import 'package:flutter/foundation.dart';

/// 메인(매출/정산 상세) 화면과 현금정산 화면이 공유하는 데이터.
///
/// 모든 파생값(부족한 시제, 남기는금액, 실제 입금액 등)은 원본 팜텔리 PC
/// 프로그램의 `update_calculations` 와 동일한 자동 계산 공식을 따른다.
class SettlementStore extends ChangeNotifier {
  SettlementStore._();
  static final SettlementStore instance = SettlementStore._();

  // 사용자 입력값 ──────────────────────────────────────────
  String author = '최병찬';
  String savedFolderPath = r'C:\Users\hsmbr\OneDrive\일정산1';

  int baseCash = 1000000; // 시제 (기본준비금)

  int c1000 = 0;
  int c5000 = 0;
  int c10000 = 0;
  int c50000 = 0;

  int b5000 = 0;
  int b10000 = 0;
  int b25000 = 0;
  int b50000 = 0;
  int b100000 = 0;

  String memo = '';

  // 자동 계산 ────────────────────────────────────────────
  /// 1천+5천원권 합산.
  int get smallBillsSum => 1000 * c1000 + 5000 * c5000;

  /// 통에 들어 있는 1만+5만권 전체 합 (영업 마감 시 카운트값).
  int get bigBillsTotal => 10000 * c10000 + 50000 * c50000;

  /// 밑에돈(묶음) 총합계.
  int get bundlesSum =>
      5000 * b5000 +
      10000 * b10000 +
      25000 * b25000 +
      50000 * b50000 +
      100000 * b100000;

  /// 부족한 시제 = 시제 - (1천+5천 합 + 묶음 총합). 음수가 나오면 시제 초과.
  int get missing => baseCash - (smallBillsSum + bundlesSum);

  /// 남기는금액(1만+5만) = missing 을 만원 단위로 ceil(양수일 때) /
  /// floor(음수일 때) 처리. 0이면 0.
  int get autoKeep {
    final m = missing;
    if (m > 0) {
      // ceil
      return ((m + 9999) ~/ 10000) * 10000;
    } else if (m == 0) {
      return 0;
    } else {
      // floor (음수)
      return (m / 10000).floor() * 10000;
    }
  }

  /// 실제 입금액 = 1만/5만권 합 - 남기는금액. 매출/정산 상세의
  /// "현금 수입(현입)"과 동일한 값.
  int get actualDeposit => bigBillsTotal - autoKeep;

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }
}
