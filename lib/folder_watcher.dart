import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notifications.dart';

/// 백그라운드 작업 이름.
const String kPharmTallyWatchTask = 'pharm_tally_folder_watch';

/// `SettlementStore` 가 사용하는 키와 동일. 백그라운드 isolate 에서도
/// 같은 SharedPreferences 항목을 읽기 위해 직접 값을 맞춰둔다.
const String _kFolderPathKey = 'pharm_tally.savedFolderPath';

/// 마지막으로 폴더를 스캔한 시각(ms). 다음 스캔에서 이보다 새로 생성/수정된
/// 파일만 "새 파일" 로 간주한다.
const String _kLastScanMillisKey = 'pharm_tally.folderWatch.lastScanMillis';

/// 이미 알림을 보낸 파일 이름 목록. 같은 파일에 대해 동기화가 여러 번 일어나도
/// 알림은 한 번만 가도록 중복을 방지. 너무 커지지 않게 최근 500개만 유지.
const String _kSeenFilesKey = 'pharm_tally.folderWatch.seenFiles';


/// WorkManager 콜백. **반드시 top-level / static 이어야 하며,
/// `@pragma('vm:entry-point')` 가 붙어 있어야 release 모드에서 살아남는다.**
@pragma('vm:entry-point')
void pharmTallyCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kPharmTallyWatchTask) return true;
    try {
      // 백그라운드 isolate 는 알림 플러그인을 새로 초기화해야 한다.
      await PharmTallyNotifications.initialize();
      await pharmTallyScanFolderAndNotify();
    } catch (e, st) {
      debugPrint('[folder_watch] error: $e\n$st');
    }
    return true;
  });
}

/// 저장된 폴더를 한 번 스캔해서 새 엑셀 파일이 있으면 알림을 보낸다.
///
/// WorkManager 주기 작업과 포그라운드 서비스(짧은 주기) 양쪽에서 같은 로직을
/// 공유한다. 중복 알림은 `_kSeenFilesKey` 로 방지하므로 두 경로가 같은 파일을
/// 동시에 봐도 알림은 한 번만 간다. 호출 전 [PharmTallyNotifications.initialize]
/// 가 끝나 있어야 한다.
Future<void> pharmTallyScanFolderAndNotify() async {
  // 안드로이드 외 플랫폼에서는 동작하지 않음 (iOS 는 WorkManager 미지원).
  if (kIsWeb || !Platform.isAndroid) return;

  final prefs = await SharedPreferences.getInstance();
  final folder = (prefs.getString(_kFolderPathKey) ?? '').trim();
  if (folder.isEmpty) {
    debugPrint('[folder_watch] saved folder path is empty, skip.');
    return;
  }

  final dir = Directory(folder);
  if (!await dir.exists()) {
    debugPrint('[folder_watch] folder does not exist: $folder');
    return;
  }

  final lastScanMillis = prefs.getInt(_kLastScanMillisKey) ?? 0;
  final lastScan = DateTime.fromMillisecondsSinceEpoch(lastScanMillis);
  final seen =
      (prefs.getStringList(_kSeenFilesKey) ?? const <String>[]).toSet();

  // 이번 스캔 도중에 발견한 신규 파일.
  final newEntries = <_NewEntry>[];

  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final lower = name.toLowerCase();
      if (!lower.endsWith('.xlsx')) continue;
      // OneDrive / Excel 임시 잠금 파일 (`~$2026-05-13 (수).xlsx` 등) 제외.
      if (name.startsWith('~')) continue;

      final stat = await entity.stat();
      final modified = stat.modified;

      final isNewer = modified.isAfter(lastScan);
      final notSeen = !seen.contains(name);
      if (isNewer && notSeen) {
        newEntries.add(_NewEntry(name: name, modified: modified));
      }
    }
  } catch (e) {
    debugPrint('[folder_watch] listing failed: $e');
    return;
  }

  // 오래된 파일부터 알림이 가도록 정렬 (사용자가 알림센터에서 자연스럽게 봄).
  newEntries.sort((a, b) => a.modified.compareTo(b.modified));

  // 한 번의 동기화로 여러 파일이 들어오면 최대 5개까지만 개별 알림.
  // 그 이상이면 합쳐서 1개 요약 알림으로 정리.
  const int maxIndividualNotifications = 5;
  if (newEntries.length <= maxIndividualNotifications) {
    for (final e in newEntries) {
      await PharmTallyNotifications.notifyNewExcel(
        fileName: e.name,
        payloadIsoDate: _extractIsoDate(e.name),
      );
      seen.add(e.name);
    }
  } else {
    // 요약 알림 1개 + 최신 파일의 날짜를 payload 로 사용.
    final latest = newEntries.last;
    await PharmTallyNotifications.notifyNewExcel(
      fileName:
          '${newEntries.length}개 파일이 새로 도착했습니다 (최신: ${latest.name})',
      payloadIsoDate: _extractIsoDate(latest.name),
    );
    for (final e in newEntries) {
      seen.add(e.name);
    }
  }

  // 다음 스캔의 기준 시각 = 이번 스캔 시작 시각.
  await prefs.setInt(
    _kLastScanMillisKey,
    DateTime.now().millisecondsSinceEpoch,
  );

  // seen 목록은 최근 500개만 유지 (`Set` → `List` 정렬 후 잘라내기).
  const int maxSeen = 500;
  final seenList = seen.toList()..sort();
  if (seenList.length > maxSeen) {
    seenList.removeRange(0, seenList.length - maxSeen);
  }
  await prefs.setStringList(_kSeenFilesKey, seenList);

  debugPrint(
    '[folder_watch] scanned "$folder": '
    '${newEntries.length} new file(s) since $lastScan',
  );
}

class _NewEntry {
  final String name;
  final DateTime modified;
  _NewEntry({required this.name, required this.modified});
}

/// 파일명 앞부분이 `YYYY-MM-DD` 인 경우 그 날짜 문자열을 반환. 매칭되지
/// 않으면 null. (예: `2026-05-13 (수).xlsx` → `2026-05-13`)
String? _extractIsoDate(String fileName) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(fileName);
  if (m == null) return null;
  return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
}

/// 앱 시작 시 한 번 호출. WorkManager 초기화 + 주기 작업 등록.
///
/// iOS 는 WorkManager 가 지원하지 않으므로 no-op. (iOS 에서 동일 기능을 원할 때는
/// BackgroundTasks / BGTaskScheduler 를 별도로 도입해야 함.)
Future<void> initializeFolderWatcher() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await Workmanager().initialize(
      pharmTallyCallbackDispatcher,
      isInDebugMode: false,
    );
    // 안드로이드 WorkManager 의 최소 주기는 15분.
    await Workmanager().registerPeriodicTask(
      kPharmTallyWatchTask,
      kPharmTallyWatchTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
  } catch (e, st) {
    debugPrint('[folder_watch] initialize failed: $e\n$st');
  }
}

/// 배터리 최적화(도즈)에서 이 앱을 제외해 달라고 사용자에게 요청한다.
///
/// 도즈가 깊어지면 15분 주기 백그라운드 스캔이 밤에 1~2시간씩 밀린다.
/// 최적화에서 제외되면 주기에 훨씬 가깝게(거의 15분마다) 실행된다.
/// (주기 자체를 15분보다 짧게 만들지는 못함 — 그건 WorkManager 의 OS 하한.)
///
/// 아직 제외되지 않았다면 앱을 켤 때마다 다시 요청한다. 한 번 거부했다고
/// 영영 묻지 않으면 도즈 지연이 계속 남기 때문. 이미 제외돼 있으면
/// `isGranted` 로 곧바로 빠져나가므로 다이얼로그는 더 이상 뜨지 않는다.
Future<void> requestIgnoreBatteryOptimizations() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    // 이미 제외돼 있으면 아무것도 안 함 (다이얼로그도 안 뜸).
    if (await Permission.ignoreBatteryOptimizations.isGranted) return;

    // 아직 제외 안 됨 → 시스템 다이얼로그("배터리 최적화를 사용 안 함으로
    // 설정할까요?")를 띄운다. 사용자가 허용할 때까지 다음 실행에서도 다시 뜬다.
    await Permission.ignoreBatteryOptimizations.request();
  } catch (e, st) {
    debugPrint('[folder_watch] battery opt request failed: $e\n$st');
  }
}
