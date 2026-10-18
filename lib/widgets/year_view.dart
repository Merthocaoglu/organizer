import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/event_store.dart';
import 'month_view.dart';

/// 12 mini-month grids for one year. Tapping a month name opens its
/// Month view; tapping a day jumps straight to that Day view. Days are
/// tinted by how busy they are (more scheduled hours = deeper tint).
class YearView extends StatelessWidget {
  const YearView({
    super.key,
    required this.store,
    required this.date,
    required this.onDateChanged,
    required this.onMonthTap,
    required this.onDayTap,
  });

  final EventStore store;
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onMonthTap;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onDateChanged(DateTime(date.year - 1, 1, 1)),
              ),
              Expanded(
                child: Text(
                  '${date.year}',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onDateChanged(DateTime(date.year + 1, 1, 1)),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 0.95,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            children: [
              for (var month = 1; month <= 12; month++)
                _MiniMonth(
                  store: store,
                  year: date.year,
                  month: month,
                  onMonthTap: () => onMonthTap(DateTime(date.year, month, 1)),
                  onDayTap: onDayTap,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.store,
    required this.year,
    required this.month,
    required this.onMonthTap,
    required this.onDayTap,
  });

  final EventStore store;
  final int year;
  final int month;
  final VoidCallback onMonthTap;
  final ValueChanged<DateTime> onDayTap;

  /// Scheduled minutes on [day] (overnight events count only the part
  /// falling on that day).
  int _minutesOn(DateTime day) {
    var total = 0;
    for (final event in store.eventsOn(day)) {
      final segment = event.segmentOn(day);
      total += segment.end - segment.start;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrentMonth = year == now.year && month == now.month;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onMonthTap,
            borderRadius: BorderRadius.circular(8),
            child: Text(
              DateFormat('MMM').format(DateTime(year, month)),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isCurrentMonth ? scheme.primary : null,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: MonthGrid(
              year: year,
              month: month,
              dayBuilder: (context, day) => _MiniDayCell(
                day: day,
                minutes: _minutesOn(day),
                onTap: () => onDayTap(day),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDayCell extends StatelessWidget {
  const _MiniDayCell({
    required this.day,
    required this.minutes,
    required this.onTap,
  });

  final DateTime day;
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    // Heat: 0h → container color, 12h+ → most of the way to primary.
    final heat = (minutes / 720).clamp(0.0, 1.0) * 0.7;
    final background = isToday
        ? scheme.primary
        : minutes == 0
            ? null
            : Color.lerp(scheme.primaryContainer, scheme.primary, heat);
    final foreground = isToday
        ? scheme.onPrimary
        : minutes == 0
            ? scheme.onSurfaceVariant
            : heat > 0.35
                ? scheme.onPrimary
                : scheme.onPrimaryContainer;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: background == null
              ? null
              : BoxDecoration(color: background, shape: BoxShape.circle),
          child: Text(
            '${day.day}',
            style: TextStyle(fontSize: 8, color: foreground),
          ),
        ),
      ),
    );
  }
}
