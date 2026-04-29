import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'settlement_store.dart';

class CashSettlementScreen extends StatefulWidget {
  const CashSettlementScreen({super.key, required this.date});

  final DateTime date;

  @override
  State<CashSettlementScreen> createState() => _CashSettlementScreenState();
}

class _CashSettlementScreenState extends State<CashSettlementScreen> {
  final SettlementStore _store = SettlementStore.instance;

  late final TextEditingController authorController;
  bool authorFixed = true;

  late final TextEditingController baseCashController;
  bool baseCashFixed = false;

  late final TextEditingController c1000;
  bool c1000Fixed = false;
  late final TextEditingController c5000;
  bool c5000Fixed = false;
  late final TextEditingController c10000;
  bool c10000Fixed = false;
  late final TextEditingController c50000;
  bool c50000Fixed = false;

  late final TextEditingController b5000;
  bool b5000Fixed = false;
  late final TextEditingController b10000;
  bool b10000Fixed = false;
  late final TextEditingController b25000;
  bool b25000Fixed = false;
  late final TextEditingController b50000;
  bool b50000Fixed = false;
  late final TextEditingController b100000;
  bool b100000Fixed = false;

  late final TextEditingController folderController;
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
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} (${days[d.weekday - 1]})';
  }

  @override
  void initState() {
    super.initState();
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
    folderController = TextEditingController(text: _store.savedFolderPath);
    memoController = TextEditingController(text: _store.memo);

    authorController.addListener(() {
      _store.update(() => _store.author = authorController.text);
    });
    baseCashController.addListener(() {
      _store.update(() => _store.baseCash = _i(baseCashController));
    });
    c1000.addListener(() {
      _store.update(() => _store.c1000 = _i(c1000));
    });
    c5000.addListener(() {
      _store.update(() => _store.c5000 = _i(c5000));
    });
    c10000.addListener(() {
      _store.update(() => _store.c10000 = _i(c10000));
    });
    c50000.addListener(() {
      _store.update(() => _store.c50000 = _i(c50000));
    });
    b5000.addListener(() {
      _store.update(() => _store.b5000 = _i(b5000));
    });
    b10000.addListener(() {
      _store.update(() => _store.b10000 = _i(b10000));
    });
    b25000.addListener(() {
      _store.update(() => _store.b25000 = _i(b25000));
    });
    b50000.addListener(() {
      _store.update(() => _store.b50000 = _i(b50000));
    });
    b100000.addListener(() {
      _store.update(() => _store.b100000 = _i(b100000));
    });
    folderController.addListener(() {
      _store.update(() => _store.savedFolderPath = folderController.text);
    });
    memoController.addListener(() {
      _store.update(() => _store.memo = memoController.text);
    });

    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
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
    folderController.dispose();
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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

  Widget _fixedToggle(bool v, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('고정', style: TextStyle(fontSize: 12)),
        Checkbox(
          value: v,
          visualDensity: VisualDensity.compact,
          onChanged: (nv) => onChanged(nv ?? false),
        ),
      ],
    );
  }

  Widget _numField(TextEditingController c, {required bool fixed, Color? textColor}) {
    return TextField(
      controller: c,
      readOnly: fixed,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
        fillColor: fixed ? Colors.grey[100] : null,
        filled: fixed,
      ),
    );
  }

  Widget _roNumber(int v, {Color color = Colors.black}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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

  void _reset() {
    baseCashController.text = '1000000';
    for (final c in [c1000, c5000, c10000, c50000, b5000, b10000, b25000, b50000, b100000]) {
      c.text = '0';
    }
    memoController.clear();
  }

  Future<void> _pickExcelFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '엑셀 저장 폴더 선택');
    if (!mounted) return;
    if (dir == null || dir.trim().isEmpty) return;

    setState(() => folderController.text = dir);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('엑셀 폴더 지정: $dir')),
    );
  }

  void _confirmAndBack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('현금정산 입력을 적용했습니다. 메인 화면의 저장 버튼으로 엑셀에 기록하세요.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '입력 적용 후 메인으로',
          icon: const Icon(Icons.check, color: Colors.white),
          onPressed: _confirmAndBack,
        ),
        title: const Text('[현금정산]', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // 헤더 라인 (정산 초기화 / 타이틀 / 작성자)
            Row(
              children: [
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: _reset,
                    child: const Text('정산 초기화', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '[현금정산]',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '매출/정산 상세로',
                      icon: const Icon(Icons.arrow_forward, color: Colors.indigo),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Spacer(),
                const Text('작성자', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                _fixedToggle(authorFixed, (nv) => setState(() => authorFixed = nv)),
                SizedBox(width: 110, child: TextField(controller: authorController, readOnly: authorFixed)),
              ],
            ),
            const SizedBox(height: 10),
            Text(_dateStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // 시제 / 부족한 시제
            _row(
              label: '시제 (기본준비금)',
              right: Row(
                children: [
                  _fixedToggle(baseCashFixed, (nv) => setState(() => baseCashFixed = nv)),
                  Expanded(child: _numField(baseCashController, fixed: baseCashFixed)),
                ],
              ),
              bg: Colors.grey[100],
            ),
            _row(
              label: '부족한 시제',
              right: _roNumber(missing, color: Colors.red),
              bg: Colors.yellow[50],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),

            // 권종
            _row(
              label: '1,000원권 (장)',
              right: Row(
                children: [
                  _fixedToggle(c1000Fixed, (nv) => setState(() => c1000Fixed = nv)),
                  Expanded(child: _numField(c1000, fixed: c1000Fixed)),
                ],
              ),
            ),
            _row(
              label: '5,000원권 (장)',
              right: Row(
                children: [
                  _fixedToggle(c5000Fixed, (nv) => setState(() => c5000Fixed = nv)),
                  Expanded(child: _numField(c5000, fixed: c5000Fixed)),
                ],
              ),
            ),
            _row(
              label: '합산(1천원권+5천원권)',
              right: _roNumber(smallBillsSum, color: Colors.blue),
              bg: Colors.lightBlue[50],
            ),
            _row(
              label: '10,000원권 (장)',
              right: Row(
                children: [
                  _fixedToggle(c10000Fixed, (nv) => setState(() => c10000Fixed = nv)),
                  Expanded(child: _numField(c10000, fixed: c10000Fixed)),
                ],
              ),
            ),
            _row(
              label: '50,000원권 (장)',
              right: Row(
                children: [
                  _fixedToggle(c50000Fixed, (nv) => setState(() => c50000Fixed = nv)),
                  Expanded(child: _numField(c50000, fixed: c50000Fixed)),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text('[밀어돈]', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),

            _row(
              label: '5,000원 묶음 (개)',
              right: Row(
                children: [
                  _fixedToggle(b5000Fixed, (nv) => setState(() => b5000Fixed = nv)),
                  Expanded(child: _numField(b5000, fixed: b5000Fixed)),
                ],
              ),
            ),
            _row(
              label: '10,000원 묶음 (개)',
              right: Row(
                children: [
                  _fixedToggle(b10000Fixed, (nv) => setState(() => b10000Fixed = nv)),
                  Expanded(child: _numField(b10000, fixed: b10000Fixed)),
                ],
              ),
            ),
            _row(
              label: '25,000원 묶음 (개)',
              right: Row(
                children: [
                  _fixedToggle(b25000Fixed, (nv) => setState(() => b25000Fixed = nv)),
                  Expanded(child: _numField(b25000, fixed: b25000Fixed)),
                ],
              ),
            ),
            _row(
              label: '50,000원 묶음 (개)',
              right: Row(
                children: [
                  _fixedToggle(b50000Fixed, (nv) => setState(() => b50000Fixed = nv)),
                  Expanded(child: _numField(b50000, fixed: b50000Fixed)),
                ],
              ),
            ),
            _row(
              label: '100,000원 묶음 (개)',
              right: Row(
                children: [
                  _fixedToggle(b100000Fixed, (nv) => setState(() => b100000Fixed = nv)),
                  Expanded(child: _numField(b100000, fixed: b100000Fixed)),
                ],
              ),
            ),
            _row(
              label: '밀어돈 총합계',
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

            const SizedBox(height: 10),
            _row(
              label: '저장폴더설정',
              right: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: folderController,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _pickExcelFolder,
                      icon: const Icon(Icons.file_open),
                      label: const Text('불러오기'),
                    ),
                  ),
                ],
              ),
              labelWidth: 120,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 120,
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('특이사항 (메모)', style: TextStyle(fontSize: 14)),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: TextField(
                      controller: memoController,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

