import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'settlement_store.dart';

/// 매출/정산 상세 화면이 메인 화면에서 들고 있는 입력값들을
/// 한 묶음으로 전달하기 위한 단순 DTO.
class SalesInput {
  SalesInput({
    required this.date,
    required this.rxCount,
    required this.copay,
    required this.cardTotal,
    required this.cardCopay,
    required this.bottle,
    required this.adjustments,
  });

  final DateTime date;
  final int rxCount;
  final int copay;
  final int cardTotal;
  final int cardCopay;
  final int bottle;
  final List<AdjustmentEntry> adjustments;

  int get cardOtc => cardTotal - cardCopay;

  int get adjustmentsSum =>
      adjustments.fold<int>(0, (sum, a) => sum + a.amount);
}

class AdjustmentEntry {
  AdjustmentEntry({required this.name, required this.amount});
  final String name;
  final int amount;
}

const _fontFamily = '맑은 고딕';
const _fontSize = 11;

/// 'YYYY-MM-DD (요일).xlsx' 파일명 생성.
String pharmTallyFileName(DateTime d) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  final y = d.year.toString();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day (${days[d.weekday - 1]}).xlsx';
}

/// 파일명 앞부분만으로 매칭할 때 사용 (`YYYY-MM-DD`).
String pharmTallyFileNamePrefix(DateTime d) {
  final y = d.year.toString();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// 폴더 안의 xlsx 파일명에서 날짜를 파싱해, [before] 이전 날짜 중 가장 최근을 반환.
/// [before]를 생략하면 전체 중 가장 최근 날짜를 반환.
/// 임시 잠금 파일(~$...)은 제외. 해당하는 파일이 없으면 null.
Future<DateTime?> findMostRecentXlsxDate(String folder, {DateTime? before}) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return null;

  final dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
  DateTime? latest;

  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.toLowerCase().endsWith('.xlsx')) continue;
    if (name.startsWith('~')) continue;

    final m = dateRe.firstMatch(name);
    if (m == null) continue;

    final date = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    if (before != null && !date.isBefore(before)) continue;
    if (latest == null || date.isAfter(latest)) latest = date;
  }

  return latest;
}

/// 정확한 `YYYY-MM-DD (요일).xlsx` 가 없으면 같은 날짜 접두어를 가진 xlsx 를 찾는다.
/// (PC·동기화 도구에 따라 괄호·공백·유니코드가 조금 달라도 불러오기 가능하게 함.)
Future<String?> resolvePharmTallyXlsxPath({
  required String folder,
  required DateTime date,
}) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return null;

  final exactName = pharmTallyFileName(date);
  final exactPath = p.join(folder, exactName);
  if (await File(exactPath).exists()) return exactPath;

  final prefix = pharmTallyFileNamePrefix(date);
  final candidates = <String>[];

  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.toLowerCase().endsWith('.xlsx')) continue;
    if (!name.startsWith(prefix)) continue;
    final tail = name.substring(prefix.length);
    final lowerTail = tail.toLowerCase();
    // `2026-05-13.xlsx` 또는 `2026-05-13 (수).xlsx` 등
    if (lowerTail == '.xlsx' ||
        tail.startsWith(' ') ||
        tail.startsWith('(') ||
        tail.startsWith('_') ||
        tail.startsWith('-')) {
      candidates.add(entity.path);
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort();
  return candidates.first;
}

String _dateLabel(DateTime d) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day (${days[d.weekday - 1]})';
}

Border _thinBorder() => Border(borderStyle: BorderStyle.Thin);

CellStyle _baseStyle({
  String? format,
  bool bold = false,
  bool wrap = false,
  VerticalAlign verticalAlign = VerticalAlign.Center,
}) {
  return CellStyle(
    fontFamily: _fontFamily,
    fontSize: _fontSize,
    bold: bold,
    textWrapping: wrap ? TextWrapping.WrapText : null,
    verticalAlign: verticalAlign,
    numberFormat: format == null
        ? NumFormat.defaultNumeric
        : CustomNumericNumFormat(formatCode: format),
    leftBorder: _thinBorder(),
    rightBorder: _thinBorder(),
    topBorder: _thinBorder(),
    bottomBorder: _thinBorder(),
  );
}

void _setText(Sheet sheet, String coord, String? value, {bool bold = false}) {
  final cell = sheet.cell(CellIndex.indexByString(coord));
  cell.value = value == null ? null : TextCellValue(value);
  cell.cellStyle = _baseStyle(bold: bold);
}

void _setInt(Sheet sheet, String coord, int? value) {
  final cell = sheet.cell(CellIndex.indexByString(coord));
  cell.value = value == null ? null : IntCellValue(value);
  cell.cellStyle = _baseStyle(format: '#,##0');
}

void _applyBlankBorders(Sheet sheet, int rowFrom, int rowTo) {
  for (int r = rowFrom; r <= rowTo; r++) {
    for (int c = 0; c < 4; c++) {
      final cell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r - 1));
      cell.cellStyle ??= _baseStyle();
    }
  }
}

/// 원본 팜텔리 양식 그대로 한 파일을 만들어 [folder] 에 저장.
/// 같은 날짜 파일이 있으면 덮어쓴다. 저장된 파일의 절대 경로를 반환.
Future<String> savePharmTallyXlsx({
  required SettlementStore store,
  required SalesInput sales,
  required String folder,
}) async {
  final dir = Directory(folder);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final excel = Excel.createExcel();
  const sheetName = '정산내역';
  if (excel.sheets.keys.first != sheetName) {
    excel.rename(excel.sheets.keys.first, sheetName);
  }
  final sheet = excel[sheetName];

  // 컬럼 너비
  sheet.setColumnWidth(0, 25.0);
  sheet.setColumnWidth(1, 18.0);
  sheet.setColumnWidth(2, 30.0);
  sheet.setColumnWidth(3, 18.0);

  // ── 헤더 ────────────────────────────────────────────────
  _setText(sheet, 'A1', '작성자');
  _setText(sheet, 'B1', store.author);
  _setText(sheet, 'B2', '[현금정산]');
  _setText(sheet, 'C2', _dateLabel(sales.date));
  _setText(sheet, 'D2', '[매출/정산 상세]');

  // ── 좌측(현금정산) ─────────────────────────────────────
  _setText(sheet, 'A3', '시제 (기본준비금)');
  _setInt(sheet, 'B3', store.baseCash);

  _setText(sheet, 'A4', '부족한 시제');
  _setInt(sheet, 'B4', store.missing);

  _setText(sheet, 'A6', '1,000원권 (장)');
  _setInt(sheet, 'B6', store.c1000);
  _setText(sheet, 'A7', '5,000원권 (장)');
  _setInt(sheet, 'B7', store.c5000);
  _setText(sheet, 'A8', '합산(1천원권+5천원권)');
  _setInt(sheet, 'B8', store.smallBillsSum);

  _setText(sheet, 'A9', '10,000원권 (장)');
  _setInt(sheet, 'B9', store.c10000);
  _setText(sheet, 'A10', '50,000원권 (장)');
  _setInt(sheet, 'B10', store.c50000);

  _setText(sheet, 'A12', '[밑에돈]');

  _setText(sheet, 'A13', '5,000원 묶음 (개)');
  _setInt(sheet, 'B13', store.b5000);
  _setText(sheet, 'A14', '10,000원 묶음 (개)');
  _setInt(sheet, 'B14', store.b10000);
  _setText(sheet, 'A15', '25,000원 묶음 (개)');
  _setInt(sheet, 'B15', store.b25000);
  _setText(sheet, 'A16', '50,000원 묶음 (개)');
  _setInt(sheet, 'B16', store.b50000);
  _setText(sheet, 'A17', '100,000원 묶음 (개)');
  _setInt(sheet, 'B17', store.b100000);

  _setText(sheet, 'A18', '밑에돈 총합계');
  _setInt(sheet, 'B18', store.bundlesSum);

  _setText(sheet, 'A20', '남기는금액(1만+5만)');
  _setInt(sheet, 'B20', store.autoKeep);

  _setText(sheet, 'A21', '실제 입금액');
  _setInt(sheet, 'B21', store.actualDeposit);

  // ── 우측(매출/정산 상세) ────────────────────────────────
  final cardOtc = sales.cardOtc;
  final cashIncome = store.actualDeposit;
  final grandTotal = sales.cardTotal + cashIncome + sales.adjustmentsSum;
  final salesOtc = grandTotal - sales.copay;

  _setText(sheet, 'C3', '처방전수');
  _setInt(sheet, 'D3', sales.rxCount);
  _setText(sheet, 'C4', '본인부담금');
  _setInt(sheet, 'D4', sales.copay);
  _setText(sheet, 'C5', '카드매출(총매출)');
  _setInt(sheet, 'D5', sales.cardTotal);
  _setText(sheet, 'C6', '카드매출(본인부담금)');
  _setInt(sheet, 'D6', sales.cardCopay);
  _setText(sheet, 'C7', '카드매출(일반약)');
  _setInt(sheet, 'D7', cardOtc);
  _setText(sheet, 'C8', '매약(일반약)');
  _setInt(sheet, 'D8', salesOtc);
  _setText(sheet, 'C9', '통약');
  _setInt(sheet, 'D9', sales.bottle);
  _setText(sheet, 'C10', '현금 수입(현입)');
  _setInt(sheet, 'D10', cashIncome);
  _setText(sheet, 'C11', '매출총액(카드+현금+보정)');
  _setInt(sheet, 'D11', grandTotal);

  _setText(sheet, 'C13', '--- 보정 및 기타 ---');

  // 보정 항목: 14행부터. 항목명/값 둘 다 비어있는 행은 제외.
  final filledAdjustments = sales.adjustments
      .where((a) => a.name.trim().isNotEmpty || a.amount != 0)
      .toList();

  int row = 14;
  for (final adj in filledAdjustments) {
    final name = adj.name.trim().isEmpty ? null : adj.name.trim();
    _setText(sheet, 'C$row', name);
    _setInt(sheet, 'D$row', adj.amount);
    row++;
  }

  // ── 메모 영역 ────────────────────────────────────────────
  // 원본 팜텔리: m_r = max(len(left_data), len(right_data)) + 4.
  // left_data 길이는 항상 19 (시제~실제입금액). right_data 길이는
  // 11(고정) + 보정항목 수.
  const leftLen = 19;
  final rightLen = 11 + filledAdjustments.length;
  final maxLen = leftLen > rightLen ? leftLen : rightLen;
  final memoLabelRow = maxLen + 4;

  _setText(sheet, 'A$memoLabelRow', '특이사항 및 메모', bold: true);
  sheet.merge(
    CellIndex.indexByString('A$memoLabelRow'),
    CellIndex.indexByString('D$memoLabelRow'),
  );

  final memoStart = memoLabelRow + 1;
  final memoEnd = memoLabelRow + 6;
  final memoCell =
      sheet.cell(CellIndex.indexByString('A$memoStart'));
  memoCell.value =
      store.memo.isEmpty ? null : TextCellValue(store.memo);
  memoCell.cellStyle = _baseStyle(wrap: true, verticalAlign: VerticalAlign.Top);
  sheet.merge(
    CellIndex.indexByString('A$memoStart'),
    CellIndex.indexByString('D$memoEnd'),
  );

  // 비어있는 셀에도 테두리를 그려 원본과 동일한 격자 모양 유지.
  _applyBlankBorders(sheet, 1, memoEnd);

  // ── 파일 저장 ──────────────────────────────────────────
  final bytes = excel.encode();
  if (bytes == null) {
    throw Exception('엑셀 인코딩에 실패했습니다');
  }

  final outPath = p.join(folder, pharmTallyFileName(sales.date));
  final file = File(outPath);
  if (await file.exists()) {
    await file.delete();
  }
  await file.writeAsBytes(bytes, flush: true);
  return outPath;
}

// ── 불러오기 (저장된 xlsx → 폼/스토어 값) ────────────────────────────────

/// `savePharmTallyXlsx`로 저장한 파일을 다시 읽어와서 폼에 채워넣을 때
/// 쓰이는 결과 묶음. 파생값(부족한 시제, 남기는금액 등)은 별도로
/// 들고 있지 않고, 입력 원본값만 복원한다.
class LoadedSettlement {
  const LoadedSettlement({
    required this.author,
    required this.rxCount,
    required this.copay,
    required this.cardTotal,
    required this.cardCopay,
    required this.bottle,
    required this.adjustments,
    required this.baseCash,
    required this.c1000,
    required this.c5000,
    required this.c10000,
    required this.c50000,
    required this.b5000,
    required this.b10000,
    required this.b25000,
    required this.b50000,
    required this.b100000,
    required this.memo,
  });

  final String author;
  final int rxCount;
  final int copay;
  final int cardTotal;
  final int cardCopay;
  final int bottle;
  final List<AdjustmentEntry> adjustments;
  final int baseCash;
  final int c1000;
  final int c5000;
  final int c10000;
  final int c50000;
  final int b5000;
  final int b10000;
  final int b25000;
  final int b50000;
  final int b100000;
  final String memo;
}

/// [folder] 안에서 [date]에 해당하는 `YYYY-MM-DD (요일).xlsx` 파일을 읽어
/// 메인/현금정산 화면에 다시 채워넣을 값들을 돌려준다.
///
/// - 폴더가 비어 있거나, 파일이 없으면 `null` 을 돌려준다(정상 케이스).
/// - 파일은 있는데 디코딩/파싱 단계에서 실패하면 [LoadXlsxException] 을 던진다.
///
/// `package:excel` 은 openpyxl 이 만든 `t="inlineStr"` 셀을 제대로 못 읽기
/// 때문에 여기서는 xlsx(=zip+xml) 의 sheet1.xml 을 직접 파싱한다. 따라서
/// PC팜텔리(파이썬/openpyxl) 가 만든 파일과 Flutter 가 만든 파일 모두 동일
/// 하게 처리할 수 있다.
bool _suspiciousLoadedEmpty(LoadedSettlement data, int fileLen) {
  if (fileLen < 2500) return false;
  return data.rxCount == 0 &&
      data.cardTotal == 0 &&
      data.copay == 0 &&
      data.author.trim().isEmpty;
}

LoadedSettlement _loadedSettlementFromSheet(_XlsxSheet sheet) {
  String author = '';
  int rxCount = 0, copay = 0, cardTotal = 0, cardCopay = 0, bottle = 0;
  int baseCash = 1000000;
  int c1000 = 0, c5000 = 0, c10000 = 0, c50000 = 0;
  int b5000 = 0, b10000 = 0, b25000 = 0, b50000 = 0, b100000 = 0;
  final adjustments = <AdjustmentEntry>[];
  String memo = '';

  int? memoLabelRow;
  bool inAdjustments = false;

  final lastRow = sheet.lastRow;
  author = sheet.text('B1');

  for (int r = 1; r <= lastRow; r++) {
    final aLabel = sheet.text('A$r').trim();
    switch (aLabel) {
      case '시제 (기본준비금)':
        baseCash = sheet.intAt('B$r', 1000000);
        break;
      case '1,000원권 (장)':
        c1000 = sheet.intAt('B$r');
        break;
      case '5,000원권 (장)':
        c5000 = sheet.intAt('B$r');
        break;
      case '10,000원권 (장)':
        c10000 = sheet.intAt('B$r');
        break;
      case '50,000원권 (장)':
        c50000 = sheet.intAt('B$r');
        break;
      case '5,000원 묶음 (개)':
        b5000 = sheet.intAt('B$r');
        break;
      case '10,000원 묶음 (개)':
        b10000 = sheet.intAt('B$r');
        break;
      case '25,000원 묶음 (개)':
        b25000 = sheet.intAt('B$r');
        break;
      case '50,000원 묶음 (개)':
        b50000 = sheet.intAt('B$r');
        break;
      case '100,000원 묶음 (개)':
        b100000 = sheet.intAt('B$r');
        break;
      case '특이사항 및 메모':
        memoLabelRow = r;
        break;
    }

    final cLabel = sheet.text('C$r').trim();
    if (!inAdjustments) {
      switch (cLabel) {
        case '처방전수':
          rxCount = sheet.intAt('D$r');
          break;
        case '본인부담금':
          copay = sheet.intAt('D$r');
          break;
        case '카드매출(총매출)':
          cardTotal = sheet.intAt('D$r');
          break;
        case '카드매출(본인부담금)':
          cardCopay = sheet.intAt('D$r');
          break;
        case '통약':
          bottle = sheet.intAt('D$r');
          break;
        case '--- 보정 및 기타 ---':
          inAdjustments = true;
          break;
      }
    } else {
      if (aLabel == '특이사항 및 메모') {
        inAdjustments = false;
        continue;
      }
      final amount = sheet.intAt('D$r');
      if (cLabel.isNotEmpty || amount != 0) {
        adjustments.add(AdjustmentEntry(name: cLabel, amount: amount));
      }
    }
  }

  if (memoLabelRow != null) {
    memo = sheet.text('A${memoLabelRow + 1}');
  }

  return LoadedSettlement(
    author: author,
    rxCount: rxCount,
    copay: copay,
    cardTotal: cardTotal,
    cardCopay: cardCopay,
    bottle: bottle,
    adjustments: adjustments,
    baseCash: baseCash,
    c1000: c1000,
    c5000: c5000,
    c10000: c10000,
    c50000: c50000,
    b5000: b5000,
    b10000: b10000,
    b25000: b25000,
    b50000: b50000,
    b100000: b100000,
    memo: memo,
  );
}

Future<LoadedSettlement?> loadPharmTallyXlsx({
  required String folder,
  required DateTime date,
}) async {
  if (folder.trim().isEmpty) return null;

  final path = await resolvePharmTallyXlsxPath(folder: folder, date: date);
  if (path == null) return null;

  final file = File(path);

  Future<Uint8List> readAll() async {
    try {
      return await file.readAsBytes();
    } catch (e) {
      throw LoadXlsxException('파일 읽기 실패: $e', path: path);
    }
  }

  final bytes = await readAll();
  if (bytes.isEmpty) {
    throw LoadXlsxException('파일이 비어 있습니다 (0 byte)', path: path);
  }

  int fileLen = 0;
  try {
    fileLen = await file.length();
  } catch (_) {}

  final _XlsxSheet sheet;
  try {
    sheet = _parseXlsxFirstSheet(bytes);
  } catch (e, st) {
    throw LoadXlsxException(
      '엑셀 파싱 실패: $e\n$st',
      path: path,
    );
  }

  var loaded = _loadedSettlementFromSheet(sheet);

  // 동기화·저장 직후 불완전 읽기로 셀이 비어 파싱되는 경우 재시도.
  if (_suspiciousLoadedEmpty(loaded, fileLen)) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    try {
      final bytes2 = await readAll();
      if (bytes2.isNotEmpty) {
        final sheet2 = _parseXlsxFirstSheet(bytes2);
        final loaded2 = _loadedSettlementFromSheet(sheet2);
        if (!_suspiciousLoadedEmpty(loaded2, fileLen)) {
          loaded = loaded2;
        }
      }
    } catch (_) {}
  }

  return loaded;
}

/// 통계 화면용 — 시트 우측(C/D) 매출·현금 필드만 추출.
class PharmTallySalesStats {
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

PharmTallySalesStats parseSalesStatsFromXlsxBytes(Uint8List bytes) {
  final sheet = _parseXlsxFirstSheet(bytes);
  final rec = PharmTallySalesStats();
  for (int r = 1; r <= sheet.lastRow; r++) {
    final lbl = sheet.text('C$r').trim();
    if (lbl.isEmpty) continue;
    final val = sheet.intAt('D$r');
    switch (lbl) {
      case '처방전수':
        rec.rx = val;
        break;
      case '본인부담금':
        rec.copay = val;
        break;
      case '카드매출(총매출)':
        rec.cardTot = val;
        break;
      case '카드매출(본인부담금)':
        rec.cardCopay = val;
        break;
      case '카드매출(일반약)':
        rec.cardOtc = val;
        break;
      case '매약(일반약)':
        rec.salesOtc = val;
        break;
      case '통약':
        rec.bottle = val;
        break;
      case '현금 수입(현입)':
        rec.cashIn = val;
        break;
      case '현금 합계':
      case '매출총액(현금+카드+보정)':
      case '매출총액(합계)':
      case '매출총액(카드+현금+보정)':
        rec.cashTot = val;
        break;
    }
  }
  return rec;
}

// ── 미니 xlsx 파서 ───────────────────────────────────────────────────────
//
// `package:excel` 4.x 는 openpyxl 이 만든 `t="inlineStr"` 셀을 제대로
// 디코딩하지 못한다 (값이 빈 문자열로 잡힘). pharm_tally 가 다루는 시트는
// 구조가 단순하므로 zip 안의 sheet1.xml 을 직접 읽어 좌표 → 값 맵으로
// 만들어 쓰는 편이 안정적이다.

class _XlsxSheet {
  _XlsxSheet({
    required this.textByCoord,
    required this.numberByCoord,
    required this.lastRow,
  });

  final Map<String, String> textByCoord;
  final Map<String, double> numberByCoord;
  final int lastRow;

  String text(String coord) => textByCoord[coord] ?? '';

  int intAt(String coord, [int fallback = 0]) {
    final n = numberByCoord[coord];
    if (n != null) return n.round();
    final t = textByCoord[coord];
    if (t == null || t.isEmpty) return fallback;
    final cleaned = t.replaceAll(',', '').trim();
    return int.tryParse(cleaned) ??
        double.tryParse(cleaned)?.round() ??
        fallback;
  }
}

int _rowFromRef(String ref) {
  var i = 0;
  while (i < ref.length && _isLetter(ref.codeUnitAt(i))) {
    i++;
  }
  return int.tryParse(ref.substring(i)) ?? 0;
}

bool _isLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

final _excelCellRefRe = RegExp(r'^[A-Za-z]+\d+$');

String? _excelRefFromCellAttrs(String attrs) {
  final m = RegExp(r'\br="([^"]+)"').firstMatch(attrs);
  final ref = m?.group(1);
  if (ref == null || !_excelCellRefRe.hasMatch(ref)) return null;
  return ref;
}

/// 일부 환경에서 Xml 트리 순회가 셀을 못 잡을 때, 시트 원문 문자열로 보강한다.
int _mergeRawXmlIntoMaps(
  String raw,
  List<String> sharedStrings,
  Map<String, String> textMap,
  Map<String, double> numMap,
  int maxRow,
) {
  var localMax = maxRow;

  void bumpRow(String ref) {
    final rn = _rowFromRef(ref);
    if (rn > localMax) localMax = rn;
  }

  final inlineRe = RegExp(
    r'<c([^>]*)>\s*<is>(.*?)</is>\s*</c>',
    dotAll: true,
  );
  for (final m in inlineRe.allMatches(raw)) {
    final attrs = m.group(1)!;
    if (!attrs.contains('t="inlineStr"')) continue;
    final ref = _excelRefFromCellAttrs(attrs);
    if (ref == null) continue;
    final inner = m.group(2)!;
    final buf = StringBuffer();
    for (final tm
        in RegExp(r'<t[^>]*>([^<]*)</t>', dotAll: true).allMatches(inner)) {
      buf.write(tm.group(1)!);
    }
    final txt = buf.toString();
    if (txt.isNotEmpty) {
      textMap[ref] = txt;
      bumpRow(ref);
    }
  }

  final cellWithV = RegExp(
    r'<c([^>]*)>\s*<v>([^<]*)</v>\s*</c>',
    dotAll: true,
  );
  for (final m in cellWithV.allMatches(raw)) {
    final attrs = m.group(1)!;
    final ref = _excelRefFromCellAttrs(attrs);
    if (ref == null) continue;
    final valStr = m.group(2)!.trim();

    if (attrs.contains('t="inlineStr"')) continue;

    if (attrs.contains('t="s"')) {
      final idx = int.tryParse(valStr);
      if (idx != null && idx >= 0 && idx < sharedStrings.length) {
        final s = sharedStrings[idx];
        if (s.isNotEmpty) {
          textMap[ref] = s;
          bumpRow(ref);
        }
      }
      continue;
    }

    if (attrs.contains('t="str"')) {
      if (valStr.isNotEmpty) {
        textMap[ref] = valStr;
        bumpRow(ref);
      }
      continue;
    }

    final n = double.tryParse(valStr);
    if (n != null) {
      numMap[ref] = n;
      bumpRow(ref);
    }
  }

  return localMax;
}

ArchiveFile? _archiveFindFileInsensitive(Archive archive, String path) {
  final want = path.replaceAll(r'\', '/').toLowerCase();
  for (final f in archive.files) {
    if (f.name.replaceAll(r'\', '/').toLowerCase() == want) return f;
  }
  return null;
}

/// workbook.xml + workbook.xml.rels 로 첫 번째 시트의 zip 내 경로를 구한다.
String? _firstWorksheetZipPath(Archive archive) {
  final wb = _archiveFindFileInsensitive(archive, 'xl/workbook.xml');
  if (wb == null) return null;
  xml.XmlDocument wbDoc;
  try {
    wbDoc = xml.XmlDocument.parse(utf8.decode(wb.content as List<int>));
  } catch (_) {
    return null;
  }
  xml.XmlElement? firstSheet;
  for (final el in wbDoc.descendants.whereType<xml.XmlElement>()) {
    if (el.name.local == 'sheet') {
      firstSheet = el;
      break;
    }
  }
  if (firstSheet == null) return null;
  String? rid;
  for (final a in firstSheet.attributes) {
    if (a.localName == 'id') rid = a.value;
  }
  if (rid == null) return null;

  final rels =
      _archiveFindFileInsensitive(archive, 'xl/_rels/workbook.xml.rels');
  if (rels == null) return null;
  xml.XmlDocument relsDoc;
  try {
    relsDoc = xml.XmlDocument.parse(utf8.decode(rels.content as List<int>));
  } catch (_) {
    return null;
  }
  for (final rel in relsDoc.descendants.whereType<xml.XmlElement>()) {
    if (rel.name.local != 'Relationship') continue;
    String? idVal;
    String? target;
    for (final a in rel.attributes) {
      final ln = a.localName;
      if (ln == 'Id' || ln == 'id') idVal = a.value;
      if (ln == 'Target' || ln == 'target') target = a.value;
    }
    if (idVal == rid && target != null) {
      var t = target.replaceAll(r'\', '/');
      if (t.startsWith('/xl/')) return t.substring(1);
      if (t.startsWith('xl/')) return t;
      return 'xl/$t';
    }
  }
  return null;
}

xml.XmlElement? _xmlChildLocal(xml.XmlElement parent, String local) {
  for (final ch in parent.childElements) {
    if (ch.name.local == local) return ch;
  }
  return null;
}

String? _xmlAttrLocal(xml.XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.localName == local) return a.value;
  }
  return null;
}

_XlsxSheet _parseXlsxFirstSheet(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final sharedStrings = <String>[];
  final sharedFile =
      _archiveFindFileInsensitive(archive, 'xl/sharedStrings.xml');
  if (sharedFile != null) {
    final content = utf8.decode(sharedFile.content as List<int>);
    final doc = xml.XmlDocument.parse(content);
    for (final si in doc.descendants.whereType<xml.XmlElement>()) {
      if (si.name.local != 'si') continue;
      final buf = StringBuffer();
      for (final t in si.descendants.whereType<xml.XmlElement>()) {
        if (t.name.local == 't') buf.write(t.innerText);
      }
      sharedStrings.add(buf.toString());
    }
  }

  ArchiveFile? sheetFile;
  final resolved = _firstWorksheetZipPath(archive);
  if (resolved != null) {
    sheetFile = _archiveFindFileInsensitive(archive, resolved);
  }
  sheetFile ??=
      _archiveFindFileInsensitive(archive, 'xl/worksheets/sheet1.xml');

  if (sheetFile == null) {
    final paths = archive.files
        .map((f) => f.name)
        .where(
          (n) =>
              n.replaceAll(r'\', '/').toLowerCase().startsWith(
                    'xl/worksheets/',
                  ) &&
              n.toLowerCase().endsWith('.xml'),
        )
        .toList()
      ..sort();
    if (paths.isNotEmpty) {
      sheetFile = _archiveFindFileInsensitive(archive, paths.first);
    }
  }

  if (sheetFile == null) {
    throw StateError('워크시트 XML 을 찾을 수 없음');
  }

  final rawStr = utf8.decode(sheetFile.content as List<int>);
  final sheetXml = xml.XmlDocument.parse(rawStr);

  final textMap = <String, String>{};
  final numMap = <String, double>{};
  int maxRow = 0;

  for (final c in sheetXml.descendants.whereType<xml.XmlElement>()) {
    if (c.name.local != 'c') continue;
    final ref = _xmlAttrLocal(c, 'r');
    if (ref == null) continue;
    final rowNum = _rowFromRef(ref);
    if (rowNum > maxRow) maxRow = rowNum;
    final type = _xmlAttrLocal(c, 't') ?? 'n';

    if (type == 'inlineStr') {
      final is_ = _xmlChildLocal(c, 'is');
      if (is_ == null) continue;
      final buf = StringBuffer();
      for (final t in is_.descendants.whereType<xml.XmlElement>()) {
        if (t.name.local == 't') buf.write(t.innerText);
      }
      final s = buf.toString();
      if (s.isNotEmpty) textMap[ref] = s;
    } else if (type == 's') {
      final v = _xmlChildLocal(c, 'v');
      if (v == null) continue;
      final idx = int.tryParse(v.innerText.trim());
      if (idx == null || idx < 0 || idx >= sharedStrings.length) continue;
      final s = sharedStrings[idx];
      if (s.isNotEmpty) textMap[ref] = s;
    } else if (type == 'str') {
      final v = _xmlChildLocal(c, 'v');
      if (v == null) continue;
      final s = v.innerText;
      if (s.isNotEmpty) textMap[ref] = s;
    } else {
      final v = _xmlChildLocal(c, 'v');
      if (v == null) continue;
      final rawCell = v.innerText.trim();
      if (rawCell.isEmpty) continue;
      final n = double.tryParse(rawCell);
      if (n != null) numMap[ref] = n;
    }
  }

  // 트리 파서가 셀을 거의 못 잡은 경우(일부 삼성·동기화 환경) 원문 XML 로 보강.
  final parsedCount = textMap.length + numMap.length;
  if (parsedCount < 30 && rawStr.length > 400) {
    maxRow = _mergeRawXmlIntoMaps(
      rawStr,
      sharedStrings,
      textMap,
      numMap,
      maxRow,
    );
  }

  return _XlsxSheet(
    textByCoord: textMap,
    numberByCoord: numMap,
    lastRow: maxRow,
  );
}

class LoadXlsxException implements Exception {
  LoadXlsxException(this.message, {this.path});
  final String message;
  final String? path;

  @override
  String toString() =>
      path == null ? message : '$message\n(path: $path)';
}

