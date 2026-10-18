import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';

/// Resolved layout numbers for one [TimeGrid] build, handed to the
/// children builder so positions track the actual hour height.
class TimeGridGeometry {
  const TimeGridGeometry({
    required this.laneAreaWidth,
    required this.hourHeight,
  });

  /// Width to the right of the gutter, minus the 16px right padding.
  final double laneAreaWidth;
  final double hourHeight;

  double get gridHeight => 24 * hourHeight;

  /// Vertical pixel position of a minutes-from-midnight value.
  double y(int minutes) => minutes / 60 * hourHeight;
}

/// Shared 24-hour grid: hour labels in a left gutter, hour divider
/// lines, and caller-positioned children (event bubbles, the now-line)
/// stacked on top. The Day and Week timelines both build on this so
/// their hour axes can't drift apart.
///
/// Scrolls at [hourHeight] px/hour by default; with [fitToHeight] the
/// whole day is compressed to the viewport instead (used by Week view).
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.initialScrollHour,
    required this.childrenBuilder,
    this.labelStepHours = 1,
    this.fitToHeight = false,
  });

  /// Hour (0–23) scrolled to when the grid is first shown (ignored in
  /// [fitToHeight] mode — everything is already visible).
  final int initialScrollHour;

  /// Gutter labels (and their divider lines) are drawn every this many
  /// hours — 1 for the Day view, sparser for the Week view.
  final int labelStepHours;

  /// Compress 24h into the available height instead of scrolling.
  final bool fitToHeight;

  final List<Widget> Function(BuildContext context, TimeGridGeometry geometry)
      childrenBuilder;

  static const double hourHeight = 64;
  static const double gutterWidth = 64;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  late final ScrollController _scrollController = ScrollController(
      initialScrollOffset: widget.fitToHeight
          ? 0
          : widget.initialScrollHour * TimeGrid.hourHeight);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      // Never compress below 18px/hour — past that, fall back to
      // scrolling rather than making events unreadable.
      final hourHeight = widget.fitToHeight
          ? math.max((constraints.maxHeight - 16) / 24, 18.0)
          : TimeGrid.hourHeight;
      final geometry = TimeGridGeometry(
        laneAreaWidth: constraints.maxWidth - TimeGrid.gutterWidth - 16,
        hourHeight: hourHeight,
      );
      return SingleChildScrollView(
        controller: _scrollController,
        child: SizedBox(
          height: geometry.gridHeight + 16,
          child: Stack(
            children: [
              for (var hour = 0;
                  hour < 24;
                  hour += widget.labelStepHours) ...[
                Positioned(
                  top: hour * hourHeight - 7,
                  left: 0,
                  width: TimeGrid.gutterWidth - 8,
                  child: Text(
                    hour == 0
                        ? ''
                        : DateFormat('j').format(DateTime(2020, 1, 1, hour)),
                    textAlign: TextAlign.right,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ),
                Positioned(
                  top: hour * hourHeight,
                  left: TimeGrid.gutterWidth,
                  right: 0,
                  child: Divider(height: 1, color: scheme.outlineVariant),
                ),
              ],
              ...widget.childrenBuilder(context, geometry),
            ],
          ),
        ),
      );
    });
  }
}

/// The red "current time" marker: a dot on the gutter edge plus a line
/// across whatever width the parent Positioned gives it.
class NowLine extends StatelessWidget {
  const NowLine({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: scheme.error, shape: BoxShape.circle),
        ),
        Expanded(child: Container(height: 2, color: scheme.error)),
      ],
    );
  }
}

class LaidOutEvent {
  LaidOutEvent(this.event, this.segment);
  final Event event;
  final ({int start, int end}) segment; // this day's portion, minutes
  int column = 0;
  int columns = 1;
}

/// Google-Calendar-style overlap handling: events that overlap in time
/// are split into side-by-side columns within their overlap cluster.
/// Overlap is judged on each event's segment on [day], so an overnight
/// tail occupies the morning, not its literal start time.
List<LaidOutEvent> layoutEventColumns(List<Event> events, DateTime day) {
  int startOf(Event e) => e.segmentOn(day).start;
  int endOf(Event e) => e.segmentOn(day).end;

  final items = [
    for (final e in events) LaidOutEvent(e, e.segmentOn(day)),
  ]; // already sorted by segment start
  var clusterStart = 0;
  var clusterEnd = -1;
  final columnEnds = <int>[]; // end time of the last event in each column

  void closeCluster(int upTo) {
    for (var i = clusterStart; i < upTo; i++) {
      items[i].columns = columnEnds.length;
    }
    columnEnds.clear();
  }

  for (var i = 0; i < items.length; i++) {
    final event = items[i].event;
    if (startOf(event) >= clusterEnd && columnEnds.isNotEmpty) {
      closeCluster(i);
      clusterStart = i;
    }
    // First column whose last event has ended, else a new column.
    var col = columnEnds.indexWhere((end) => end <= startOf(event));
    if (col == -1) {
      col = columnEnds.length;
      columnEnds.add(endOf(event));
    } else {
      columnEnds[col] = endOf(event);
    }
    items[i].column = col;
    if (endOf(event) > clusterEnd) clusterEnd = endOf(event);
  }
  closeCluster(items.length);
  return items;
}
