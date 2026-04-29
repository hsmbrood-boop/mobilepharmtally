import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CashSettlementScreen extends StatefulWidget {
  const CashSettlementScreen({super.key, required this.date});

  final DateTime date;

  @override
  State<CashSettlementScreen> createState() => _CashSettlementScreenState();
}

class _CashSettlementScreenState extends State<CashSettlementScreen> {
  // 상단
  final authorController = TextEditingController(text: '최병찬');
  bool authorFixed = true;

  final baseCashController = TextEditingController(text: '1000000');
  bool baseCashFixed = false;

  final shortageController = TextEditingController(text: '0');
  bool shortageFixed = false;

  // 권종(장)
  final c1000 = TextEditingController(text: '0');
  bool c1000Fixed = false;
  final c5000 = TextEditingController(text: '0');
  bool c5000Fixed = false;
  final c10000 = TextEditingController(text: '0');
  bool c10000Fixed = false;
  final c50000 = TextEditingController(text: '0');
  bool c50000Fixed = false;

  // 밀어돈(묶음, 개)
  final b5000 = TextEditingController(text: '0');
  bool b5000Fixed = false;
  final b10000 = TextEditingController(text: '0');
  bool b10000Fixed = false;
  final b25000 = TextEditingController(text: '0');
  bool b25000Fixed = false;
  final b50000 = TextEditingController(text: '0');
  bool b50000Fixed = false;
  final b100000 = TextEditingController(text: '0');
  bool b100000Fixed = false;

  final folderController = TextEditingController(text: r'C:\Users\hsmbr\OneDrive\일정산1');
  final memoController = TextEditingController();

  int _i(TextEditingController c) => int.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  String _fmtInt(int v) {
    final s = v.toString();
    final reg = RegExp(r'(\d)(?=(\d{3})+$)');
    return s.replaceAllMapped(reg, (m) => '${m[1]},');
  }

  int get smallBillsSum => 1000 * _i(c1000) + 5000 * _i(c5000);
  int get remainingLarge => 10000 * _i(c10000) + 50000 * _i(c50000); // 남기는금액(1만+5만)
  int get bundlesSum =>
      5000 * _i(b5000) +
      10000 * _i(b10000) +
      25000 * _i(b25000) +
      50000 * _i(b50000) +
      100000 * _i(b100000);

  int get baseCash => _i(baseCashController);
  int get shortage => _i(shortageController);

  // 실제 입금액(임시 계산): (권종합계 + 남기는금액 + 밀어돈총합) - 부족한시제
  int get actualDeposit => (smallBillsSum + remainingLarge + bundlesSum) - shortage;

  String get _dateStr {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} (${days[d.weekday - 1]})';
  }

  @override
  void initState() {
    super.initState();
    final all = <TextEditingController>[
      baseCashController,
      shortageController,
      c1000,
      c5000,
      c10000,
      c50000,
      b5000,
      b10000,
      b25000,
      b50000,
      b100000,
    ];
    for (final c in all) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    authorController.dispose();
    baseCashController.dispose();
    shortageController.dispose();
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
    shortageController.text = '0';
    for (final c in [c1000, c5000, c10000, c50000, b5000, b10000, b25000, b50000, b100000]) {
      c.text = '0';
    }
    memoController.clear();
  }

  Future<void> _pickExcelFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '엑셀 불러올 폴더 선택');
    if (!mounted) return;
    if (dir == null || dir.trim().isEmpty) return;

    setState(() => folderController.text = dir);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('엑셀 폴더 지정: $dir')),
    );
  }

  Future<void> _saveExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['현금정산'];

      int r = 0;
      void addRow(String k, dynamic v) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(k);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue('$v');
        r++;
      }

      addRow('날짜', _dateStr);
      addRow('작성자', authorController.text);
      addRow('시제(기본준비금)', baseCashController.text);
      addRow('부족한 시제', shortageController.text);
      addRow('1,000원권(장)', c1000.text);
      addRow('5,000원권(장)', c5000.text);
      addRow('합산(1천+5천)', _fmtInt(smallBillsSum));
      addRow('10,000원권(장)', c10000.text);
      addRow('50,000원권(장)', c50000.text);
      addRow('남기는금액(1만+5만)', _fmtInt(remainingLarge));
      addRow('5,000원 묶음(개)', b5000.text);
      addRow('10,000원 묶음(개)', b10000.text);
      addRow('25,000원 묶음(개)', b25000.text);
      addRow('50,000원 묶음(개)', b50000.text);
      addRow('100,000원 묶음(개)', b100000.text);
      addRow('밀어돈 총합계', _fmtInt(bundlesSum));
      addRow('실제 입금액', _fmtInt(actualDeposit));
      addRow('메모', memoController.text);

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('엑셀 인코딩 실패');
      }

      // 저장 위치: 사용자가 지정한 폴더가 있으면 우선 사용(가능할 때만),
      // 아니면 앱 Documents 폴더로 저장
      Directory baseDir;
      final userDir = folderController.text.trim();
      if (userDir.isNotEmpty && await Directory(userDir).exists()) {
        baseDir = Directory(userDir);
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final fileName =
          '현금정산_${widget.date.year}${widget.date.month.toString().padLeft(2, '0')}${widget.date.day.toString().padLeft(2, '0')}.xlsx';
      final outPath = p.join(baseDir.path, fileName);
      final outFile = File(outPath);
      await outFile.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('엑셀 저장 완료: $outPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('엑셀 저장 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '엑셀 저장',
          icon: const Icon(Icons.save, color: Colors.white),
          onPressed: _saveExcel,
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
              right: Row(
                children: [
                  _fixedToggle(shortageFixed, (nv) => setState(() => shortageFixed = nv)),
                  Expanded(child: _numField(shortageController, fixed: shortageFixed, textColor: Colors.red)),
                ],
              ),
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
              right: _roNumber(remainingLarge, color: Colors.green),
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

