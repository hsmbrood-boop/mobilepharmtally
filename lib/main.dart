import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'cash_settlement_screen.dart';
import 'holiday_calendar_picker.dart';
import 'pharm_tally_excel.dart';
import 'settlement_store.dart';
import 'statistics_screen.dart';
import 'widgets/calc_search_icon.dart';

void main() {
  runApp(const PharmTallyApp());
}

class PharmTallyApp extends StatelessWidget {
  const PharmTallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmTally',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR')],
      home: const SalesScreen(),
    );
  }
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
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
  }

  @override
  void dispose() {
    SettlementStore.instance.removeListener(_onStoreChanged);
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

  Widget buildInput(String label, TextEditingController ctrl) {
    return buildRow(
      label,
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => calculate(),
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
      setState(() => selectedDate = picked);
    }
  }

  String get dateStr {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${selectedDate.year}-${selectedDate.month.toString().padLeft(2,'0')}-${selectedDate.day.toString().padLeft(2,'0')} (${days[selectedDate.weekday - 1]})';
  }

  int _toInt(String s) =>
      int.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  void _openStatistics() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatisticsScreen()),
    );
  }

  Future<void> _save() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '웹에서는 로컬 폴더에 저장할 수 없습니다. Windows 데스크톱(또는 안드로이드)에서 실행해 주세요.'),
        ),
      );
      return;
    }
    final store = SettlementStore.instance;

    String? folder = store.savedFolderPath.trim();
    if (folder.isEmpty || !await Directory(folder).exists()) {
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '엑셀 저장 폴더 선택',
      );
      if (!mounted) return;
      if (picked == null || picked.trim().isEmpty) return;
      folder = picked;
      store.update(() => store.savedFolderPath = picked);
    }

    final sales = SalesInput(
      date: selectedDate,
      rxCount: _toInt(rxController.text),
      copay: _toInt(copayController.text),
      cardTotal: _toInt(cardTotalController.text),
      cardCopay: _toInt(cardCopayController.text),
      bottle: _toInt(bottleController.text),
      adjustments: adjRows
          .map((r) => AdjustmentEntry(
                name: r['name']!.text,
                amount: _toInt(r['value']!.text),
              ))
          .toList(),
    );

    try {
      final outPath = await savePharmTallyXlsx(
        store: store,
        sales: sales,
        folder: folder,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 완료: $outPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '저장',
                  icon: const Icon(Icons.save, color: Colors.teal),
                  onPressed: _save,
                ),
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
                  tooltip: '현금정산',
                  icon: const CalcSearchIcon(width: 52, height: 38),
                  iconSize: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CashSettlementScreen(date: selectedDate),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => selectedDate = DateTime.now()),
                  child: const Text('오늘'),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() =>
                      selectedDate = selectedDate.subtract(const Duration(days: 1))),
                ),
                GestureDetector(
                  onTap: pickDate,
                  child: Text(dateStr,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() =>
                      selectedDate = selectedDate.add(const Duration(days: 1))),
                ),
                IconButton(
                  tooltip: '달력',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: pickDate,
                ),
              ],
            ),
            const SizedBox(height: 12),

            buildInput('처방전수', rxController),
            buildInput('본인부담금', copayController),
            buildInput('카드매출(총매출)', cardTotalController),
            buildInput('카드매출(본인부담금)', cardCopayController),
            buildReadOnly('카드매출(일반약)', cardOtc, color: Colors.blue),
            buildReadOnly('매약(일반약)', salesOtc, color: Colors.red),
            buildInput('통약', bottleController),
            buildReadOnly('현금 수입(현입)', cashIncome, color: Colors.green),
            buildReadOnly('매출총액(카드+현금+보정)', grandTotal),

            const Divider(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (adjRows.length > 1) {
                      setState(() => adjRows.removeLast());
                    }
                  },
                  icon: const Icon(Icons.remove, size: 16),
                  label: const Text('항목 삭제'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
                const Text('--- 보정 및 기타 ---',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () {
                    setState(() => adjRows.add({
                      'name': TextEditingController(),
                      'value': TextEditingController(),
                    }));
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('항목 추가'),
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
                      child: TextField(
                        controller: row['name'],
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '항목명',
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: row['value'],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => calculate(),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 80),
          ],
        ),
        ),
      ),
    );
  }
}