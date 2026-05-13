import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';

import 'brand_splash.dart';
import 'cash_settlement_screen.dart';
import 'folder_watcher.dart';
import 'holiday_calendar_picker.dart';
import 'korean_holidays.dart';
import 'notifications.dart';
import 'pharm_tally_excel.dart';

import 'settlement_store.dart';
import 'statistics_screen.dart';
import 'widgets/calc_search_icon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 시스템 스플래시 → 매출/정산 화면 으로 곧바로 가도록 store 로드는
  // runApp 이전에 끝낸다. 시작 시 추가 브랜딩 화면을 띄우지 않아 화면이
  // 한 번만 바뀐다. (브랜딩 글자는 종료 시에 한 번만 표시.)
  await SettlementStore.instance.load();

  // 로컬 알림 초기화 (알림 탭 → payload(YYYY-MM-DD) 가 pendingTargetDate 로).
  // SalesScreen 이 이 값을 watch 해서 해당 날짜로 자동 이동한다.
  await PharmTallyNotifications.initialize();
  // 콜드 스타트가 알림 탭으로 시작된 경우, launch payload 를 미리 채워둔다.
  final launchPayload = await PharmTallyNotifications.consumeLaunchPayload();
  if (launchPayload != null && launchPayload.isNotEmpty) {
    PharmTallyNotifications.pendingTargetDate.value = launchPayload;
  }

  // 안드로이드 백그라운드 폴더 감시 작업 등록 (iOS 는 no-op).
  // 권한이 아직 없거나 폴더가 비어있어도 안전 — 콜백 안에서 가드함.
  await initializeFolderWatcher();

  runApp(const PharmTallyApp());
}

class PharmTallyApp extends StatelessWidget {
  const PharmTallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmTally',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        // 첫 프레임이 검은색·기본 다크 배경으로 잠깐 깜빡이는 것을 막기 위해
        // 앱 전역 배경을 흰색으로 고정. 네이티브 스플래시(흰 배경) → Dart
        // 스플래시(흰 배경) → 본 화면 모두 같은 배경색을 공유한다.
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR')],
      // 시작 시 추가 브랜딩 화면 없이 시스템 스플래시 → 본 화면 직행.
      // 브랜딩 글자(Developed by HSM of Orc Holdings)는 종료 시에만 BrandSplash
      // 로 한 번 표시된다.
      home: const SalesScreen(),
    );
  }
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> with WidgetsBindingObserver {
  DateTime selectedDate = DateTime.now();

  final rxController = TextEditingController(text: '0');
  final copayController = TextEditingController(text: '0');
  final cardTotalController = TextEditingController(text: '0');
  final cardCopayController = TextEditingController(text: '0');
  final bottleController = TextEditingController(text: '0');

  double cardOtc = 0;
  double salesOtc = 0;
  double cashIncome = 0;
  double grandTotal = 0;

  List<Map<String, TextEditingController>> adjRows = [];

  bool _warnedManageStoragePermission = false;

  // 안드로이드 시스템 뒤로가기: 짧은 시간 안에 두 번 누르면 앱 종료.
  DateTime? _lastBackPressedAt;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) {
      adjRows.add({
        'name': TextEditingController(),
        'value': TextEditingController(),
      });
    }
    for (var c in [cardTotalController, cardCopayController,
        copayController, bottleController]) {
      c.addListener(calculate);
    }
    SettlementStore.instance.addListener(_onStoreChanged);

    WidgetsBinding.instance.addObserver(this);

    // 알림 탭으로 들어온 날짜가 있으면 그 날짜로 자동 이동한다. 콜드
    // 스타트 시점에 채워진 값과, 앱이 떠 있는 동안 새로 도착한 알림 모두
    // 같은 ValueNotifier 를 통해 처리. 처리한 값은 곧바로 null 로 비워서
    // 같은 알림이 중복 처리되지 않게 한다.
    PharmTallyNotifications.pendingTargetDate
        .addListener(_handlePendingTargetDate);

    // 앱 첫 진입 시: 해당 날짜 파일이 있으면 자동으로 불러와 폼에 채움.
    // 동기화 앱이 파일을 잠깐 잠그는 경우 첫 읽기만 실패할 수 있어,
    // 「파일은 있는데 폼이 비어 있을 때만」 짧게 한 번 더 시도한다.
    // (매번 두 번 읽으면 두 번째가 실패했을 때 예외 처리로 폼이 통째로 비워지는 버그가 있었음.)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 알림 권한(Android 13+) 요청 — 한 번만 시도하면 됨. 거부돼도 무해.
      // 본격적인 폼 로드 전에 짧게 처리.
      await PharmTallyNotifications.requestRuntimePermissions();

      // 알림 탭으로 시작된 경우: 미리 채워둔 payload 를 소비해서 그 날짜로 이동.
      _handlePendingTargetDate();

      await _loadForDate(selectedDate, showFeedback: false);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      final folder = SettlementStore.instance.savedFolderPath.trim();
      if (folder.isEmpty) return;
      final path = await resolvePharmTallyXlsxPath(
        folder: folder,
        date: selectedDate,
      );
      if (path == null || !await File(path).exists()) return;

      final rx = int.tryParse(rxController.text.replaceAll(',', '').trim()) ?? 0;
      final cardTot =
          int.tryParse(cardTotalController.text.replaceAll(',', '').trim()) ?? 0;
      final looksEmpty = rx == 0 && cardTot == 0 && copayController.text.trim() == '0';

      if (looksEmpty) {
        await _loadForDate(selectedDate, showFeedback: false);
      }
    });
  }

  /// 알림 payload(`YYYY-MM-DD`) 가 도착하면 해당 날짜로 점프.
  void _handlePendingTargetDate() {
    final raw = PharmTallyNotifications.pendingTargetDate.value;
    if (raw == null || raw.isEmpty) return;
    final parsed = DateTime.tryParse(raw);
    PharmTallyNotifications.pendingTargetDate.value = null;
    if (parsed == null) return;
    if (!mounted) return;
    // 이미 그 날짜를 보고 있다면 다시 로드해서 새로 도착한 파일을 즉시 반영.
    final normalized = DateTime(parsed.year, parsed.month, parsed.day);
    _onDateChanged(normalized);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadForDate(selectedDate, showFeedback: false);
      });
    }
  }

  @override
  void dispose() {
    SettlementStore.instance.removeListener(_onStoreChanged);
    PharmTallyNotifications.pendingTargetDate
        .removeListener(_handlePendingTargetDate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    calculate();
  }

  void calculate() {
    double cardTotal = double.tryParse(cardTotalController.text) ?? 0;
    double cardCopay = double.tryParse(cardCopayController.text) ?? 0;
    double copay = double.tryParse(copayController.text) ?? 0;

    double adj = 0;
    for (var row in adjRows) {
      adj += double.tryParse(row['value']!.text) ?? 0;
    }

    setState(() {
      cardOtc = cardTotal - cardCopay;
      cashIncome = SettlementStore.instance.actualDeposit.toDouble();
      grandTotal = cardTotal + cashIncome + adj;
      salesOtc = grandTotal - copay;
    });
  }

  String formatNumber(double val) {
    return val.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  }

  Widget buildRow(String label, Widget input) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(child: input),
        ],
      ),
    );
  }

  Widget buildReadOnly(String label, double value, {Color color = Colors.black}) {
    return buildRow(
      label,
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          formatNumber(value),
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String formatIntegerDisplay(TextEditingController c) {
    final raw = c.text.replaceAll(',', '').trim();
    if (raw.isEmpty) return '0';
    final n = double.tryParse(raw);
    if (n == null) return c.text;
    return formatNumber(n);
  }

  String _formatAdjValueDisplay(String raw) {
    final t = raw.replaceAll(',', '').trim();
    if (t.isEmpty) return '';
    final n = double.tryParse(t);
    if (n == null) return raw;
    final neg = n < 0;
    final abs = neg ? -n : n;
    final body = formatNumber(abs);
    return neg ? '-$body' : body;
  }

  Widget buildViewerNumeric(String label, TextEditingController ctrl) {
    return buildRow(
      label,
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          formatIntegerDisplay(ctrl),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> pickDate() async {
    final picked = await showHolidayDatePicker(
      context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      await _onDateChanged(picked);
    }
  }

  /// 날짜를 [newDate]로 변경하고, 해당 날짜의 저장 파일을 자동 로드.
  Future<void> _onDateChanged(DateTime newDate) async {
    setState(() => selectedDate = newDate);
    await _loadForDate(newDate);
  }

  /// (디버그) 현재 선택된 날짜에 해당하는 파일이 폴더에 정확히 있는지,
  /// 폴더 안에 어떤 xlsx 들이 있는지 모달로 보여준다.
  Future<void> _showLoadDiagnostic() async {
    final store = SettlementStore.instance;
    final folder = store.savedFolderPath.trim();
    final lines = <String>[
      '폴더 경로: $folder',
    ];

    if (folder.isEmpty) {
      lines.add('→ 폴더가 지정되지 않음.');
    } else {
      final dir = Directory(folder);
      final exists = await dir.exists();
      lines.add('폴더 존재: $exists');
      if (exists) {
        try {
          final entries = await dir.list().toList();
          final names = entries
              .map((e) => p.basename(e.path))
              .where((n) => n.toLowerCase().endsWith('.xlsx'))
              .toList()
            ..sort();
          lines.add('xlsx 개수: ${names.length}');
          for (final n in names.take(20)) {
            lines.add(' • $n');
          }
          if (names.length > 20) lines.add(' • … (${names.length - 20}개 더)');
        } catch (e) {
          lines.add('폴더 읽기 오류: $e');
        }
      }
    }

    lines.add('');
    lines.add('찾는 파일명(표준): ${pharmTallyFileName(selectedDate)}');
    lines.add('날짜 접두어: ${pharmTallyFileNamePrefix(selectedDate)}');
    if (folder.isNotEmpty) {
      final resolved = await resolvePharmTallyXlsxPath(
        folder: folder,
        date: selectedDate,
      );
      lines.add('실제 사용 경로: ${resolved ?? "(없음)"}');
      if (resolved != null) {
        try {
          final len = await File(resolved).length();
          lines.add('파일 크기: $len byte');
        } catch (e) {
          lines.add('크기 조회 실패: $e');
        }
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로드 진단'),
        content: SingleChildScrollView(
          child: SelectableText(
            lines.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _loadForDate(selectedDate, showFeedback: false);
            },
            child: const Text('다시 로드'),
          ),
        ],
      ),
    );
  }

  /// 안드로이드 11+ 에서 `/storage/emulated/0/<…>` 임의 경로를 dart:io 로
  /// 읽고/쓰려면 "모든 파일 접근(MANAGE_EXTERNAL_STORAGE)" 권한이 필요하다.
  /// 권한이 없으면 사용자에게 안내 다이얼로그를 띄우고 시스템 설정으로 보낸다.
  /// 권한이 이미 있거나 안드로이드 외 플랫폼이면 true.
  Future<bool> _ensureStoragePermission({bool showPrompt = true}) async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    if (!showPrompt) return false;
    if (!mounted) return false;

    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('파일 접근 권한이 필요해요'),
        content: const Text(
            '폰의 OneSyncFiles 같은 일반 폴더에 엑셀을 읽고 쓰려면 '
            '"모든 파일 접근" 권한이 필요합니다.\n\n'
            '확인을 누르면 설정 화면이 열려요. 거기서 pharm_tally 의 '
            '"모든 파일 접근"을 켠 뒤, 앱으로 돌아와 다시 시도해 주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
    if (go == true) {
      await Permission.manageExternalStorage.request();
    }
    return await Permission.manageExternalStorage.isGranted;
  }

  /// 저장 폴더에서 [date]에 해당하는 xlsx 파일을 읽어 폼/스토어에 반영.
  /// 파일이 없거나 폴더가 비어 있으면 폼을 기본값으로 리셋.
  /// [showFeedback] 이 true 면 결과를 스낵바로 보여준다.
  Future<void> _loadForDate(DateTime date, {bool showFeedback = true}) async {
    if (kIsWeb) return;
    final store = SettlementStore.instance;
    final folder = store.savedFolderPath.trim();
    debugPrint('[loadForDate] date=$date folder="$folder"');
    if (folder.isEmpty) {
      if (showFeedback) _resetForm();
      return;
    }

    // 권한이 없으면 조용히 통과(첫 진입 시 다이얼로그 폭격 방지).
    // 사용자가 명시적으로 저장을 누르거나 폴더를 새로 지정할 때만 안내.
    if (!await _ensureStoragePermission(showPrompt: false)) {
      debugPrint('[loadForDate] permission not granted, skipping');
      if (folder.isNotEmpty &&
          !kIsWeb &&
          Platform.isAndroid &&
          !_warnedManageStoragePermission) {
        _warnedManageStoragePermission = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final granted = await Permission.manageExternalStorage.isGranted;
          if (!mounted || granted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '"모든 파일 접근" 권한이 꺼져 있어 엑셀 폴더를 읽지 못했습니다. 설정에서 허용해 주세요.',
              ),
              action: SnackBarAction(
                label: '설정 열기',
                onPressed: () async {
                  await openAppSettings();
                },
              ),
              duration: const Duration(seconds: 10),
            ),
          );
        });
      }
      if (showFeedback) _resetForm();
      return;
    }

    LoadedSettlement? loaded;
    String? errorMsg;
    try {
      loaded = await loadPharmTallyXlsx(folder: folder, date: date);
      debugPrint('[loadForDate] result=${loaded == null ? "no file" : "loaded"}');
    } on LoadXlsxException catch (e) {
      errorMsg = e.message;
      debugPrint('[loadForDate] LoadXlsxException: $e');
    } catch (e, st) {
      errorMsg = '예상치 못한 오류: $e';
      debugPrint('[loadForDate] unexpected: $e\n$st');
    }
    if (!mounted) return;

    if (errorMsg != null) {
      // 백그라운드(첫 진입·복귀) 재시도 중 실패 시 폼을 비우면,
      // 이미 성공한 첫 로드까지 지워지는 경우가 있음(동기화 앱 파일 잠금 등).
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('불러오기 실패: $errorMsg')),
        );
        _resetForm();
      } else {
        debugPrint('[loadForDate] silent skip after error: $errorMsg');
      }
      return;
    }

    final data = loaded;
    if (data == null) {
      // 파일이 없을 때: 조용히 폼만 초기화 (뷰어 모드에서는 스낵바 없음).
      _resetForm();
      return;
    }

    // 매출/정산 상세 입력값 반영(이 컨트롤러들엔 calculate 리스너가 붙어있어
    // .text 변경만으로도 자동 재계산됨).
    rxController.text = data.rxCount.toString();
    copayController.text = data.copay.toString();
    cardTotalController.text = data.cardTotal.toString();
    cardCopayController.text = data.cardCopay.toString();
    bottleController.text = data.bottle.toString();

    // 보정 항목 컨트롤러 재구성(최소 5행 유지). 기존 컨트롤러는
    // 위젯 트리 갱신 이후에 dispose 해서 "사용 중 dispose" 충돌을 피한다.
    final newAdjRows = <Map<String, TextEditingController>>[];
    final n = data.adjustments.length > 5 ? data.adjustments.length : 5;
    for (int i = 0; i < n; i++) {
      final adj = i < data.adjustments.length ? data.adjustments[i] : null;
      newAdjRows.add({
        'name': TextEditingController(text: adj?.name ?? ''),
        'value': TextEditingController(
          text: (adj == null || adj.amount == 0) ? '' : adj.amount.toString(),
        ),
      });
    }
    final oldAdjRows = adjRows;
    setState(() {
      adjRows = newAdjRows;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in oldAdjRows) {
        row['name']?.dispose();
        row['value']?.dispose();
      }
    });

    // 현금정산/메모/작성자는 스토어를 통해 두 화면이 공유.
    store.update(() {
      if (data.author.isNotEmpty) store.author = data.author;
      store.baseCash = data.baseCash;
      store.c1000 = data.c1000;
      store.c5000 = data.c5000;
      store.c10000 = data.c10000;
      store.c50000 = data.c50000;
      store.b5000 = data.b5000;
      store.b10000 = data.b10000;
      store.b25000 = data.b25000;
      store.b50000 = data.b50000;
      store.b100000 = data.b100000;
      store.memo = data.memo;
    });

    calculate();
  }

  /// 해당 날짜에 저장된 파일이 없을 때 폼/스토어를 기본값으로 되돌림.
  void _resetForm() {
    if (!mounted) return;

    rxController.text = '0';
    copayController.text = '0';
    cardTotalController.text = '0';
    cardCopayController.text = '0';
    bottleController.text = '0';

    final newAdjRows = <Map<String, TextEditingController>>[];
    for (int i = 0; i < 5; i++) {
      newAdjRows.add({
        'name': TextEditingController(),
        'value': TextEditingController(),
      });
    }
    final oldAdjRows = adjRows;
    setState(() {
      adjRows = newAdjRows;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in oldAdjRows) {
        row['name']?.dispose();
        row['value']?.dispose();
      }
    });

    // 작성자(author) 와 시제(baseCash) 는 "설정성" 값이므로 날짜 변경 시
    // 리셋하지 않고 유지한다. 그 외 거래/카운트 데이터만 0으로 돌린다.
    final store = SettlementStore.instance;
    store.update(() {
      store.c1000 = 0;
      store.c5000 = 0;
      store.c10000 = 0;
      store.c50000 = 0;
      store.b5000 = 0;
      store.b10000 = 0;
      store.b25000 = 0;
      store.b50000 = 0;
      store.b100000 = 0;
      store.memo = '';
    });

    calculate();
  }

  String get dateStr {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${selectedDate.year}-${selectedDate.month.toString().padLeft(2,'0')}-${selectedDate.day.toString().padLeft(2,'0')} (${days[selectedDate.weekday - 1]})';
  }

  void _openStatistics() {
    // 통계 화면 진입 시, 매출/정산 화면에서 보고 있던 날짜(`selectedDate`)
    // 가 속한 달의 1일 ~ 말일을 기본 조회 범위로 사용한다. 현금정산 화면
    // 에서 통계 버튼을 누르더라도, 그 화면에서 날짜를 바꾸면 콜백으로
    // selectedDate 가 동기화되어 있으므로 같은 기준이 적용된다.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatisticsScreen(initialDate: selectedDate),
      ),
    );
  }

  /// 통계 버튼 옆 "불러오기" 아이콘: 폴더를 고르면 그 경로를 저장하고
  /// 곧바로 현재 날짜의 엑셀을 읽어 폼에 채운다. (기존 "데이터폴더설정" 대체)
  Future<void> _pickFolderAndLoad() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '웹에서는 폴더 선택을 사용할 수 없습니다. Windows 데스크톱(또는 안드로이드)에서 실행해 주세요.'),
        ),
      );
      return;
    }

    if (!await _ensureStoragePermission()) return;

    String? dir;
    try {
      dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: '엑셀 데이터 폴더 선택');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('폴더 선택 중 오류: $e')),
      );
      return;
    }

    if (!mounted) return;
    if (dir == null || dir.trim().isEmpty) return;

    final store = SettlementStore.instance;
    store.update(() => store.savedFolderPath = dir!);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('폴더 지정: $dir')),
    );

    await _loadForDate(selectedDate);
  }

  /// 종료 브랜딩 화면이 이미 떠있는지 막는 가드. 사용자가 빠르게
  /// 뒤로가기를 연타할 때 같은 화면이 여러 번 push 되지 않도록 한다.
  bool _exitingWithSplash = false;

  /// 안드로이드 시스템 뒤로가기를 가로채서 "두 번 눌러 종료" 패턴을 구현.
  /// 첫 번째 누름은 화면 하단에 스낵바로 안내만 띄우고, 2초 안에 다시
  /// 누르면 같은 브랜딩 화면을 잠깐 보여준 뒤 [SystemNavigator.pop] 으로
  /// 앱을 종료한다.
  void _handleSystemBack() {
    if (_exitingWithSplash) return;

    final now = DateTime.now();
    final last = _lastBackPressedAt;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            '한 번 더 누르면 종료합니다',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(40, 0, 40, 24),
        ),
      );
      return;
    }

    _exitingWithSplash = true;
    // 시작 화면과 동일한 디자인의 종료용 브랜딩 화면을 전체 화면으로
    // 띄우고, 짧은 지연 뒤 시스템에 앱 종료를 요청.
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => const PopScope(
          // 종료 화면에서 또 뒤로가기를 눌러도 본 화면으로 못 돌아가게.
          canPop: false,
          child: BrandSplash(tagline: 'Developed by HSM of Orc Holdings.'),
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1100), () {
      SystemNavigator.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '통계',
                    icon: const Icon(Icons.bar_chart, color: Colors.indigo),
                    onPressed: _openStatistics,
                  ),
                  const Spacer(),
                  const Text('[매출/정산 상세]',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo)),
                  const Spacer(),
                  IconButton(
                    tooltip: '불러오기 (폴더 지정 후 자동 로드)',
                    icon: const Icon(Icons.folder, color: Color(0xFFFFA000)),
                    onPressed: _pickFolderAndLoad,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => _onDateChanged(DateTime.now()),
                      child: const Text('오늘'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _onDateChanged(
                          selectedDate.subtract(const Duration(days: 1))),
                    ),
                    // 달력과 같은 라이브러리 계열 제스처: 좌우 스와이프는 버튼과 분리된 영역에서만 받음.
                    Expanded(
                      child: SimpleGestureDetector(
                        behavior: HitTestBehavior.opaque,
                        swipeConfig: const SimpleSwipeConfig(
                          horizontalThreshold: 40,
                          swipeDetectionBehavior:
                              SwipeDetectionBehavior.singularOnEnd,
                        ),
                        onHorizontalSwipe: (dir) {
                          if (dir == SwipeDirection.right) {
                            _onDateChanged(
                              selectedDate.add(const Duration(days: 1)),
                            );
                          } else {
                            _onDateChanged(
                              selectedDate.subtract(const Duration(days: 1)),
                            );
                          }
                        },
                        onTap: pickDate,
                        onLongPress: _showLoadDiagnostic,
                        child: Center(
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: KoreanHolidays.dateBarColor(selectedDate),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _onDateChanged(
                          selectedDate.add(const Duration(days: 1))),
                    ),
                    // 현금정산 버튼: 같은 줄 오른쪽 끝.
                    IconButton(
                      tooltip: '현금정산',
                      icon: const CalcSearchIcon(width: 52, height: 38),
                      iconSize: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CashSettlementScreen(
                              date: selectedDate,
                              // 현금정산 화면에서 날짜를 바꾸면 매출/정산
                              // 화면도 그 날짜의 파일을 로드하도록 위임.
                              onDateChanged: (newDate) {
                                _onDateChanged(newDate);
                              },
                              // 통계/폴더 버튼도 매출/정산 화면의 동일한
                              // 동작(통계 화면 push, 폴더 선택 + 로드)을
                              // 그대로 위임받아 사용한다.
                              onOpenStatistics: _openStatistics,
                              onPickFolder: _pickFolderAndLoad,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                child: SelectionContainer.disabled(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            buildViewerNumeric('처방전수', rxController),
            buildViewerNumeric('본인부담금', copayController),
            buildViewerNumeric('카드매출(총매출)', cardTotalController),
            buildViewerNumeric('카드매출(본인부담금)', cardCopayController),
            buildReadOnly('카드매출(일반약)', cardOtc, color: Colors.blue),
            buildReadOnly('매약(일반약)', salesOtc, color: Colors.red),
            buildViewerNumeric('통약', bottleController),
            buildReadOnly('현금 수입(현입)', cashIncome, color: Colors.green),
            buildReadOnly('매출총액(카드+현금+보정)', grandTotal),

            const Divider(height: 24),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '--- 보정 및 기타 ---',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            ...adjRows.asMap().entries.map((entry) {
              int i = entry.key;
              var row = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          row['name']!.text,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatAdjValueDisplay(row['value']!.text),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

                    ],
                  ),
                ),
              ),
            ),
            // 화면 맨 아래 고정 브랜딩 배지. 스크롤되지 않는 푸터로 표시.
            const BrandTaglineBadge(),
          ],
        ),
      ),
      ),
    );
  }
}