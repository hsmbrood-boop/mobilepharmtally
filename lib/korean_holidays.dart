class KoreanHolidays {
  // 우선: 양력 고정 공휴일만 포함 (대체공휴일/설/추석 등 음력 기반은 추후 확장)
  static bool isSolarHoliday(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final m = d.month;
    final dd = d.day;
    return switch ((m, dd)) {
      (1, 1) => true, // 신정
      (3, 1) => true, // 삼일절
      (5, 5) => true, // 어린이날
      (6, 6) => true, // 현충일
      (8, 15) => true, // 광복절
      (10, 3) => true, // 개천절
      (10, 9) => true, // 한글날
      (12, 25) => true, // 성탄절
      _ => false,
    };
  }
}

