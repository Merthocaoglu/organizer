import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import 'notification_service.dart';

/// Single source of truth for events. Persists the whole list as one
/// JSON string in shared_preferences — plenty for v1 data volumes.
class EventStore extends ChangeNotifier {
  EventStore({this.notifications});

  static const _prefsKey = 'organizer_events';
  static const _customExercisesKey = 'organizer_custom_exercises';

  /// Optional so tests (and web) can run without the plugin.
  final NotificationService? notifications;
  final List<Event> _events = [];
  final List<String> _customExercises = [];
  int _idCounter = 0;

  /// User-defined gym exercises, shown after the built-in ones.
  List<String> get customExercises => List.unmodifiable(_customExercises);

  /// Events on [day], sorted by when their segment on that day starts
  /// (an overnight event's morning tail sorts at 00:00, not 23:00).
  List<Event> eventsOn(DateTime day) {
    final list = _events.where((e) => e.isOn(day)).toList();
    list.sort((a, b) {
      final cmp = a.segmentOn(day).start.compareTo(b.segmentOn(day).start);
      return cmp != 0 ? cmp : a.durationMinutes.compareTo(b.durationMinutes);
    });
    return list;
  }

  bool hasEventsOn(DateTime day) => _events.any((e) => e.isOn(day));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _customExercises
      ..clear()
      ..addAll(prefs.getStringList(_customExercisesKey) ?? const []);
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _events
        ..clear()
        ..addAll(
            decoded.map((e) => Event.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
    // Keep the OS notification queue in sync with the stored events.
    await notifications?.rescheduleAll(_events);
  }

  Future<void> addCustomExercise(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _customExercises.contains(trimmed)) return;
    _customExercises.add(trimmed);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customExercisesKey, _customExercises);
  }

  Future<void> removeCustomExercise(String name) async {
    _customExercises.remove(name);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customExercisesKey, _customExercises);
  }

  Future<void> add({
    required DateTime date,
    required TimeOfDay start,
    required TimeOfDay end,
    required String title,
    EventCategory category = EventCategory.other,
    String? notes,
    bool repeatsWeekly = false,
    int? reminderMinutes,
  }) async {
    final event = Event(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}',
      date: DateTime(date.year, date.month, date.day),
      start: start,
      end: end,
      title: title,
      category: category,
      notes: (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      repeatsWeekly: repeatsWeekly,
      reminderMinutes: reminderMinutes,
    );
    _events.add(event);
    notifyListeners();
    await _save();
    await notifications?.scheduleFor(event);
  }

  /// Replaces the event with [id] in place, keeping its identity.
  Future<void> update(
    String id, {
    required DateTime date,
    required TimeOfDay start,
    required TimeOfDay end,
    required String title,
    EventCategory category = EventCategory.other,
    String? notes,
    bool repeatsWeekly = false,
    int? reminderMinutes,
  }) async {
    final index = _events.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final event = Event(
      id: id,
      date: DateTime(date.year, date.month, date.day),
      start: start,
      end: end,
      title: title,
      category: category,
      notes: (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      repeatsWeekly: repeatsWeekly,
      reminderMinutes: reminderMinutes,
    );
    _events[index] = event;
    notifyListeners();
    await _save();
    await notifications?.scheduleFor(event);
  }

  Future<void> remove(Event event) async {
    _events.removeWhere((e) => e.id == event.id);
    notifyListeners();
    await _save();
    await notifications?.cancelFor(event);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_events.map((e) => e.toJson()).toList()));
  }
}
