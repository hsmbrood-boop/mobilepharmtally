import 'package:flutter/foundation.dart'
    show ChangeNotifier, VoidCallback, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

/// 메인(매출/정산 상세) 화면과 현금정산 화면이 공유하는 데이터.
///
/// 모든 파생값(부족한 시제, 남기는금액, 실제 입금액 등)은 원본 팜텔리 PC
/// 프로그램의 `update_calculations` 와 동일한 자동 계산 공식을 따른다.
///
/// 일부 "설정성" 값(저장 폴더 경로·작성자·기본 시제)은
/// [load] / 내부 자동 영속화 로직을 통해 앱 재실행 사이에도 유지된다.
class SettlementStore extends ChangeNotifier {
  SettlementStore._();
  static final SettlementStore instance = SettlementStore._();

  static const _kFolderPathKey = 'pharm_tally.savedFolderPath';
  static const _kAuthorKey = 'pharm_tally.author';
  static const _kBaseCashKey = 'pharm_tally.baseCash';

  // 사용자 입력값 ──────────────────────────────────────────
  String author = '최병찬';
  /// 빈 문자열이면 미지정. Windows 전용 기본 경로를 두면 안드로이드에서 존재하지 않아 로드가 항상 실패한다.
  String savedFolderPath = '';

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
    final beforeFolder = savedFolderPath;
    final beforeAuthor = author;
    final beforeBaseCash = baseCash;
    fn();
    // 설정성 값이 바뀐 경우에만 fire-and-forget 으로 영구 저장.
    if (savedFolderPath != beforeFolder ||
        author != beforeAuthor ||
        baseCash != beforeBaseCash) {
      _persist();
    }
    notifyListeners();
  }

  /// PC 스타일 절대경로 `C:\...` — 안드로이드·iOS 에서는 유효하지 않다.
  static bool _looksLikeWindowsDrivePath(String path) {
    final t = path.trim();
    return t.length >= 3 && RegExp(r'^[A-Za-z]:[/\\]').hasMatch(t);
  }

  static bool get _isIosOrAndroid =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 앱 시작 시 한 번 호출. SharedPreferences 에 저장된 설정성 값을 적용.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString(_kFolderPathKey);
      if (p != null && p.isNotEmpty) savedFolderPath = p;

      // 모바일에 PC 경로만 저장돼 있으면 폴더가 없어 엑셀을 못 읽는다 → 무시.
      if (_isIosOrAndroid && _looksLikeWindowsDrivePath(savedFolderPath)) {
        savedFolderPath = '';
        await prefs.remove(_kFolderPathKey);
      }

      final a = prefs.getString(_kAuthorKey);
      if (a != null && a.isNotEmpty) author = a;
      final bc = prefs.getInt(_kBaseCashKey);
      if (bc != null) baseCash = bc;
    } catch (_) {
      // 무시: 기본값을 사용.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFolderPathKey, savedFolderPath);
      await prefs.setString(_kAuthorKey, author);
      await prefs.setInt(_kBaseCashKey, baseCash);
    } catch (_) {
      // 무시.
    }
  }
}
