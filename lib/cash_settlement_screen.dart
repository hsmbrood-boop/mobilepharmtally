import 'package:flutter/material.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';

import 'brand_splash.dart';
import 'holiday_calendar_picker.dart';
import 'korean_holidays.dart';
import 'settlement_store.dart';
import 'widgets/calc_search_icon.dart';

class CashSettlementScreen extends StatefulWidget {
  const CashSettlementScreen({
    super.key,
    required this.date,
    this.onDateChanged,
    this.onOpenStatistics,
    this.onPickFolder,
  });

  final DateTime date;

  /// 현금정산 화면에서 날짜가 바뀔 때마다 호출. 부모(매출/정산 화면)에서
  /// 해당 날짜의 엑셀을 다시 로드해 [SettlementStore] 를 갱신해 주는 용도.
  final ValueChanged<DateTime>? onDateChanged;

  /// 통계 화면을 여는 콜백. 매출/정산 화면의 `_openStatistics` 를 그대로
  /// 위임받아 호출하면 같은 통계 화면이 동일한 방식으로 뜬다.
  final VoidCallback? onOpenStatistics;

  /// 폴더 지정 + 자동 로드 콜백. 매출/정산 화면의 `_pickFolderAndLoad` 를
  /// 그대로 위임받아 호출. 권한 처리·다이얼로그·스낵바 모두 부모가 책임진다.
  final VoidCallback? onPickFolder;

  @override
  State<CashSettlementScreen> createState() => _CashSettlementScreenState();
}

class _CashSettlementScreenState extends State<CashSettlementScreen> {
  final SettlementStore _store = SettlementStore.instance;

  late DateTime _date;

  // `_onStoreChanged` 가 컨트롤러 텍스트를 동기화할 때, 그 변경으로 인해
  // 컨트롤러 리스너 → `_store.update` → notifyListeners → 다시 동기화 …
  // 의 무한 루프가 생기지 않도록 막는 가드.
  bool _syncing = false;

  late final TextEditingController authorController;
  late final TextEditingController baseCashController;
  late final TextEditingController c1000;
  late final TextEditingController c5000;
  late final TextEditingController c10000;
  late final TextEditingController c50000;
  late final TextEditingController b5000;
  late final TextEditingController b10000;
  late final TextEditingController b25000;
  late final TextEditingController b50000;
  late final TextEditingController b100000;
  late final TextEditingController memoController;

  int _i(TextEditingController c) => int.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  String _fmtInt(int v) {
    final s = v.toString();
    final reg = RegExp(r'(\d)(?=(\d{3})+$)');
    return s.replaceAllMapped(reg, (m) => '${m[1]},');
  }

  int get smallBillsSum => _store.smallBillsSum;
  int get bigBillsTotal => _store.bigBillsTotal;
  int get bundlesSum => _store.bundlesSum;
  int get baseCash => _store.baseCash;
  int get missing => _store.missing;
  int get autoKeep => _store.autoKeep;
  int get actualDeposit => _store.actualDeposit;

  String get _dateStr {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final d = _date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} (${days[d.weekday - 1]})';
  }

  void _changeDate(DateTime newDate) {
    if (newDate.year == _date.year &&
        newDate.month == _date.month &&
        newDate.day == _date.day) {
      return;
    }
    setState(() => _date = newDate);
    widget.onDateChanged?.call(newDate);
  }

  Future<void> _pickDate() async {
    final picked = await showHolidayDatePicker(
      context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) _changeDate(picked);
  }

  @override
  void initState() {
    super.initState();
    _date = widget.date;
    authorController = TextEditingController(text: _store.author);
    baseCashController = TextEditingController(text: _store.baseCash.toString());
    c1000 = TextEditingController(text: _store.c1000.toString());
    c5000 = TextEditingController(text: _store.c5000.toString());
    c10000 = TextEditingController(text: _store.c10000.toString());
    c50000 = TextEditingController(text: _store.c50000.toString());
    b5000 = TextEditingController(text: _store.b5000.toString());
    b10000 = TextEditingController(text: _store.b10000.toString());
    b25000 = TextEditingController(text: _store.b25000.toString());
    b50000 = TextEditingController(text: _store.b50000.toString());
    b100000 = TextEditingController(text: _store.b100000.toString());
    memoController = TextEditingController(text: _store.memo);

    authorController.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.author = authorController.text);
    });
    baseCashController.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.baseCash = _i(baseCashController));
    });
    c1000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.c1000 = _i(c1000));
    });
    c5000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.c5000 = _i(c5000));
    });
    c10000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.c10000 = _i(c10000));
    });
    c50000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.c50000 = _i(c50000));
    });
    b5000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.b5000 = _i(b5000));
    });
    b10000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.b10000 = _i(b10000));
    });
    b25000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.b25000 = _i(b25000));
    });
    b50000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.b50000 = _i(b50000));
    });
    b100000.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.b100000 = _i(b100000));
    });
    memoController.addListener(() {
      if (_syncing) return;
      _store.update(() => _store.memo = memoController.text);
    });

    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // store 가 바뀌었으므로(부모에서 _loadForDate 로 갱신된 경우 포함) 표시
    // 중인 컨트롤러 텍스트도 다시 맞춰 준다. _syncing 가드로 인해 이 동기화는
    // 리스너 → store.update 의 역방향 갱신을 트리거하지 않는다.
    _syncing = true;
    void s(TextEditingController c, String v) {
      if (c.text != v) c.text = v;
    }
    s(authorController, _store.author);
    s(baseCashController, _store.baseCash.toString());
    s(c1000, _store.c1000.toString());
    s(c5000, _store.c5000.toString());
    s(c10000, _store.c10000.toString());
    s(c50000, _store.c50000.toString());
    s(b5000, _store.b5000.toString());
    s(b10000, _store.b10000.toString());
    s(b25000, _store.b25000.toString());
    s(b50000, _store.b50000.toString());
    s(b100000, _store.b100000.toString());
    s(memoController, _store.memo);
    _syncing = false;
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    authorController.dispose();
    baseCashController.dispose();
    c1000.dispose();
    c5000.dispose();
    c10000.dispose();
    c50000.dispose();
    b5000.dispose();
    b10000.dispose();
    b25000.dispose();
    b50000.dispose();
    b100000.dispose();
    memoController.dispose();
    super.dispose();
  }

  Widget _row({
    required String label,
    required Widget right,
    Color? bg,
    double labelWidth = 170,
  }) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _viewerNumeric(TextEditingController c, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerRight,
      child: Text(
        _fmtInt(_i(c)),
        textAlign: TextAlign.right,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: textColor ?? Colors.black87,
        ),
      ),
    );
  }

  Widget _roNumber(int v, {Color color = Colors.black}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _fmtInt(v),
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 첫 줄: 매출/정산 화면과 동일한 [통계] ··· [타이틀] ··· [폴더] 구성.
            // 같은 패딩·높이·자식 구조라서 두 화면에서 타이틀·둘째 줄·전환
            // 버튼의 Y 좌표가 정확히 일치한다.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '통계',
                    icon: const Icon(Icons.bar_chart, color: Colors.indigo),
                    onPressed: widget.onOpenStatistics,
                  ),
                  const Spacer(),
                  const Text(
                    '[현금정산]',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '불러오기 (폴더 지정 후 자동 로드)',
                    icon: const Icon(Icons.folder, color: Color(0xFFFFA000)),
                    onPressed: widget.onPickFolder,
                  ),
                ],
              ),
            ),
            // 둘째 줄: [오늘] [<] [날짜] [>] [매출/정산으로 가는 버튼]
            // → 매출/정산 화면의 둘째 줄과 동일한 패딩(fromLTRB(12, 4, 12, 0))
            //   과 동일한 SizedBox(height: 52) 를 사용해 같은 화면 좌표에 배치.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => _changeDate(DateTime.now()),
                      child: const Text('오늘'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeDate(
                          _date.subtract(const Duration(days: 1))),
                    ),
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
                            _changeDate(_date.add(const Duration(days: 1)));
                          } else {
                            _changeDate(
                                _date.subtract(const Duration(days: 1)));
                          }
                        },
                        onTap: _pickDate,
                        child: Center(
                          child: Text(
                            _dateStr,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: KoreanHolidays.dateBarColor(_date),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () =>
                          _changeDate(_date.add(const Duration(days: 1))),
                    ),
                    // 매출/정산 상세로 돌아가는 버튼: 매출/정산 화면의 현금정산
                    // 버튼과 동일한 크기/패딩/오프셋으로 둘째 줄 오른쪽 끝.
                    IconButton(
                      tooltip: '매출/정산 상세로',
                      icon: const CalcSearchIcon(width: 52, height: 38),
                      iconSize: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                child: SelectionContainer.disabled(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              Row(
                children: [
                  const Text('작성자', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        authorController.text,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _row(
                label: '시제 (기본준비금)',
                right: _viewerNumeric(baseCashController),
                bg: Colors.grey[100],
              ),
              _row(
                label: '부족한 시제',
                right: _roNumber(missing, color: Colors.red),
                bg: Colors.yellow[50],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),

              _row(label: '1,000원권 (장)', right: _viewerNumeric(c1000)),
              _row(label: '5,000원권 (장)', right: _viewerNumeric(c5000)),
              _row(
                label: '합산(1천원권+5천원권)',
                right: _roNumber(smallBillsSum, color: Colors.blue),
                bg: Colors.lightBlue[50],
              ),
              _row(label: '10,000원권 (장)', right: _viewerNumeric(c10000)),
              _row(label: '50,000원권 (장)', right: _viewerNumeric(c50000)),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text('[밑에돈]', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),

              _row(label: '5,000원 묶음 (개)', right: _viewerNumeric(b5000)),
              _row(label: '10,000원 묶음 (개)', right: _viewerNumeric(b10000)),
              _row(label: '25,000원 묶음 (개)', right: _viewerNumeric(b25000)),
              _row(label: '50,000원 묶음 (개)', right: _viewerNumeric(b50000)),
              _row(label: '100,000원 묶음 (개)', right: _viewerNumeric(b100000)),
            _row(
              label: '밑에돈 총합계',
              right: _roNumber(bundlesSum, color: Colors.blue),
              bg: Colors.lightBlue[50],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            _row(
              label: '남기는금액(1만+5만)',
              right: _roNumber(autoKeep, color: Colors.green),
              bg: Colors.green[50],
            ),
            _row(
              label: '실제 입금액',
              right: _roNumber(actualDeposit, color: Colors.red),
              bg: Colors.grey[100],
            ),

            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      '특이사항 (메모)',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.topLeft,
                      child: Text(
                        memoController.text,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            // 화면 맨 아래 고정 브랜딩 배지. 매출/정산 화면과 동일한 위치.
            const BrandTaglineBadge(),
          ],
        ),
      ),
    );
  }
}

