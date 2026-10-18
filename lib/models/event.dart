import 'package:flutter/material.dart';

/// Fixed v1 category palette. Bubble/backgrounds use [color] with white
/// text — all shades chosen dark enough for that contrast.
enum EventCategory {
  gym('Gym', Color(0xFFE53935)), // red
  work('Work', Color(0xFF1E88E5)), // blue
  social('Social', Color(0xFFFB8C00)), // orange
  personal('Personal', Color(0xFF8E24AA)), // purple
  sleep('Sleep', Color(0xFF3949AB)), // indigo — night
  other('Other', Color(0xFF00897B)); // teal

  const EventCategory(this.label, this.color);

  final String label;
  final Color color;
}

/// A single schedule entry: something to do on a day, from [start] to [end].
class Event {
  final String id;
  final DateTime date; // date only; times live in [start]/[end]
  final TimeOfDay start;
  final TimeOfDay end;
  final String title;
  final EventCategory category;
  final String? notes;

  /// When true, the event recurs every week on `date.weekday`,
  /// starting from [date]. All occurrences share this one Event.
  final bool repeatsWeekly;

  /// Minutes before [start] to show a notification.
  /// null = no reminder, 0 = at start time.
  final int? reminderMinutes;

  Event({
    required this.id,
    required this.date,
    required this.start,
    required this.end,
    required this.title,
    this.category = EventCategory.other,
    this.notes,
    this.repeatsWeekly = false,
    this.reminderMinutes,
  });

  int get startMinutes => start.hour * 60 + start.minute;
  int get endMinutes => end.hour * 60 + end.minute;

  /// True when the event crosses midnight and ends the following day
  /// (encoded as end < start; equal times are rejected by the form).
  bool get isOvernight => endMinutes < startMinutes;

  /// Full length in minutes, wrapping past midnight when overnight.
  int get durationMinutes => isOvernight
      ? 24 * 60 - startMinutes + endMinutes
      : endMinutes - startMinutes;

  /// Whether an occurrence *starts* on the given calendar day
  /// (including weekly recurrences on/after the start date).
  bool startsOn(DateTime day) {
    if (date.year == day.year &&
        date.month == day.month &&
        date.day == day.day) {
      return true;
    }
    if (!repeatsWeekly) return false;
    return day.weekday == date.weekday &&
        DateTime(day.year, day.month, day.day).isAfter(date);
  }

  /// Whether any part of this event falls on the given day — its start
  /// day, plus the following morning for overnight events.
  bool isOn(DateTime day) =>
      startsOn(day) ||
      (isOvernight && startsOn(DateTime(day.year, day.month, day.day - 1)));

  /// The part of the event on [day], in minutes from midnight: the
  /// evening segment on its start day (clipped at 24:00 when
  /// overnight), the morning segment on the day it ends.
  ({int start, int end}) segmentOn(DateTime day) {
    if (startsOn(day)) {
      return (start: startMinutes, end: isOvernight ? 24 * 60 : endMinutes);
    }
    return (start: 0, end: endMinutes);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': '${date.year}-${date.month}-${date.day}',
        'hour': start.hour,
        'minute': start.minute,
        'endHour': end.hour,
        'endMinute': end.minute,
        'title': title,
        'category': category.name,
        if (notes != null) 'notes': notes,
        if (repeatsWeekly) 'repeat': 'weekly',
        if (reminderMinutes != null) 'reminder': reminderMinutes,
      };

  factory Event.fromJson(Map<String, dynamic> json) {
    final parts = (json['date'] as String).split('-').map(int.parse).toList();
    final start = TimeOfDay(
        hour: json['hour'] as int, minute: json['minute'] as int);
    // Events saved before end times existed get start + 1h.
    final end = json['endHour'] == null
        ? TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute)
        : TimeOfDay(
            hour: json['endHour'] as int, minute: json['endMinute'] as int);
    return Event(
      id: json['id'] as String,
      date: DateTime(parts[0], parts[1], parts[2]),
      start: start,
      end: end,
      title: json['title'] as String,
      category: EventCategory.values
              .asNameMap()[json['category'] as String? ?? ''] ??
          EventCategory.other,
      notes: json['notes'] as String?,
      repeatsWeekly: json['repeat'] == 'weekly',
      reminderMinutes: json['reminder'] as int?,
    );
  }
}
