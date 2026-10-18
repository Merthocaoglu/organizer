import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:organizer/models/question.dart';
import 'package:organizer/screens/quiz_screen.dart';
import 'package:organizer/services/quiz_store.dart';

/// A valid question whose right answer is option B.
Map<String, dynamic> question(String id) => {
      'id': id,
      'course': 'DSM 5001',
      'source': 'Hafta 1, slayt 1',
      'question': 'Question $id?',
      'options': ['a $id', 'b $id', 'c $id', 'd $id'],
      'answer': 1,
      'explanation': 'Because $id.',
    };

void main() {
  test('Leitner: wrong comes back tomorrow, right doubles the gap to 16 days',
      () {
    final day = DateTime(2026, 10, 18);
    expect(nextReview(3, false, day), (box: 0, due: DateTime(2026, 10, 19)));
    expect(nextReview(0, true, day), (box: 1, due: DateTime(2026, 10, 19)));
    expect(nextReview(1, true, day), (box: 2, due: DateTime(2026, 10, 20)));
    expect(nextReview(4, true, day), (box: 5, due: DateTime(2026, 11, 3)));
    expect(nextReview(9, true, day), (box: 10, due: DateTime(2026, 11, 3)));
  });

  test('broken question entries and files are skipped', () {
    final files = [
      jsonEncode([
        question('ok'),
        {...question('three'), 'options': ['a', 'b', 'c']},
        {...question('range'), 'answer': 4},
      ]),
      'not json',
    ];
    expect(QuizStore.parseQuestionFiles(files).map((q) => q.id), ['ok']);
  });

  test("today's set: one course, new ones get in, small banks stay full",
      () async {
    SharedPreferences.setMockInitialValues({
      'organizer_quiz_files': [
        jsonEncode([
          for (var i = 0; i < 20; i++) question('d$i'), // overdue below
          for (var i = 0; i < 10; i++) question('n$i'), // never seen
          for (var i = 0; i < 4; i++) {...question('o$i'), 'course': 'DSM 5014'},
        ]),
      ],
      'organizer_quiz_boxes': jsonEncode({
        for (var i = 0; i < 20; i++) 'd$i': [2, '2026-01-01T00:00:00.000'],
        for (var i = 0; i < 4; i++) 'o$i': [3, '2099-01-01T00:00:00.000'],
      }),
    });
    final store = QuizStore();
    await store.load();
    final now = DateTime.now();

    // 20 overdue reviews still leave room for new questions; no other course.
    final ids = store.todaysSet('DSM 5001', now).map((q) => q.id).toList();
    expect(ids.length, dailyQuestions);
    expect(ids.where((id) => id.startsWith('n')).length, newPerDay);
    expect(ids.every((id) => id.startsWith('d') || id.startsWith('n')), isTrue);

    // Nothing due: early reviews keep the day full.
    expect(store.todaysSet('DSM 5014', now).length, 4);

    // Today's answers use up the room and don't come back today.
    final answered = store.todaysSet('DSM 5001', now).take(5).toList();
    for (final q in answered) {
      await store.record(q, 1);
    }
    final later = store.todaysSet('DSM 5001', now);
    expect(later.length, dailyQuestions - 5);
    expect(later.where(answered.contains), isEmpty);
  });

  test('every file in data/questions parses, with unique ids', () {
    final dir = Directory('data/questions');
    if (!dir.existsSync()) return; // no question bank yet
    final ids = <String>{};
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      for (final entry in jsonDecode(file.readAsStringSync()) as List) {
        final q = Question.fromJson(entry as Map<String, dynamic>);
        expect(ids.add(q.id), isTrue, reason: 'duplicate id ${q.id}');
      }
    }
  });

  testWidgets('a round shows green/red feedback and records every answer',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'organizer_quiz_files': [
        jsonEncode([question('x'), question('y')]),
      ],
    });
    final store = QuizStore();
    await store.load();
    await tester.pumpWidget(MaterialApp(home: QuizScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Today: 2 questions'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    // The set is shuffled: read which question is on screen.
    String shown() => tester
        .widget<Text>(find.textContaining('Question '))
        .data!
        .substring(9, 10);

    final first = shown();
    await tester.tap(find.text('a $first')); // wrong
    await tester.pumpAndSettle();
    expect(find.text('Wrong — the answer is B.'), findsOneWidget);
    expect(find.text('Because $first.'), findsOneWidget);
    await tester.tap(find.text('Report bad question'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final second = shown();
    await tester.tap(find.text('b $second')); // right
    await tester.pumpAndSettle();
    expect(find.text('Correct!'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2 correct'), findsOneWidget);

    expect(store.attempts.map((a) => (a.id, a.correct, a.flagged)),
        [(first, false, true), (second, true, false)]);
  });
}
