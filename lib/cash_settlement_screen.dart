import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'settlement_store.dart';
import 'widgets/calc_search_icon.dart';

class CashSettlementScreen extends StatefulWidget {
  const CashSettlementScreen({super.key, required this.date});

  final DateTime date;

  @override
  State<CashSettlementScreen> createState() => _CashSettlementScreenState();
}

class _CashSettlementScreenState extends State<CashSettlementScreen> {
  final SettlementStore _store = SettlementStore.instance;

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

  Widget _numField(TextEditingController c, {Color? textColor}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(),
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
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '웹에서는 폴더 선택을 사용할 수 없습니다. Windows 데스크톱(또는 안드로이드)에서 실행해 주세요.'),
        ),
      );
      return;
    }
    try {
      final dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: '엑셀 저장 폴더 선택');
      if (!mounted) return;
      if (dir == null || dir.trim().isEmpty) return;

      setState(() => folderController.text = dir);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('엑셀 폴더 지정: $dir')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('폴더 선택 중 오류: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Tooltip(
                    message: '정산 초기화',
                    child: InkWell(
                      onTap: _reset,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFE8F1F8), Color(0xFFC9DEEC)],
                          ),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Color(0xFFF1925A),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '[현금정산]',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const Spacer(),
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
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _dateStr,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('작성자', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: authorController,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _row(
                label: '시제 (기본준비금)',
                right: _numField(baseCashController),
                bg: Colors.grey[100],
              ),
              _row(
                label: '부족한 시제',
                right: _roNumber(missing, color: Colors.red),
                bg: Colors.yellow[50],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),

              _row(label: '1,000원권 (장)', right: _numField(c1000)),
              _row(label: '5,000원권 (장)', right: _numField(c5000)),
              _row(
                label: '합산(1천원권+5천원권)',
                right: _roNumber(smallBillsSum, color: Colors.blue),
                bg: Colors.lightBlue[50],
              ),
              _row(label: '10,000원권 (장)', right: _numField(c10000)),
              _row(label: '50,000원권 (장)', right: _numField(c50000)),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text('[밑에돈]', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),

              _row(label: '5,000원 묶음 (개)', right: _numField(b5000)),
              _row(label: '10,000원 묶음 (개)', right: _numField(b10000)),
              _row(label: '25,000원 묶음 (개)', right: _numField(b25000)),
              _row(label: '50,000원 묶음 (개)', right: _numField(b50000)),
              _row(label: '100,000원 묶음 (개)', right: _numField(b100000)),
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

            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _pickExcelFolder,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('데이터폴더설정',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo,
                        side: const BorderSide(color: Colors.indigo, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: folderController,
                      readOnly: true,
                      onTap: _pickExcelFolder,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
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
                    child: TextField(
                      controller: memoController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
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
    );
  }
}

