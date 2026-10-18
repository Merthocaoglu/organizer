import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question.dart';
import 'github_client.dart';
import 'notification_service.dart';

/// Most questions per course per day.
const dailyQuestions = 15;

/// Places kept for new questions each day, so reviews can't crowd them out.
const newPerDay = 3;

/// Leitner step: a wrong answer comes back tomorrow, each right answer
/// doubles the gap (1, 2, 4, 8, then every 16 days).
// shortcut: Leitner boxes instead of FSRS; switch if reviews feel badly timed.
({int box, DateTime due}) nextReview(int box, bool correct, DateTime day) {
  final next = correct ? box + 1 : 0;
  final days = correct ? 1 << min(next - 1, 4) : 1;
  return (box: next, due: DateTime(day.year, day.month, day.day + days));
}

/// The daily quiz: a cached copy of the repo's question files, each
/// question's Leitner box, and every answer given. Persists in
/// shared_preferences like [EventStore]; [sync] talks to GitHub.
class QuizStore extends ChangeNotifier {
  QuizStore({this.github, this.notifications});

  /// Optional so tests run without network or plugins.
  final GitHubClient? github;
  final NotificationService? notifications;

  static const _filesKey = 'organizer_quiz_files';
  static const _boxesKey = 'organizer_quiz_boxes';
  static const _attemptsKey = 'organizer_quiz_attempts';
  static const _syncedKey = 'organizer_quiz_synced';
  static const _reminderKey = 'organizer_quiz_reminder';

  List<Question> _questions = const [];
  final List<Attempt> _attempts = [];
  final Map<String, ({int box, DateTime due})> _boxes = {};
  int _synced = 0; // attempts already uploaded
  bool _syncing = false;
  TimeOfDay? _reminder;

  List<Question> get questions => _questions;
  List<Attempt> get attempts => List.unmodifiable(_attempts);
  TimeOfDay? get reminder => _reminder;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _questions = parseQuestionFiles(prefs.getStringList(_filesKey) ?? const []);
    final boxes =
        jsonDecode(prefs.getString(_boxesKey) ?? '{}') as Map<String, dynamic>;
    _boxes
      ..clear()
      ..addAll({
        for (final MapEntry(:key, :value) in boxes.entries)
          key: (box: value[0] as int, due: DateTime.parse(value[1] as String)),
      });
    _attempts
      ..clear()
      ..addAll([
        for (final a in jsonDecode(prefs.getString(_attemptsKey) ?? '[]') as List)
          Attempt.fromJson(a as Map<String, dynamic>),
      ]);
    _synced = prefs.getInt(_syncedKey) ?? 0;
    final saved = prefs.getString(_reminderKey)?.split(':');
    _reminder = saved == null
        ? null
        : TimeOfDay(hour: int.parse(saved[0]), minute: int.parse(saved[1]));
    notifyListeners();
    await notifications?.scheduleQuizReminder(_reminder);
  }

  /// Courses that have questions, sorted.
  List<String> get courses =>
      {for (final q in _questions) q.course}.toList()..sort();

  /// [course]'s test for today, up to [dailyQuestions] minus what was
  /// answered today: due reviews (oldest first) with [newPerDay] places
  /// kept for new questions, then more new ones, then early reviews
  /// (soonest first) so the day stays full while the bank is small.
  /// Nothing answered today comes back the same day.
  List<Question> todaysSet(String course, DateTime now) {
    final today = DateUtils.dateOnly(now);
    final doneToday = {
      for (final a in _attempts)
        if (a.course == course && DateUtils.isSameDay(a.at, now)) a.id,
    };
    final mine = _questions
        .where((q) => q.course == course && !doneToday.contains(q.id));
    final fresh = mine.where((q) => !_boxes.containsKey(q.id)).toList()
      ..shuffle();
    final seen = mine.where((q) => _boxes.containsKey(q.id)).toList()
      ..sort((a, b) => _boxes[a.id]!.due.compareTo(_boxes[b.id]!.due));
    final room = max(0, dailyQuestions - doneToday.length);
    final due = seen
        .takeWhile((q) => !_boxes[q.id]!.due.isAfter(today))
        .take(max(0, room - min(newPerDay, fresh.length)))
        .toList();
    return [...due, ...fresh, ...seen.skip(due.length)].take(room).toList()
      ..shuffle();
  }

  /// Saves the answer at once, so a closed app never loses it.
  Future<void> record(Question question, int chosen,
      {bool flagged = false}) async {
    final now = DateTime.now();
    final correct = chosen == question.answer;
    _attempts.add(Attempt(
      at: now,
      id: question.id,
      course: question.course,
      chosen: chosen,
      correct: correct,
      flagged: flagged,
    ));
    _boxes[question.id] =
        nextReview(_boxes[question.id]?.box ?? 0, correct, now);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_attemptsKey, jsonEncode(_attempts));
    await prefs.setString(_boxesKey, jsonEncode({
      for (final MapEntry(:key, :value) in _boxes.entries)
        key: [value.box, value.due.toIso8601String()],
    }));
  }

  /// Uploads answers not sent yet, then refreshes the question files. A
  /// no-op without a token; throws on network or auth errors, keeping the
  /// local data either way.
  Future<void> sync() async {
    final github = this.github;
    if (github == null || _syncing) return;
    if ((await github.readToken() ?? '').isEmpty) return;
    _syncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_synced < _attempts.length) {
        final batch = _attempts.sublist(_synced);
        final stamp =
            DateFormat("yyyy-MM-dd'T'HH-mm-ss").format(DateTime.now());
        await github.createFile('data/results/$stamp.json',
            const JsonEncoder.withIndent('  ').convert(batch),
            'Quiz results $stamp');
        _synced += batch.length;
        await prefs.setInt(_syncedKey, _synced);
      }
      final files = await github.fetchQuestionFiles();
      _questions = parseQuestionFiles(files);
      await prefs.setStringList(_filesKey, files);
      notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  Future<void> setReminder(TimeOfDay time) async {
    _reminder = time;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reminderKey, '${time.hour}:${time.minute}');
    await notifications?.scheduleQuizReminder(time);
  }

  /// Questions from raw question files. A broken file or entry is skipped
  /// (test/quiz_test.dart catches those before they are pushed).
  static List<Question> parseQuestionFiles(List<String> files) {
    final result = <Question>[];
    for (final file in files) {
      try {
        for (final entry in jsonDecode(file) as List) {
          try {
            result.add(Question.fromJson(entry as Map<String, dynamic>));
          } catch (_) {
            // Skip just this question.
          }
        }
      } catch (_) {
        // Not a JSON list: skip the whole file.
      }
    }
    return result;
  }
}
