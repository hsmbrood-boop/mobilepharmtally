import 'package:flutter/material.dart';

/// 한국 공휴일 판정.
///
/// - 양력 고정 공휴일은 함수로 판정
/// - 설날·부처님오신날·추석 같은 음력 기반 공휴일과 대체공휴일은
///   연도별로 직접 데이터 테이블에 매핑(2020 ~ 2030년 범위).
/// - 데이터 테이블은 정부 발표(관공서의 공휴일에 관한 규정) 기준이며,
///   향후 임시공휴일이나 정부 추가 지정이 있을 경우 수동 갱신이 필요합니다.
class KoreanHolidays {
  /// 상단 날짜 문자열 색: 토요일 파랑, 일요일·공휴일 빨강, 그 외 어두운 회색.
  static Color dateBarColor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.weekday == DateTime.sunday || isHoliday(d)) {
      return Colors.red;
    }
    if (d.weekday == DateTime.saturday) {
      return Colors.blue;
    }
    return Colors.black87;
  }

  static bool isHoliday(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (_isSolarFixed(d)) return true;
    return _variableHolidays[d.year]?.contains(d) ?? false;
  }

  /// 이전 호환을 위해 유지(현재는 [isHoliday]와 동일).
  static bool isSolarHoliday(DateTime day) => isHoliday(day);

  static bool _isSolarFixed(DateTime d) {
    return switch ((d.month, d.day)) {
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

  static final Map<int, Set<DateTime>> _variableHolidays = {
    2020: {
      DateTime(2020, 1, 24), DateTime(2020, 1, 25), DateTime(2020, 1, 26), // 설날 연휴
      DateTime(2020, 1, 27), // 설날 대체공휴일(수정안)
      DateTime(2020, 4, 30), // 부처님오신날
      DateTime(2020, 9, 30), DateTime(2020, 10, 1), DateTime(2020, 10, 2), // 추석 연휴
    },
    2021: {
      DateTime(2021, 2, 11), DateTime(2021, 2, 12), DateTime(2021, 2, 13), // 설날 연휴
      DateTime(2021, 5, 19), // 부처님오신날
      DateTime(2021, 8, 16), // 광복절 대체
      DateTime(2021, 9, 20), DateTime(2021, 9, 21), DateTime(2021, 9, 22), // 추석 연휴
      DateTime(2021, 10, 4), // 개천절 대체
      DateTime(2021, 10, 11), // 한글날 대체
    },
    2022: {
      DateTime(2022, 1, 31), DateTime(2022, 2, 1), DateTime(2022, 2, 2), // 설날 연휴
      DateTime(2022, 5, 8), // 부처님오신날
      DateTime(2022, 6, 1), // 지방선거(임시)
      DateTime(2022, 9, 9), DateTime(2022, 9, 10), DateTime(2022, 9, 11), // 추석 연휴
      DateTime(2022, 9, 12), // 추석 대체
    },
    2023: {
      DateTime(2023, 1, 21), DateTime(2023, 1, 22), DateTime(2023, 1, 23), // 설날 연휴
      DateTime(2023, 1, 24), // 설날 대체
      DateTime(2023, 5, 27), // 부처님오신날
      DateTime(2023, 5, 29), // 부처님오신날 대체
      DateTime(2023, 9, 28), DateTime(2023, 9, 29), DateTime(2023, 9, 30), // 추석 연휴
    },
    2024: {
      DateTime(2024, 2, 9), DateTime(2024, 2, 10), DateTime(2024, 2, 11), // 설날 연휴
      DateTime(2024, 2, 12), // 설날 대체
      DateTime(2024, 4, 10), // 국회의원선거
      DateTime(2024, 5, 6), // 어린이날 대체(5/5 일요일)
      DateTime(2024, 5, 15), // 부처님오신날
      DateTime(2024, 9, 16), DateTime(2024, 9, 17), DateTime(2024, 9, 18), // 추석 연휴
    },
    2025: {
      DateTime(2025, 1, 27), // 설날 임시공휴일
      DateTime(2025, 1, 28), DateTime(2025, 1, 29), DateTime(2025, 1, 30), // 설날 연휴
      DateTime(2025, 5, 5), // 어린이날(부처님오신날과 겹침)
      DateTime(2025, 5, 6), // 부처님오신날 대체
      DateTime(2025, 10, 5), DateTime(2025, 10, 6), DateTime(2025, 10, 7), // 추석 연휴
      DateTime(2025, 10, 8), // 추석 대체
    },
    2026: {
      DateTime(2026, 2, 16), DateTime(2026, 2, 17), DateTime(2026, 2, 18), // 설날 연휴
      DateTime(2026, 5, 24), // 부처님오신날
      DateTime(2026, 5, 25), // 부처님오신날 대체(5/24 일요일)
      DateTime(2026, 8, 17), // 광복절 대체(8/15 토요일)
      DateTime(2026, 9, 24), DateTime(2026, 9, 25), DateTime(2026, 9, 26), // 추석 연휴
      DateTime(2026, 9, 28), // 추석 대체(9/26 토요일)
    },
    2027: {
      DateTime(2027, 2, 6), DateTime(2027, 2, 7), DateTime(2027, 2, 8), // 설날 연휴
      DateTime(2027, 2, 9), // 설날 대체(2/7 일요일)
      DateTime(2027, 5, 13), // 부처님오신날
      DateTime(2027, 9, 14), DateTime(2027, 9, 15), DateTime(2027, 9, 16), // 추석 연휴
    },
    2028: {
      DateTime(2028, 1, 26), DateTime(2028, 1, 27), DateTime(2028, 1, 28), // 설날 연휴
      DateTime(2028, 5, 2), // 부처님오신날
      DateTime(2028, 10, 2), DateTime(2028, 10, 3), DateTime(2028, 10, 4), // 추석 연휴
    },
    2029: {
      DateTime(2029, 2, 12), DateTime(2029, 2, 13), DateTime(2029, 2, 14), // 설날 연휴
      DateTime(2029, 5, 20), // 부처님오신날
      DateTime(2029, 5, 21), // 부처님오신날 대체(5/20 일요일)
      DateTime(2029, 9, 22), DateTime(2029, 9, 23), DateTime(2029, 9, 24), // 추석 연휴
      DateTime(2029, 9, 25), // 추석 대체(9/23 일요일)
    },
    2030: {
      DateTime(2030, 2, 2), DateTime(2030, 2, 3), DateTime(2030, 2, 4), // 설날 연휴
      DateTime(2030, 2, 5), // 설날 대체(2/3 일요일)
      DateTime(2030, 5, 9), // 부처님오신날
      DateTime(2030, 9, 11), DateTime(2030, 9, 12), DateTime(2030, 9, 13), // 추석 연휴
    },
  };
}
