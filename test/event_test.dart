import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizer/models/event.dart';

void main() {
  Event sleep({bool repeats = false}) => Event(
        id: '1',
        date: DateTime(2026, 7, 22), // a Wednesday
        start: const TimeOfDay(hour: 23, minute: 0),
        end: const TimeOfDay(hour: 7, minute: 0),
        title: 'Sleep',
        category: EventCategory.sleep,
        repeatsWeekly: repeats,
      );

  test('overnight event spans its start day and the next morning', () {
    final e = sleep();
    expect(e.isOvernight, isTrue);
    expect(e.durationMinutes, 8 * 60);
    expect(e.isOn(DateTime(2026, 7, 22)), isTrue);
    expect(e.isOn(DateTime(2026, 7, 23)), isTrue);
    expect(e.isOn(DateTime(2026, 7, 24)), isFalse);
    expect(e.segmentOn(DateTime(2026, 7, 22)),
        (start: 23 * 60, end: 24 * 60));
    expect(e.segmentOn(DateTime(2026, 7, 23)), (start: 0, end: 7 * 60));
  });

  test('same-day event keeps the old behavior', () {
    final e = Event(
      id: '2',
      date: DateTime(2026, 7, 22),
      start: const TimeOfDay(hour: 9, minute: 0),
      end: const TimeOfDay(hour: 10, minute: 30),
      title: 'Meeting',
    );
    expect(e.isOvernight, isFalse);
    expect(e.durationMinutes, 90);
    expect(e.isOn(DateTime(2026, 7, 22)), isTrue);
    expect(e.isOn(DateTime(2026, 7, 23)), isFalse);
    expect(e.segmentOn(DateTime(2026, 7, 22)),
        (start: 9 * 60, end: 10 * 60 + 30));
  });

  test('event ending exactly at midnight stays on its start day', () {
    final e = Event(
      id: '3',
      date: DateTime(2026, 7, 22),
      start: const TimeOfDay(hour: 22, minute: 0),
      end: const TimeOfDay(hour: 0, minute: 0),
      title: 'Party',
    );
    expect(e.durationMinutes, 2 * 60);
    expect(e.isOn(DateTime(2026, 7, 22)), isTrue);
    expect(e.isOn(DateTime(2026, 7, 23)), isFalse);
  });

  test('weekly recurring overnight event has a tail every week', () {
    final e = sleep(repeats: true);
    expect(e.isOn(DateTime(2026, 7, 29)), isTrue); // next Wednesday
    expect(e.isOn(DateTime(2026, 7, 30)), isTrue); // Thursday morning
    expect(e.isOn(DateTime(2026, 7, 28)), isFalse); // Tuesday
    expect(e.isOn(DateTime(2026, 7, 16)), isFalse); // before series start
  });
}
