import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../models/workout_notes.dart';
import '../services/event_store.dart';

enum StatsPeriod { day, week, month, year }

/// Schedule analysis for a selectable period: total scheduled time,
/// share per category (donut + labeled rows with drill-down), and an
/// hours-per-bucket bar list (days of a week, weeks of a month, months
/// of a year). Identity is always carried by text labels, never by
/// color alone.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.store, required this.date});

  final EventStore store;
  final DateTime date;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsPeriod _period = StatsPeriod.week;
  late DateTime _anchor =
      DateTime(widget.date.year, widget.date.month, widget.date.day);

  /// Category whose row is expanded to show the period's events.
  EventCategory? _expanded;

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
  }

  static String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  List<DateTime> _days() {
    switch (_period) {
      case StatsPeriod.day:
        return [_anchor];
      case StatsPeriod.week:
        final monday = _mondayOf(_anchor);
        return List.generate(
            7, (i) => DateTime(monday.year, monday.month, monday.day + i));
      case StatsPeriod.month:
        final count = DateTime(_anchor.year, _anchor.month + 1, 0).day;
        return List.generate(
            count, (i) => DateTime(_anchor.year, _anchor.month, i + 1));
      case StatsPeriod.year:
        return [
          for (var month = 1; month <= 12; month++)
            for (var d = 1;
                d <= DateTime(_anchor.year, month + 1, 0).day;
                d++)
              DateTime(_anchor.year, month, d),
        ];
    }
  }

  void _shift(int direction) {
    setState(() {
      switch (_period) {
        case StatsPeriod.day:
          _anchor = _anchor.add(Duration(days: direction));
        case StatsPeriod.week:
          _anchor = _anchor.add(Duration(days: 7 * direction));
        case StatsPeriod.month:
          _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
        case StatsPeriod.year:
          _anchor = DateTime(_anchor.year + direction, 1, 1);
      }
    });
  }

  String _rangeLabel(List<DateTime> days) {
    switch (_period) {
      case StatsPeriod.day:
        return DateFormat('EEEE, MMM d, y').format(_anchor);
      case StatsPeriod.week:
        return '${DateFormat('MMM d').format(days.first)} – '
            '${DateFormat('MMM d').format(days.last)}';
      case StatsPeriod.month:
        return DateFormat('MMMM y').format(_anchor);
      case StatsPeriod.year:
        return '${_anchor.year}';
    }
  }

  /// Day-label format for drill-down rows.
  DateFormat get _dayFormat => _period == StatsPeriod.week ||
          _period == StatsPeriod.day
      ? DateFormat('EEE')
      : DateFormat('MMM d');

  double get _dayLabelWidth =>
      _period == StatsPeriod.week || _period == StatsPeriod.day ? 40 : 56;

  /// The bar-list section: (title, rows). Null for the day period.
  (String, List<_Bucket>)? _buckets(
      List<DateTime> days, List<int> minutesPerDay) {
    switch (_period) {
      case StatsPeriod.day:
        return null;
      case StatsPeriod.week:
        return (
          'Hours per day',
          [
            for (var i = 0; i < days.length; i++)
              _Bucket(DateFormat('EEE').format(days[i]), minutesPerDay[i],
                  _isToday(days[i])),
          ]
        );
      case StatsPeriod.month:
        final leading = DateTime(_anchor.year, _anchor.month, 1).weekday - 1;
        final count = ((leading + days.length) / 7).ceil();
        final buckets = [
          for (var b = 0; b < count; b++)
            _Bucket(
                DateFormat('MMM d').format(DateTime(
                    _anchor.year, _anchor.month, 1 - leading + b * 7)),
                0,
                false),
        ];
        for (var i = 0; i < days.length; i++) {
          final b = (leading + i) ~/ 7;
          buckets[b] = _Bucket(
            buckets[b].label,
            buckets[b].minutes + minutesPerDay[i],
            buckets[b].highlight || _isToday(days[i]),
          );
        }
        return ('Hours per week', buckets);
      case StatsPeriod.year:
        final now = DateTime.now();
        final buckets = [
          for (var month = 1; month <= 12; month++)
            _Bucket(
                DateFormat('MMM').format(DateTime(_anchor.year, month)),
                0,
                _anchor.year == now.year && month == now.month),
        ];
        for (var i = 0; i < days.length; i++) {
          final b = days[i].month - 1;
          buckets[b] = _Bucket(
              buckets[b].label, buckets[b].minutes + minutesPerDay[i],
              buckets[b].highlight);
        }
        return ('Hours per month', buckets);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final days = _days();

          // Minutes and events per category, minutes per day.
          final byCategory = <EventCategory, int>{};
          final eventsByCategory = <EventCategory, List<(DateTime, Event)>>{};
          final minutesPerDay = List.filled(days.length, 0);
          for (var i = 0; i < days.length; i++) {
            for (final event in widget.store.eventsOn(days[i])) {
              // Only the part of the event on this day, so overnight
              // events split their minutes across both days.
              final segment = event.segmentOn(days[i]);
              final minutes = segment.end - segment.start;
              byCategory.update(event.category, (v) => v + minutes,
                  ifAbsent: () => minutes);
              // List each occurrence once, on the day it starts; keep a
              // first-day morning tail whose start day is out of range.
              if (event.startsOn(days[i]) || i == 0) {
                eventsByCategory
                    .putIfAbsent(event.category, () => [])
                    .add((days[i], event));
              }
              minutesPerDay[i] += minutes;
            }
          }
          final total = minutesPerDay.fold(0, (a, b) => a + b);
          final categories = EventCategory.values
              .where((c) => (byCategory[c] ?? 0) > 0)
              .toList();
          final buckets = _buckets(days, minutesPerDay);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<StatsPeriod>(
                segments: const [
                  ButtonSegment(value: StatsPeriod.day, label: Text('Day')),
                  ButtonSegment(value: StatsPeriod.week, label: Text('Week')),
                  ButtonSegment(
                      value: StatsPeriod.month, label: Text('Month')),
                  ButtonSegment(value: StatsPeriod.year, label: Text('Year')),
                ],
                selected: {_period},
                onSelectionChanged: (selection) =>
                    setState(() => _period = selection.first),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shift(-1),
                  ),
                  Expanded(
                    child: Text(
                      _rangeLabel(days),
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shift(1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (total == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      'Nothing scheduled in this period.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 200,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      segments: [
                        for (final c in categories)
                          (color: c.color, value: byCategory[c]!.toDouble()),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatDuration(total),
                              style:
                                  Theme.of(context).textTheme.headlineSmall),
                          Text('scheduled',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                for (final c in categories) ...[
                  _CategoryRow(
                    category: c,
                    minutes: byCategory[c]!,
                    share: byCategory[c]! / total,
                    label: _formatDuration(byCategory[c]!),
                    expanded: _expanded == c,
                    onTap: () => setState(
                        () => _expanded = _expanded == c ? null : c),
                  ),
                  if (_expanded == c)
                    _CategoryDetails(
                      category: c,
                      entries: eventsByCategory[c]!,
                      dayFormat: _dayFormat,
                      dayLabelWidth: _dayLabelWidth,
                      knownExercises: [
                        ...builtInExercises,
                        ...widget.store.customExercises,
                      ],
                    ),
                  const SizedBox(height: 12),
                ],
                if (buckets != null) ...[
                  const Divider(height: 32),
                  Text(buckets.$1,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  for (final bucket in buckets.$2)
                    _BarRow(
                      label: bucket.label,
                      labelWidth: _dayLabelWidth,
                      minutes: bucket.minutes,
                      fraction: bucket.minutes /
                          buckets.$2
                              .map((b) => b.minutes)
                              .reduce(math.max)
                              .clamp(1, 1 << 31),
                      highlight: bucket.highlight,
                      text: _formatDuration(bucket.minutes),
                    ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Bucket {
  const _Bucket(this.label, this.minutes, this.highlight);
  final String label;
  final int minutes;
  final bool highlight; // contains today
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.minutes,
    required this.share,
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final EventCategory category;
  final int minutes;
  final double share;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = (share * 100).round();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: category.color, radius: 5),
              const SizedBox(width: 8),
              Expanded(child: Text(category.label)),
              Text('$label · $percent%',
                  style: Theme.of(context).textTheme.bodyMedium),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              color: category.color,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// The expanded panel under a category row: the period's events of that
/// category. For Gym it additionally parses the workout notes and lists
/// the exercises done in the period.
class _CategoryDetails extends StatelessWidget {
  const _CategoryDetails({
    required this.category,
    required this.entries,
    required this.dayFormat,
    required this.dayLabelWidth,
    required this.knownExercises,
  });

  /// (day, event), in day-then-start order.
  final List<(DateTime, Event)> entries;
  final EventCategory category;
  final DateFormat dayFormat;
  final double dayLabelWidth;
  final List<String> knownExercises;

  static String _duration(Event e) {
    final minutes = e.durationMinutes;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// "3×12 @ 60kg", degrading gracefully when parts are missing.
  static String _exerciseDetail(ExerciseLine e) {
    final setsReps = e.sets.isNotEmpty && e.reps.isNotEmpty
        ? '${e.sets}×${e.reps}'
        : e.sets.isNotEmpty
            ? '${e.sets} sets'
            : e.reps.isNotEmpty
                ? '${e.reps} reps'
                : '';
    final weight = e.weight.isNotEmpty ? '${e.weight}kg' : '';
    if (setsReps.isEmpty) return weight;
    return weight.isEmpty ? setsReps : '$setsReps @ $weight';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayStyle =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final rows = <Widget>[];

    if (category == EventCategory.gym) {
      // Sessions, then every exercise parsed from the period's notes —
      // one line per session so progression over time is visible.
      final exerciseRows = <Widget>[];
      for (final (day, event) in entries) {
        final parsed = parseWorkoutNotes(event.notes, knownExercises);
        final dayLabel = dayFormat.format(day);
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                  width: dayLabelWidth,
                  child: Text(dayLabel, style: dayStyle)),
              Expanded(
                child: Text(
                  parsed.workoutType == null
                      ? event.title
                      : '${event.title} · ${parsed.workoutType}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_duration(event), style: theme.textTheme.bodySmall),
            ],
          ),
        ));
        for (final exercise in parsed.exercises) {
          exerciseRows.add(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child:
                      Text(exercise.name, overflow: TextOverflow.ellipsis),
                ),
                Text(_exerciseDetail(exercise),
                    style: theme.textTheme.bodyMedium),
                SizedBox(
                  width: dayLabelWidth,
                  child: Text(dayLabel,
                      textAlign: TextAlign.right, style: dayStyle),
                ),
              ],
            ),
          ));
        }
      }
      rows.add(const SizedBox(height: 8));
      rows.add(Text('Exercises', style: theme.textTheme.titleSmall));
      rows.add(const SizedBox(height: 6));
      if (exerciseRows.isEmpty) {
        rows.add(Text('No exercises logged in this period.',
            style: dayStyle));
      } else {
        rows.addAll(exerciseRows);
      }
    } else {
      for (final (day, event) in entries) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: dayLabelWidth,
                child: Text(dayFormat.format(day), style: dayStyle),
              ),
              Text(
                '${event.start.format(context)} – ${event.end.format(context)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(event.title, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ));
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.labelWidth,
    required this.minutes,
    required this.fraction,
    required this.highlight,
    required this.text,
  });

  final String label;
  final double labelWidth;
  final int minutes;
  final double fraction;
  final bool highlight;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: highlight ? FontWeight.bold : null,
                    color: highlight ? scheme.primary : null,
                  ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: minutes == 0 ? 0 : fraction,
                minHeight: 10,
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              minutes == 0 ? '—' : text,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Donut with a small angular gap between segments (the "2px surface
/// gap" rule) so adjacent colors never touch.
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments});

  final List<({Color color, double value})> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (a, s) => a + s.value);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;
    const stroke = 26.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gap = segments.length > 1 ? 0.04 : 0.0; // radians between arcs

    var startAngle = -math.pi / 2;
    for (final segment in segments) {
      final sweep = segment.value / total * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = segment.color;
      canvas.drawArc(rect, startAngle + gap / 2,
          math.max(sweep - gap, 0.02), false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.segments != segments;
}
