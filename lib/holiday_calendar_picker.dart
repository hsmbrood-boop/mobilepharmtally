import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'korean_holidays.dart';

Future<DateTime?> showHolidayDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final first = DateTime((firstDate ?? DateTime(2020)).year, (firstDate ?? DateTime(2020)).month, (firstDate ?? DateTime(2020)).day);
  final last = DateTime((lastDate ?? DateTime(2030)).year, (lastDate ?? DateTime(2030)).month, (lastDate ?? DateTime(2030)).day);

  return showDialog<DateTime?>(
    context: context,
    builder: (ctx) {
      return _HolidayCalendarDialog(
        initialDate: initialDate,
        firstDate: first,
        lastDate: last,
      );
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
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime(widget.initialDate.year, widget.initialDate.month, widget.initialDate.day);
    _selectedDay = _focusedDay;
  }

  bool _enabledDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 360,
        child: TableCalendar(
          firstDay: widget.firstDate,
          lastDay: widget.lastDate,
          focusedDay: _focusedDay,
          locale: 'ko_KR',
          availableGestures: AvailableGestures.horizontalSwipe,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          enabledDayPredicate: _enabledDay,
          onDaySelected: (selectedDay, focusedDay) {
            if (!_enabledDay(selectedDay)) return;
            setState(() {
              _selectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
              _focusedDay = focusedDay;
            });
          },
          onPageChanged: (focusedDay) => _focusedDay = focusedDay,
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: Colors.teal,
              shape: BoxShape.circle,
            ),
            holidayTextStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            weekendTextStyle: const TextStyle(color: Colors.red),
            outsideDaysVisible: false,
          ),
          holidayPredicate: (day) => KoreanHolidays.isSolarHoliday(day),
          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedDay),
          child: const Text('선택'),
        ),
      ],
    );
  }
}

