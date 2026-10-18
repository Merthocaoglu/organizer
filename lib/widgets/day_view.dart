import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../services/event_store.dart';
import 'event_details_dialog.dart';
import 'time_grid.dart';

/// The main view: a Google-Calendar-style timeline for one day —
/// hour labels + lines on the left, events as positioned bubbles.
class DayView extends StatelessWidget {
  const DayView({
    super.key,
    required this.store,
    required this.date,
    required this.onDateChanged,
  });

  final EventStore store;
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DayHeader(date: date, onDateChanged: onDateChanged),
        Expanded(
          child: DayTimeline(store: store, date: date),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.onDateChanged});

  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                onDateChanged(date.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat('EEEE, MMM d').format(date),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (isToday)
                  Text('Today',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onDateChanged(date.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }
}

/// One day's events laid out on the shared [TimeGrid].
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.store, required this.date});

  final EventStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final events = store.eventsOn(date);
    final laidOut = layoutEventColumns(events, date);
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    // Start the view just above the first event, or at 8 AM.
    final initialHour = events.isEmpty
        ? 8
        : (events.first.segmentOn(date).start ~/ 60 - 1).clamp(0, 23);

    return TimeGrid(
      initialScrollHour: initialHour,
      childrenBuilder: (context, geo) => [
        // Event bubbles, clipped to this day's segment (an overnight
        // event shows its evening here and its morning the next day).
        for (final item in laidOut)
          Positioned(
            top: geo.y(item.segment.start),
            height: (geo.y(item.segment.end) - geo.y(item.segment.start))
                .clamp(28, double.infinity),
            left: TimeGrid.gutterWidth +
                item.column * (geo.laneAreaWidth / item.columns) +
                2,
            width: geo.laneAreaWidth / item.columns - 4,
            child: _EventBubble(store: store, event: item.event),
          ),
        if (isToday)
          Positioned(
            top: geo.y(now.hour * 60 + now.minute),
            left: TimeGrid.gutterWidth - 4,
            right: 0,
            child: const NowLine(),
          ),
      ],
    );
  }
}

class _EventBubble extends StatelessWidget {
  const _EventBubble({required this.store, required this.event});

  final EventStore store;
  final Event event;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: event.category.color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () =>
            showEventDetailsDialog(context, store: store, event: event),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${event.start.format(context)} – ${event.end.format(context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  if (event.notes != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.notes, size: 12, color: Colors.white),
                  ],
                  if (event.repeatsWeekly) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.repeat, size: 12, color: Colors.white),
                  ],
                  if (event.reminderMinutes != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.notifications,
                        size: 12, color: Colors.white),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
