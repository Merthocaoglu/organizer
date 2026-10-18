import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../models/workout_notes.dart';
import '../services/event_store.dart';

/// Reminder choices in minutes before start; null = no reminder.
const _reminderOptions = <(int?, String)>[
  (null, 'Off'),
  (0, 'At start'),
  (5, '5 min'),
  (10, '10 min'),
  (30, '30 min'),
  (60, '1 hour'),
];

/// Bottom-sheet form to create an event on [date] (the day currently
/// selected in the calendar) or, when [existing] is given, edit it in place.
Future<void> showEventSheet(
  BuildContext context, {
  required EventStore store,
  required DateTime date,
  Event? existing,
  void Function(DateTime date)? onSaved,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _EventForm(
          store: store, date: date, existing: existing, onSaved: onSaved),
    ),
  );
}

class _EventForm extends StatefulWidget {
  const _EventForm(
      {required this.store, required this.date, this.existing, this.onSaved});

  final EventStore store;
  final DateTime date;
  final Event? existing;
  final void Function(DateTime date)? onSaved;

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _ExerciseEntry {
  final weight = TextEditingController();
  final sets = TextEditingController();
  final reps = TextEditingController();

  void dispose() {
    weight.dispose();
    sets.dispose();
    reps.dispose();
  }
}

class _EventFormState extends State<_EventForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  final _notesController = TextEditingController();
  late TimeOfDay _start =
      widget.existing?.start ?? const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay _end =
      widget.existing?.end ?? const TimeOfDay(hour: 10, minute: 0);
  late EventCategory _category =
      widget.existing?.category ?? EventCategory.other;
  late bool _repeatsWeekly = widget.existing?.repeatsWeekly ?? false;
  // New events default to a 10-minute reminder; edits keep what was saved.
  late int? _reminderMinutes =
      widget.existing == null ? 10 : widget.existing!.reminderMinutes;

  // Gym workout state: selected day type + exercise → weight/reps fields.
  String? _workoutType;
  final Map<String, _ExerciseEntry> _entries = {};

  List<String> get _allExercises =>
      [...builtInExercises, ...widget.store.customExercises];

  @override
  void initState() {
    super.initState();
    // Only Gym notes hold workout lines; parsing others would drop them.
    if (widget.existing?.category == EventCategory.gym) {
      _parseNotes(widget.existing?.notes);
    } else {
      _notesController.text = widget.existing?.notes ?? '';
    }
  }

  /// Fills the form state from a notes blob written by [_composeNotes]
  /// (format documented in models/workout_notes.dart).
  void _parseNotes(String? notes) {
    final parsed = parseWorkoutNotes(notes, _allExercises);
    _workoutType = parsed.workoutType;
    for (final line in parsed.exercises) {
      final entry = _ExerciseEntry();
      entry.weight.text = line.weight;
      entry.sets.text = line.sets;
      entry.reps.text = line.reps;
      _entries[line.name] = entry;
    }
    _notesController.text = parsed.freeText.join('\n');
  }

  String? _composeNotes() {
    final lines = <String>[];
    if (_category == EventCategory.gym) {
      if (_workoutType != null) lines.add(_workoutType!);
      for (final exercise in _allExercises) {
        final entry = _entries[exercise];
        if (entry == null) continue;
        final weight = entry.weight.text.trim();
        final sets = entry.sets.text.trim();
        final reps = entry.reps.text.trim();
        lines.add([
          exercise,
          if (weight.isNotEmpty) '${weight}kg',
          if (sets.isNotEmpty || reps.isNotEmpty) '${sets}x$reps',
        ].join(' '));
      }
    }
    final free = _notesController.text.trim();
    if (free.isNotEmpty) lines.add(free);
    return lines.isEmpty ? null : lines.join('\n');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    for (final entry in _entries.values) {
      entry.dispose();
    }
    super.dispose();
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked == null) return;
    setState(() {
      // Keep the event length when the start moves; the mod keeps
      // overnight lengths (end < start) positive and lets a moved end
      // wrap past midnight.
      final duration =
          (_minutes(_end) - _minutes(_start)) % (24 * 60);
      _start = picked;
      final endMinutes = (_minutes(picked) + duration) % (24 * 60);
      _end = TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked == null) return;
    setState(() => _end = picked);
  }

  void _toggleExercise(String exercise, bool selected) {
    setState(() {
      if (selected) {
        _entries[exercise] = _ExerciseEntry();
      } else {
        _entries.remove(exercise)?.dispose();
      }
    });
  }

  Future<void> _addCustomExercise() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New exercise'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Face pulls'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await widget.store.addCustomExercise(trimmed);
    setState(() => _entries.putIfAbsent(trimmed, _ExerciseEntry.new));
  }

  void _removeCustomExercise(String exercise) {
    widget.store.removeCustomExercise(exercise);
    setState(() => _entries.remove(exercise)?.dispose());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // end < start means the event runs into the next day (overnight);
    // only a zero-length event is invalid.
    if (_minutes(_end) == _minutes(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Start and end can\'t be the same time')),
      );
      return;
    }
    final existing = widget.existing;
    if (existing != null) {
      await widget.store.update(
        existing.id,
        date: existing.date,
        start: _start,
        end: _end,
        title: _titleController.text.trim(),
        category: _category,
        notes: _composeNotes(),
        repeatsWeekly: _repeatsWeekly,
        reminderMinutes: _reminderMinutes,
      );
    } else {
      await widget.store.add(
        date: widget.date,
        start: _start,
        end: _end,
        title: _titleController.text.trim(),
        category: _category,
        notes: _composeNotes(),
        repeatsWeekly: _repeatsWeekly,
        reminderMinutes: _reminderMinutes,
      );
    }
    if (mounted) Navigator.of(context).pop();
    widget.onSaved?.call(existing?.date ?? widget.date);
  }

  @override
  Widget build(BuildContext context) {
    final isGym = _category == EventCategory.gym;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.existing == null ? 'New event' : 'Edit event'} · '
              '${DateFormat('EEE, MMM d').format(widget.existing?.date ?? widget.date)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter a title'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.access_time),
                    label: Text(_start.format(context)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('to'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.access_time_filled),
                    label: Text(_end.format(context)),
                  ),
                ),
              ],
            ),
            if (_minutes(_end) < _minutes(_start))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Ends the next day',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _repeatsWeekly,
              onChanged: (value) => setState(() => _repeatsWeekly = value),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Repeat every ${DateFormat('EEEE').format(widget.existing?.date ?? widget.date)}',
              ),
              subtitle: _repeatsWeekly
                  ? const Text('Editing or deleting affects every week')
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.notifications_outlined,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('Reminder',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (minutes, label) in _reminderOptions)
                  ChoiceChip(
                    label: Text(label),
                    selected: _reminderMinutes == minutes,
                    onSelected: (_) =>
                        setState(() => _reminderMinutes = minutes),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final category in EventCategory.values)
                  ChoiceChip(
                    avatar: CircleAvatar(
                        backgroundColor: category.color, radius: 6),
                    label: Text(category.label),
                    selected: _category == category,
                    selectedColor: category.color.withValues(alpha: 0.18),
                    onSelected: (_) =>
                        setState(() => _category = category),
                  ),
              ],
            ),
            if (isGym) ...[
              const SizedBox(height: 16),
              Text('Workout',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final type in workoutTypes)
                    ChoiceChip(
                      label: Text(type),
                      selected: _workoutType == type,
                      onSelected: (selected) => setState(
                          () => _workoutType = selected ? type : null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Exercises',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final exercise in builtInExercises)
                    FilterChip(
                      label: Text(exercise),
                      selected: _entries.containsKey(exercise),
                      onSelected: (selected) =>
                          _toggleExercise(exercise, selected),
                    ),
                  for (final exercise in widget.store.customExercises)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        FilterChip(
                          label: Text(exercise),
                          selected: _entries.containsKey(exercise),
                          onSelected: (selected) =>
                              _toggleExercise(exercise, selected),
                        ),
                        Positioned(
                          top: -4,
                          right: -4,
                          child: GestureDetector(
                            onTap: () => _removeCustomExercise(exercise),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color:
                                    Theme.of(context).colorScheme.onError,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add exercise'),
                    onPressed: _addCustomExercise,
                  ),
                ],
              ),
              if (_entries.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final exercise in _allExercises)
                  if (_entries.containsKey(exercise))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(exercise)),
                          SizedBox(
                            width: 60,
                            child: TextFormField(
                              controller: _entries[exercise]!.sets,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Sets',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: TextFormField(
                              controller: _entries[exercise]!.reps,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Reps',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 96,
                            child: TextFormField(
                              controller: _entries[exercise]!.weight,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Weight',
                                suffixText: 'kg',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              minLines: isGym ? 1 : 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText:
                    isGym ? 'Extra notes (optional)' : 'Notes (optional)',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(
                  widget.existing == null ? 'Add event' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
