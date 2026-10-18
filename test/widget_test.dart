import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:organizer/main.dart';
import 'package:organizer/models/event.dart';
import 'package:organizer/services/event_store.dart';

void main() {
  testWidgets('App renders the Day view shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = EventStore();
    await store.load();

    await tester.pumpWidget(OrganizerApp(store: store));

    expect(find.text('Organizer'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Today'), findsWidgets); // header chip + app bar button
  });

  testWidgets('editing a non-gym event keeps exercise-like note lines',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = EventStore();
    await store.load();
    final now = DateTime.now();
    // Not today: the red now-line can cover the title and swallow the tap.
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    const notes = 'Push-ups 3x20\nPlank\nfelt good';
    await store.add(
      date: tomorrow,
      start: const TimeOfDay(hour: 10, minute: 0),
      end: const TimeOfDay(hour: 11, minute: 0),
      title: 'Home workout',
      category: EventCategory.personal,
      notes: notes,
    );
    await tester.pumpWidget(OrganizerApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(store.eventsOn(tomorrow).single.notes, notes);
  });
}
