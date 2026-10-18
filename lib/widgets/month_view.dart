import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../services/event_store.dart';

/// Calendar grid for one month. Days with events get a dot; tapping a
/// day opens its Day view.
class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.store,
    required this.date,
    required this.onDateChanged,
    required this.onDayTap,
  });

  final EventStore store;
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
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
                onPressed: () =>
                    onDateChanged(DateTime(date.year, date.month - 1, 1)),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM y').format(date),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    onDateChanged(DateTime(date.year, date.month + 1, 1)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const _WeekdayHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Container(
              // Cells draw top+left hairlines; this closes the grid on
              // the right and bottom.
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5),
                  bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5),
                ),
              ),
              child: MonthGrid(
                year: date.year,
                month: date.month,
                includeAdjacent: true,
                dayBuilder: (context, day) => _MonthDayCell(
                  day: day,
                  inMonth: day.month == date.month,
                  events: store.eventsOn(day),
                  onTap: () => onDayTap(day),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final label in _labels)
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// A plain Mon-first month grid; rendering of each day is delegated so
/// MonthView and YearView can share the layout logic.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.dayBuilder,
    this.includeAdjacent = false,
  });

  final int year;
  final int month;
  final Widget Function(BuildContext context, DateTime day) dayBuilder;

  /// When true, leading/trailing cells get real dates from the
  /// previous/next month (Google-Calendar style) instead of blanks;
  /// the builder can dim them via `day.month != month`.
  final bool includeAdjacent;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first
    final cellCount = leadingBlanks + daysInMonth;
    final rows = (cellCount / 7).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final dayNumber = row * 7 + col - leadingBlanks + 1;
                      if (!includeAdjacent &&
                          (dayNumber < 1 || dayNumber > daysInMonth)) {
                        return const SizedBox.shrink();
                      }
                      // DateTime normalizes out-of-range day numbers
                      // into the adjacent months.
                      return dayBuilder(
                          context, DateTime(year, month, dayNumber));
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A Google-Calendar-style month cell: day number on top, then up to a
/// few tiny category-colored event chips and a "+N" overflow line.
class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final List<Event> events;
  final VoidCallback onTap;

  static const double _chipHeight = 16; // chip + margin
  static const double _numberHeight = 24;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    final cell = InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5),
            left: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: LayoutBuilder(builder: (context, constraints) {
          // How many chip lines fit under the day number.
          final lines = math.max(
              0,
              ((constraints.maxHeight - _numberHeight) / _chipHeight)
                  .floor());
          // Reserve the last line for "+N" when not everything fits.
          final visible =
              events.length <= lines ? events.length : math.max(0, lines - 1);
          final overflow = events.length - visible;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(
                          color: scheme.primary, shape: BoxShape.circle)
                      : null,
                  child: Text(
                    '${day.day}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isToday
                              ? scheme.onPrimary
                              : inMonth
                                  ? null
                                  : scheme.outline,
                          fontWeight: isToday ? FontWeight.bold : null,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              for (final event in events.take(visible))
                Container(
                  height: _chipHeight - 2,
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: event.category.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (overflow > 0)
                Text(
                  '+$overflow',
                  style: TextStyle(fontSize: 9, color: scheme.outline),
                ),
            ],
          );
        }),
      ),
    );
    // Adjacent-month days are shown dimmed, GC-style.
    return inMonth ? cell : Opacity(opacity: 0.45, child: cell);
  }
}
