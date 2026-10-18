import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/event_store.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  final store = EventStore(notifications: notifications);
  await store.load();
  runApp(OrganizerApp(store: store));
}

class OrganizerApp extends StatelessWidget {
  const OrganizerApp({super.key, required this.store});

  final EventStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Organizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomeScreen(store: store),
    );
  }
}
