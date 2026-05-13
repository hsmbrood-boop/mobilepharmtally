import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'korean_holidays.dart';

Future<DateTime?> showHolidayDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final first = DateTime(
    (firstDate ?? DateTime(2020)).year,
    (firstDate ?? DateTime(2020)).month,
    (firstDate ?? DateTime(2020)).day,
  );
  final last = DateTime(
    (lastDate ?? DateTime(2030)).year,
    (lastDate ?? DateTime(2030)).month,
    (lastDate ?? DateTime(2030)).day,
  );

  return showGeneralDialog<DateTime?>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final topInset = MediaQuery.paddingOf(ctx).top + 2;
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: topInset,
            left: 12,
            right: 12,
            child: _HolidayCalendarDialog(
              initialDate: initialDate,
              firstDate: first,
              lastDate: last,
            ),
          ),
        ],
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _HolidayCalendarDialog extends StatefulWidget {
  const _HolidayCalendarDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_HolidayCalendarDialog> createState() => _HolidayCalendarDialogState();
}

class _HolidayCalendarDialogState extends State<_HolidayCalendarDialog> {
  late DateTime _focusedDay;

  DateTime get _firstMonth =>
      DateTime(widget.firstDate.year, widget.firstDate.month, 1);
  DateTime get _lastMonth =>
      DateTime(widget.lastDate.year, widget.lastDate.month, 1);

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
  }

  bool _enabledDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);
  }

  /// 표시 가능한 달(1일 기준)로만 포커스를 옮긴다.
  void _goToYearMonth(int year, int month) {
    var t = DateTime(year, month, 1);
    if (t.isBefore(_firstMonth)) t = _firstMonth;
    if (t.isAfter(_lastMonth)) t = _lastMonth;
    setState(() => _focusedDay = t);
  }

  void _shiftYear(int delta) {
    _goToYearMonth(_focusedDay.year + delta, _focusedDay.month);
  }

  void _shiftMonth(int delta) {
    var y = _focusedDay.year;
    var m = _focusedDay.month + delta;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    _goToYearMonth(y, m);
  }

  bool _canShiftYear(int delta) {
    final t = DateTime(_focusedDay.year + delta, _focusedDay.month, 1);
    return !t.isBefore(_firstMonth) && !t.isAfter(_lastMonth);
  }

  bool _canShiftMonth(int delta) {
    var y = _focusedDay.year;
    var m = _focusedDay.month + delta;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    final t = DateTime(y, m, 1);
    return !t.isBefore(_firstMonth) && !t.isAfter(_lastMonth);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 42),
            child: SizedBox(
              width: 360,
              child: TableCalendar(
                firstDay: widget.firstDate,
                lastDay: widget.lastDate,
                focusedDay: _focusedDay,
                locale: 'ko_KR',
                availableGestures: AvailableGestures.horizontalSwipe,
                enabledDayPredicate: _enabledDay,
                onDaySelected: (selectedDay, focusedDay) {
                  if (!_enabledDay(selectedDay)) return;
                  final d = DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day,
                  );
                  Navigator.of(context).pop(d);
                },
                onPageChanged: (focusedDay) {
                  setState(() => _focusedDay = focusedDay);
                },
                weekendDays: const [DateTime.saturday],
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: Colors.teal,
                    shape: BoxShape.circle,
                  ),
                  holidayTextStyle: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  weekendTextStyle: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                  outsideDaysVisible: false,
                ),
                holidayPredicate: (day) =>
                    day.weekday == DateTime.sunday ||
                    KoreanHolidays.isHoliday(day),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  leftChevronVisible: false,
                  rightChevronVisible: false,
                  headerPadding: EdgeInsets.zero,
                ),
                calendarBuilders: CalendarBuilders(
                  headerTitleBuilder: (context, focusedMonth) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '이전 연도',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.keyboard_double_arrow_left),
                          onPressed: _canShiftYear(-1)
                              ? () => _shiftYear(-1)
                              : null,
                        ),
                        IconButton(
                          tooltip: '이전 달',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _canShiftMonth(-1)
                              ? () => _shiftMonth(-1)
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            '${focusedMonth.year}년 ${focusedMonth.month}월',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: '다음 달',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _canShiftMonth(1)
                              ? () => _shiftMonth(1)
                              : null,
                        ),
                        IconButton(
                          tooltip: '다음 연도',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.keyboard_double_arrow_right),
                          onPressed: _canShiftYear(1)
                              ? () => _shiftYear(1)
                              : null,
                        ),
                      ],
                    );
                  },
                  dowBuilder: (context, day) {
                    const labels = ['월', '화', '수', '목', '금', '토', '일'];
                    final label = labels[day.weekday - 1];
                    Color color;
                    if (day.weekday == DateTime.sunday) {
                      color = Colors.red;
                    } else if (day.weekday == DateTime.saturday) {
                      color = Colors.blue;
                    } else {
                      color = Colors.black87;
                    }
                    return Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Tooltip(
              message: '닫기',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(null),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
