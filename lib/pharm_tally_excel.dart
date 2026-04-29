import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

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
