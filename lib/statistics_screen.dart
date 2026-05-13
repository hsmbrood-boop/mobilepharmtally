import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'holiday_calendar_picker.dart';
import 'pharm_tally_excel.dart';
import 'settlement_store.dart';

/// 매출 통계(상세 매출 통계) 화면.
///
/// - [SettlementStore.savedFolderPath]에 저장된 일별 엑셀 파일들을 읽어
///   기간/일별·월별 단위로 집계 후 표 + 합계/평균을 표시합니다.
/// - 모바일 진입 시 자동으로 가로 모드로 강제, 종료 시 원복.
/// - 엑셀 저장은 하지 않으며, 메인에서 지정한 데이터 폴더의 일별 xlsx 를 읽습니다.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, this.initialDate});

  /// 통계 화면을 처음 열 때 기본으로 보여줄 기준 날짜. 이 날짜가 속한 달의
  /// 1일 ~ 말일 범위가 자동으로 선택된다(예: 2025-04-11 → 2025-04-01 ~
  /// 2025-04-30). null 이면 "이번 달 1일 ~ 오늘" 을 기본으로 사용한다.
  final DateTime? initialDate;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

enum _ViewMode { daily, monthly }

class _Record {
  _Record({required this.date});
  final DateTime date;
  int rx = 0;
  int copay = 0;
  int cardTot = 0;
  int cardCopay = 0;
  int cardOtc = 0;
  int salesOtc = 0;
  int bottle = 0;
  int cashIn = 0;
  int cashTot = 0;
}

class _AggregatedRow {
  _AggregatedRow({required this.label, required this.sortDate});
  final String label;
  final DateTime sortDate;
  int rx = 0;
  int copay = 0;
  int cardTot = 0;
  int cardCopay = 0;
  int cardOtc = 0;
  int salesOtc = 0;
  int bottle = 0;
  int cashIn = 0;
  int cashTot = 0;
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final _store = SettlementStore.instance;
  final _nf = _IntFmt();

  late DateTime _startDate;
  late DateTime _endDate;
  _ViewMode _mode = _ViewMode.daily;

  bool _loading = false;
  String? _error;
  List<_AggregatedRow> _rows = [];

  late final ScrollController _tableHScrollController;
  late final ScrollController _summaryHScrollController;
  bool _syncingHorizontalScroll = false;

  @override
  void initState() {
    super.initState();
    _tableHScrollController = ScrollController();
    _summaryHScrollController = ScrollController();
    _tableHScrollController.addListener(_onTableHorizontalScroll);
    _summaryHScrollController.addListener(_onSummaryHorizontalScroll);

    // 기준 날짜: widget.initialDate 가 있으면 그 달의 1일 ~ 말일을, 없으면
    // 오늘이 속한 달의 1일 ~ 오늘 범위를 기본으로 사용한다. 호출자가 보고
    // 있던 날짜의 한 달치 일별 데이터를 바로 볼 수 있게 한다.
    final base = widget.initialDate ?? DateTime.now();
    _startDate = DateTime(base.year, base.month, 1);
    // 다음 달 1일에서 하루 빼면 해당 월의 말일이 된다.
    _endDate = DateTime(base.year, base.month + 1, 1)
        .subtract(const Duration(days: 1));

    if (!kIsWeb) {
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } catch (_) {}
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } catch (_) {}
    }

    _tableHScrollController.removeListener(_onTableHorizontalScroll);
    _summaryHScrollController.removeListener(_onSummaryHorizontalScroll);
    _tableHScrollController.dispose();
    _summaryHScrollController.dispose();

    super.dispose();
  }

  void _onTableHorizontalScroll() {
    _mirrorHorizontalScroll(_tableHScrollController, _summaryHScrollController);
  }

  void _onSummaryHorizontalScroll() {
    _mirrorHorizontalScroll(_summaryHScrollController, _tableHScrollController);
  }

  void _mirrorHorizontalScroll(ScrollController from, ScrollController to) {
    if (_syncingHorizontalScroll) return;
    if (!from.hasClients || !to.hasClients) return;
    final target = from.offset.clamp(
      to.position.minScrollExtent,
      to.position.maxScrollExtent,
    );
    if ((to.offset - target).abs() < 1.0) return;
    _syncingHorizontalScroll = true;
    to.jumpTo(target);
    _syncingHorizontalScroll = false;
  }

  Future<void> _pickStart() async {
    final picked = await showHolidayDatePicker(
      context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      final start = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _startDate = start;
        // 시작일이 종료일보다 뒤면 종료일을 시작일과 같게 자동 보정.
        if (_endDate.isBefore(start)) {
          _endDate = start;
        }
      });
      _refresh();
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showHolidayDatePicker(
      context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      final end = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _endDate = end;
        // 종료일이 시작일보다 앞이면 시작일을 종료일과 같게 자동 보정.
        if (_startDate.isAfter(end)) {
          _startDate = end;
        }
      });
      _refresh();
    }
  }

  Future<void> _pickFolder() async {
    try {
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked != null && picked.isNotEmpty) {
        _store.update(() => _store.savedFolderPath = picked);
        _refresh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('폴더 선택 중 오류: $e')),
      );
    }
  }

  Future<void> _refresh() async {
    if (kIsWeb) {
      setState(() {
        _rows = [];
        _error = '웹 브라우저에서는 로컬 폴더의 엑셀 파일을 읽을 수 없습니다.\n'
            'Windows 데스크톱(flutter run -d windows) 또는\n'
            '안드로이드 앱으로 실행해 주세요.';
        _loading = false;
      });
      return;
    }
    final folder = _store.savedFolderPath;
    if (folder.isEmpty || !Directory(folder).existsSync()) {
      setState(() {
        _rows = [];
        _error = '데이터 폴더가 지정되지 않았습니다. 통계 화면 상단의 [폴더] 또는 현금정산의 [데이터폴더설정]으로 경로를 지정해 주세요.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _loadRange(folder, _startDate, _endDate);
      final aggregated = _aggregate(raw, _mode);
      aggregated.sort((a, b) => a.sortDate.compareTo(b.sortDate));
      setState(() {
        _rows = aggregated;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '데이터를 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  Future<List<_Record>> _loadRange(
    String folder,
    DateTime start,
    DateTime end,
  ) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return [];
    final entries = await dir.list().toList();
    final files = entries
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.xlsx')
        .toList();

    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final out = <_Record>[];

    for (final file in files) {
      final name = p.basename(file.path);
      final datePart = name.replaceAll('.xlsx', '').split(' ').first;
      DateTime? d;
      try {
        d = DateTime.parse(datePart);
      } catch (_) {
        continue;
      }
      final dd = DateTime(d.year, d.month, d.day);
      if (dd.isBefore(s) || dd.isAfter(e)) continue;

      try {
        var bytes = await file.readAsBytes();
        var stats = parseSalesStatsFromXlsxBytes(bytes);
        if (bytes.length > 2800 &&
            stats.rx == 0 &&
            stats.cardTot == 0 &&
            stats.copay == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          bytes = await file.readAsBytes();
          stats = parseSalesStatsFromXlsxBytes(bytes);
        }
        final rec = _Record(date: dd)
          ..rx = stats.rx
          ..copay = stats.copay
          ..cardTot = stats.cardTot
          ..cardCopay = stats.cardCopay
          ..cardOtc = stats.cardOtc
          ..salesOtc = stats.salesOtc
          ..bottle = stats.bottle
          ..cashIn = stats.cashIn
          ..cashTot = stats.cashTot;
        out.add(rec);
      } catch (_) {
        // 동기화 중 파일 잠금·불완전 쓰기 등으로 첫 읽기만 실패하는 경우 한 번 재시도.
        try {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          final bytes = await file.readAsBytes();
          final stats = parseSalesStatsFromXlsxBytes(bytes);
          final rec = _Record(date: dd)
            ..rx = stats.rx
            ..copay = stats.copay
            ..cardTot = stats.cardTot
            ..cardCopay = stats.cardCopay
            ..cardOtc = stats.cardOtc
            ..salesOtc = stats.salesOtc
            ..bottle = stats.bottle
            ..cashIn = stats.cashIn
            ..cashTot = stats.cashTot;
          out.add(rec);
        } catch (_) {
          continue;
        }
      }
    }
    return out;
  }

  List<_AggregatedRow> _aggregate(List<_Record> raw, _ViewMode mode) {
    const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final map = <String, _AggregatedRow>{};
    for (final r in raw) {
      String key;
      DateTime sortDate;
      if (mode == _ViewMode.daily) {
        final m = r.date.month.toString().padLeft(2, '0');
        final d = r.date.day.toString().padLeft(2, '0');
        key = '${r.date.year}-$m-$d (${dayNames[r.date.weekday - 1]})';
        sortDate = r.date;
      } else {
        final m = r.date.month.toString().padLeft(2, '0');
        key = '${r.date.year}년 $m월';
        sortDate = DateTime(r.date.year, r.date.month, 1);
      }
      final agg = map.putIfAbsent(
        key,
        () => _AggregatedRow(label: key, sortDate: sortDate),
      );
      agg.rx += r.rx;
      agg.copay += r.copay;
      agg.cardTot += r.cardTot;
      agg.cardCopay += r.cardCopay;
      agg.cardOtc += r.cardOtc;
      agg.salesOtc += r.salesOtc;
      agg.bottle += r.bottle;
      agg.cashIn += r.cashIn;
      agg.cashTot += r.cashTot;
    }
    return map.values.toList();
  }

  String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$dd';
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final totals = _AggregatedRow(label: '합계', sortDate: DateTime(0));
    for (final r in _rows) {
      totals.rx += r.rx;
      totals.copay += r.copay;
      totals.cardTot += r.cardTot;
      totals.cardCopay += r.cardCopay;
      totals.cardOtc += r.cardOtc;
      totals.salesOtc += r.salesOtc;
      totals.bottle += r.bottle;
      totals.cashIn += r.cashIn;
      totals.cashTot += r.cashTot;
    }
    final n = _rows.isEmpty ? 1 : _rows.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterBar(),
            const Divider(height: 1),
            Expanded(child: _buildTable()),
            _buildSummary(totals, n),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: const Color(0xFFEEEEEE),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '뒤로',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Text('상세 매출 통계',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 24),
          const Text('기간 조회:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          _DateChip(text: _fmtDate(_startDate), onTap: _pickStart),
          const SizedBox(width: 4),
          const Text('~'),
          const SizedBox(width: 4),
          _DateChip(text: _fmtDate(_endDate), onTap: _pickEnd),
          const SizedBox(width: 16),
          Container(width: 1, height: 24, color: Colors.grey[400]),
          const SizedBox(width: 16),
          ChoiceChip(
            label: const Text('월별 보기'),
            selected: _mode == _ViewMode.monthly,
            onSelected: (v) {
              setState(() => _mode = _ViewMode.monthly);
              _refresh();
            },
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('일별 보기'),
            selected: _mode == _ViewMode.daily,
            onSelected: (v) {
              setState(() => _mode = _ViewMode.daily);
              _refresh();
            },
          ),
          const Spacer(),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              if (!kIsWeb) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('데이터 폴더 선택'),
                  onPressed: _pickFolder,
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                '해당 기간(${_fmtDate(_startDate)} ~ ${_fmtDate(_endDate)})에\n저장된 데이터가 없습니다.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('폴더: ${_store.savedFolderPath}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final headers = [
      'No.',
      '날짜/기간',
      '처방전수',
      '본인부담금',
      '카드매출(총액)',
      '카드(본인부담)',
      '카드(일반약)',
      '매약(일반약)',
      '통약',
      '현금수입',
      '매출총액(카드+현금+보정)',
    ];

    return Scrollbar(
      controller: _tableHScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _tableHScrollController,
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFE3F2FD)),
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            columnSpacing: 18,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columns: [
              for (int i = 0; i < headers.length; i++)
                DataColumn(
                  label: Text(headers[i]),
                  numeric: i >= 2,
                ),
            ],
            rows: [
              for (int i = 0; i < _rows.length; i++)
                DataRow(cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(Text(_rows[i].label)),
                  DataCell(Text(_nf.format(_rows[i].rx))),
                  DataCell(Text(_nf.format(_rows[i].copay))),
                  DataCell(Text(_nf.format(_rows[i].cardTot))),
                  DataCell(Text(_nf.format(_rows[i].cardCopay))),
                  DataCell(Text(_nf.format(_rows[i].cardOtc))),
                  DataCell(Text(_nf.format(_rows[i].salesOtc))),
                  DataCell(Text(_nf.format(_rows[i].bottle))),
                  DataCell(Text(_nf.format(_rows[i].cashIn))),
                  DataCell(Text(_nf.format(_rows[i].cashTot))),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(_AggregatedRow totals, int n) {
    final cells = <_SummaryCell>[
      _SummaryCell('처방전', totals.rx.toDouble(), totals.rx / n),
      _SummaryCell('본인부담', totals.copay.toDouble(), totals.copay / n),
      _SummaryCell('카드매출(총액)', totals.cardTot.toDouble(), totals.cardTot / n),
      _SummaryCell('카드(본인)', totals.cardCopay.toDouble(), totals.cardCopay / n),
      _SummaryCell('카드(일반)', totals.cardOtc.toDouble(), totals.cardOtc / n),
      _SummaryCell('매약(일반)', totals.salesOtc.toDouble(), totals.salesOtc / n),
      _SummaryCell('통약', totals.bottle.toDouble(), totals.bottle / n),
      _SummaryCell('현금수입', totals.cashIn.toDouble(), totals.cashIn / n),
      _SummaryCell('매출총액(카드+현금+보정)', totals.cashTot.toDouble(),
          totals.cashTot / n,
          wide: true),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: SingleChildScrollView(
        controller: _summaryHScrollController,
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 56, child: Center(child: Text('합계',
                    style: TextStyle(fontWeight: FontWeight.bold)))),
                for (final c in cells) _summaryBox(c.label, _nf.format(c.total.round()), c.wide),
              ],
            ),
            Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.grey.shade200),
            Row(
              children: [
                const SizedBox(width: 56, child: Center(child: Text('평균',
                    style: TextStyle(fontWeight: FontWeight.bold)))),
                for (final c in cells)
                  _summaryBox(c.label, c.avg.toStringAsFixed(1).replaceAllMapped(
                    RegExp(r'(\d)(?=(\d{3})+(\.\d+|$))'),
                    (m) => '${m[1]},',
                  ), c.wide),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox(String label, String value, bool wide) {
    return Container(
      width: wide ? 200 : 110,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF666666))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SummaryCell {
  _SummaryCell(this.label, this.total, this.avg, {this.wide = false});
  final String label;
  final double total;
  final double avg;
  final bool wide;
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_month, size: 16),
          ],
        ),
      ),
    );
  }
}

/// 단순 정수 천단위 포맷터(intl 의존성 없이).
class _IntFmt {
  String format(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}
