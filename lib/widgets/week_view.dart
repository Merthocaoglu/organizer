import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../services/event_store.dart';
import 'event_details_dialog.dart';
import 'time_grid.dart';

/// Google-Calendar-style week: Mon–Sun as seven columns over the shared
/// hour axis (labeled every 2 hours to keep the gutter calm), events as
/// positioned chips. Tapping a day header opens its Day view; tapping a
/// chip opens the details dialog.
class WeekView extends StatelessWidget {
  const WeekView({
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

  static bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final monday =
        DateTime(date.year, date.month, date.day - (date.weekday - 1));
    final days = List.generate(
        7, (i) => DateTime(monday.year, monday.month, monday.day + i));
    final eventsByDay = [for (final day in days) store.eventsOn(day)];

    // Scroll to just above the week's earliest event, or 8 AM.
    var firstMinutes = 24 * 60;
    for (var i = 0; i < 7; i++) {
      for (final event in eventsByDay[i]) {
        final start = event.segmentOn(days[i]).start;
        if (start < firstMinutes) firstMinutes = start;
      }
    }
    final initialHour =
        firstMinutes == 24 * 60 ? 8 : (firstMinutes ~/ 60 - 1).clamp(0, 23);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () =>
                    onDateChanged(date.subtract(const Duration(days: 7))),
              ),
              Expanded(
                child: Text(
                  '${DateFormat('MMM d').format(monday)} – '
                  '${DateFormat('MMM d').format(days.last)}',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    onDateChanged(date.add(const Duration(days: 7))),
              ),
            ],
          ),
        ),
        _WeekHeader(days: days, onDayTap: onDayTap),
        Expanded(
          child: TimeGrid(
            initialScrollHour: initialHour,
            labelStepHours: 6,
            fitToHeight: true,
            childrenBuilder: (context, geo) {
              final scheme = Theme.of(context).colorScheme;
              final colWidth = geo.laneAreaWidth / 7;
              final now = DateTime.now();
              return [
                // Vertical separators between day columns.
                for (var i = 1; i < 7; i++)
                  Positioned(
                    top: 0,
                    height: geo.gridHeight,
                    left: TimeGrid.gutterWidth + i * colWidth,
                    child: Container(width: 1, color: scheme.outlineVariant),
                  ),
                for (var i = 0; i < 7; i++) ...[
                  for (final item
                      in layoutEventColumns(eventsByDay[i], days[i]))
                    Positioned(
                      top: geo.y(item.segment.start),
                      height:
                          (geo.y(item.segment.end) - geo.y(item.segment.start))
                              .clamp(12, double.infinity),
                      left: TimeGrid.gutterWidth +
                          i * colWidth +
                          item.column * (colWidth / item.columns) +
                          1,
                      width: colWidth / item.columns - 2,
                      child: _WeekEventChip(store: store, event: item.event),
                    ),
                  if (_isToday(days[i]))
                    Positioned(
                      top: geo.y(now.hour * 60 + now.minute),
                      left: TimeGrid.gutterWidth + i * colWidth - 4,
                      width: colWidth + 4,
                      child: const NowLine(),
                    ),
                ],
              ];
            },
          ),
        ),
      ],
    );
  }
}

/// Weekday initials + date numbers above the columns; today's number is
/// the filled circle. Tapping a day opens its Day view.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.days, required this.onDayTap});

  final List<DateTime> days;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: TimeGrid.gutterWidth),
          for (final day in days)
            Expanded(
              child: InkWell(
                onTap: () => onDayTap(day),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  children: [
                    Text(
                      DateFormat('EEEEE').format(day), // single initial
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.outline),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: WeekView._isToday(day)
                          ? BoxDecoration(
                              color: scheme.primary, shape: BoxShape.circle)
                          : null,
                      child: Text(
                        '${day.day}',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: WeekView._isToday(day)
                                      ? scheme.onPrimary
                                      : null,
                                  fontWeight: WeekView._isToday(day)
                                      ? FontWeight.bold
                                      : null,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A narrow event chip in a week column: category color + tiny title.
class _WeekEventChip extends StatelessWidget {
  const _WeekEventChip({required this.store, required this.event});

  final EventStore store;
  final Event event;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: event.category.color,
      borderRadius: BorderRadius.circular(4),
      // Short chips (compressed grid) clip their text instead of
      // painting outside the bubble.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            showEventDetailsDialog(context, store: store, event: event),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              height: 1.15,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
