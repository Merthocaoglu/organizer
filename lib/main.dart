import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/event_store.dart';
import 'services/github_client.dart';
import 'services/notification_service.dart';
import 'services/quiz_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  final store = EventStore(notifications: notifications);
  await store.load();
  // After the events: their reschedule starts by cancelling every reminder.
  final quiz = QuizStore(github: GitHubClient(), notifications: notifications);
  await quiz.load();
  runApp(OrganizerApp(store: store, quiz: quiz));
}

class OrganizerApp extends StatelessWidget {
  const OrganizerApp({super.key, required this.store, required this.quiz});

  final EventStore store;
  final QuizStore quiz;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Organizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomeScreen(store: store, quiz: quiz),
    );
  }
}
