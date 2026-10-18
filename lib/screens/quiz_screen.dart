import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/question.dart';
import '../services/quiz_store.dart';

/// Daily quiz: today's count and Start, then one question at a time with
/// green/red feedback and the slide's explanation; history below.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.store});

  final QuizStore store;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Question>? _session; // null on the start page
  int _index = 0;
  int? _chosen; // option picked for the current question
  bool _flagged = false;
  int _correct = 0;

  @override
  void initState() {
    super.initState();
    _sync(quiet: true);
  }

  Future<void> _sync({bool quiet = false}) async {
    String? message;
    try {
      await widget.store.sync();
      if (!quiet) message = 'Synced: ${widget.store.questions.length} questions';
    } catch (e) {
      message = 'Sync failed: $e';
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _next(Question question) async {
    final chosen = _chosen!;
    final flagged = _flagged;
    // Advance first, so a double tap can't record the answer twice.
    setState(() {
      if (chosen == question.answer) _correct++;
      _index++;
      _chosen = null;
      _flagged = false;
    });
    await widget.store.record(question, chosen, flagged: flagged);
    if (_index == _session!.length) await _sync(quiet: true); // upload
  }

  Future<void> _settings() async {
    final store = widget.store;
    final token = TextEditingController();
    var time = store.reminder ?? const TimeOfDay(hour: 21, minute: 0);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Quiz settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub token',
                  helperText: 'Leave empty to keep the saved one',
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Daily reminder'),
                trailing: Text(time.format(context)),
                onTap: () async {
                  final picked =
                      await showTimePicker(context: context, initialTime: time);
                  if (picked != null) setDialogState(() => time = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    if (token.text.trim().isNotEmpty) {
      await store.github?.saveToken(token.text);
    }
    await store.setReminder(time);
    await _sync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily quiz'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync',
            onPressed: _sync,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _settings,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final session = _session;
          if (session == null) return _startPage();
          if (_index == session.length) return _summary(session.length);
          return _questionPage(session[_index], session.length);
        },
      ),
    );
  }

  // Shown next to the course codes; update when the term changes.
  static const _courseNames = {
    'DSM 5001': 'Olasılık ve İstatistik',
    'DSM 5003': 'R',
    'DSM 5014': 'Derin Öğrenme',
  };

  Widget _startPage() {
    final store = widget.store;
    final theme = Theme.of(context);
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (store.questions.isEmpty)
          Text(
            'No questions yet. Add your GitHub token in settings to '
            'download them.',
            style: theme.textTheme.titleMedium,
          ),
        for (final course in store.courses)
          _courseRow(course, store.todaysSet(course, now)),
        ..._history(theme),
      ],
    );
  }

  /// One test per course — a round never mixes courses.
  Widget _courseRow(String course, List<Question> today) {
    final name = _courseNames[course];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name == null ? course : '$course · $name'),
      subtitle: Text(today.isEmpty
          ? 'All done for today'
          : 'Today: ${today.length} questions'),
      trailing: FilledButton(
        onPressed: today.isEmpty
            ? null
            : () => setState(() {
                  _session = today;
                  _index = 0;
                  _correct = 0;
                  _chosen = null;
                  _flagged = false;
                }),
        child: const Text('Start'),
      ),
    );
  }

  /// One row per day, newest first, with the score per course.
  List<Widget> _history(ThemeData theme) {
    final days = <DateTime, List<Attempt>>{};
    for (final attempt in widget.store.attempts.reversed) {
      days.putIfAbsent(DateUtils.dateOnly(attempt.at), () => []).add(attempt);
    }
    if (days.isEmpty) return const [];
    String score(Iterable<Attempt> list) =>
        '${list.where((a) => a.correct).length}/${list.length}';
    return [
      const Divider(height: 32),
      Text('History', style: theme.textTheme.titleSmall),
      for (final MapEntry(key: day, value: list) in days.entries)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${DateFormat('EEE, MMM d').format(day)} · ${score(list)}'),
          subtitle: Text([
            for (final course in {for (final a in list) a.course})
              '$course ${score(list.where((a) => a.course == course))}',
          ].join(' · ')),
        ),
    ];
  }

  Widget _questionPage(Question question, int total) {
    final theme = Theme.of(context);
    final chosen = _chosen;
    final right = chosen == question.answer;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_index + 1} / $total · ${question.course}',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Text(question.question, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        for (var i = 0; i < question.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionButton(
              label: 'ABCD'[i],
              text: question.options[i],
              result: chosen == null
                  ? null
                  : i == question.answer
                      ? true
                      : i == chosen
                          ? false
                          : null,
              onTap: chosen == null ? () => setState(() => _chosen = i) : null,
            ),
          ),
        if (chosen != null) ...[
          const SizedBox(height: 8),
          Text(
            right
                ? 'Correct!'
                : 'Wrong — the answer is ${'ABCD'[question.answer]}.',
            style: theme.textTheme.titleSmall?.copyWith(
                color: right ? Colors.green.shade800 : theme.colorScheme.error),
          ),
          const SizedBox(height: 4),
          Text(question.explanation),
          const SizedBox(height: 4),
          Text(
            question.source,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _flagged = !_flagged),
                icon: Icon(_flagged ? Icons.flag : Icons.outlined_flag),
                label: Text(_flagged ? 'Reported' : 'Report bad question'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _next(question),
                child: Text(_index + 1 == total ? 'Finish' : 'Next'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _summary(int total) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_correct / $total correct',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => _session = null),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// An answer option. Once answered, [result] paints it green (the right
/// answer) or red (a wrong pick), with an icon so color isn't the only cue.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.text,
    required this.result,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool? result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Shades dark enough for white text (4.5:1).
    final color = switch (result) {
      true => Colors.green.shade800,
      false => Colors.red.shade700,
      null => null,
    };
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(12),
        disabledBackgroundColor: color,
        disabledForegroundColor: color == null ? null : Colors.white,
      ),
      child: Row(
        children: [
          Text('$label.  ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
          if (result != null) Icon(result! ? Icons.check : Icons.close),
        ],
      ),
    );
  }
}
