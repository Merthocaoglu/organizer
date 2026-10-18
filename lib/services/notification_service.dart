import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';

/// Schedules a local notification [Event.reminderMinutes] before each
/// event's start time. Weekly-recurring events use the plugin's
/// day-of-week repeat, so one schedule covers every occurrence.
///
/// flutter_local_notifications has no web support, so every method is a
/// no-op on web (Chrome stays the UI dev preview; reminders are verified
/// on a real device).
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _quizReminderId = -1; // event ids (idFor) are never negative
  bool _initialized = false;
  bool _permissionsRequested = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'event_reminders',
      'Event reminders',
      channelDescription: 'Reminders before scheduled events',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Unknown zone: tz.local stays UTC — reminders may be offset but
      // nothing crashes.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _initialized = true;
  }

  /// Asks for the Android 13+ notification permission the first time a
  /// reminder is scheduled in this run — at launch too, when saved events
  /// have upcoming reminders. Exact alarms need no prompt: the manifest's
  /// USE_EXACT_ALARM is granted at install.
  Future<void> _ensurePermissions() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Stable 31-bit notification id for an event id like
  /// "1721550000000_3" (FNV-1a, so it survives app restarts).
  static int idFor(String eventId) {
    var hash = 0x811c9dc5;
    for (final unit in eventId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> cancelFor(Event event) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(id: idFor(event.id));
  }

  /// (Re)schedules the reminder for [event]; cancels any previous one.
  Future<void> scheduleFor(Event event) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(id: idFor(event.id));
    final minutes = event.reminderMinutes;
    if (minutes == null) return;

    var when = tz.TZDateTime(
      tz.local,
      event.date.year,
      event.date.month,
      event.date.day,
      event.start.hour,
      event.start.minute,
    ).subtract(Duration(minutes: minutes));

    final now = tz.TZDateTime.now(tz.local);
    if (event.repeatsWeekly) {
      // The plugin repeats by day-of-week + time; it just needs the
      // first future occurrence as the anchor.
      while (!when.isAfter(now)) {
        when = when.add(const Duration(days: 7));
      }
    } else if (!when.isAfter(now)) {
      return; // Reminder time already passed.
    }

    final startLabel =
        '${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}';
    final body = minutes == 0
        ? 'Starting now ($startLabel)'
        : 'Starts in $minutes min ($startLabel)';
    await _schedule(idFor(event.id), event.title, body, when,
        event.repeatsWeekly ? DateTimeComponents.dayOfWeekAndTime : null);
  }

  /// Daily quiz reminder at [time]; null turns it off.
  Future<void> scheduleQuizReminder(TimeOfDay? time) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(id: _quizReminderId);
    if (time == null) return;
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!when.isAfter(now)) {
      when = tz.TZDateTime(
          tz.local, now.year, now.month, now.day + 1, time.hour, time.minute);
    }
    await _schedule(_quizReminderId, 'Daily quiz',
        "Today's questions are waiting", when, DateTimeComponents.time);
  }

  Future<void> _schedule(int id, String title, String body,
      tz.TZDateTime when, DateTimeComponents? repeat) async {
    await _ensurePermissions();
    Future<void> zoned(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: _details,
          androidScheduleMode: mode,
          matchDateTimeComponents: repeat,
        );
    try {
      await zoned(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      // Exact alarms not permitted on this device — inexact is close
      // enough (may be delayed a few minutes).
      await zoned(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Drops every pending notification and schedules from [events] —
  /// run after load so the OS queue always mirrors the stored data.
  Future<void> rescheduleAll(List<Event> events) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancelAll();
    for (final event in events) {
      if (event.reminderMinutes != null) {
        await scheduleFor(event);
      }
    }
  }
}
