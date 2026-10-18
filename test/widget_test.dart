import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:organizer/main.dart';
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
}
