/// The deterministic gym-notes text format, shared by the event form
/// (which writes/edits it) and the week analysis (which reads it).
///
/// Format inside [Event.notes]:
///   line 1 (optional): a workout type ("Push day")
///   following lines (optional): an exercise name plus optional "60kg"
///     and an optional sets×reps token — "3x12", "x12" (reps only, the
///     pre-sets format) or "3x" (sets only) — one exercise per line
///   anything unrecognized: free text
library;

const workoutTypes = [
  'Push day',
  'Pull day',
  'Leg day',
  'Full body',
  'Cardio',
];

const builtInExercises = [
  'Bench press',
  'Push-ups',
  'Shoulder press',
  'Dips',
  'Pull-ups',
  'Rows',
  'Lat pulldown',
  'Deadlift',
  'Squats',
  'Lunges',
  'Leg press',
  'Biceps curl',
  'Triceps extension',
  'Plank',
  'Treadmill',
  'Cycling',
];

/// One parsed exercise line; the numeric parts stay raw strings ('' when
/// absent) so form text fields can round-trip them unchanged.
class ExerciseLine {
  const ExerciseLine({
    required this.name,
    this.weight = '',
    this.sets = '',
    this.reps = '',
  });

  final String name;
  final String weight;
  final String sets;
  final String reps;
}

class ParsedWorkout {
  String? workoutType;
  final exercises = <ExerciseLine>[];
  final freeText = <String>[];
}

final _linePattern =
    RegExp(r'^(.*?)(?:\s+(\d+(?:[.,]\d+)?)\s*kg)?(?:\s+(\d*)\s*x\s*(\d*))?$');

/// Splits [notes] into workout type, exercise lines (names matched
/// against [knownExercises]) and free text. Unknown lines never fail —
/// they land in [ParsedWorkout.freeText].
ParsedWorkout parseWorkoutNotes(String? notes, List<String> knownExercises) {
  final result = ParsedWorkout();
  if (notes == null) return result;
  for (final line in notes.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (result.workoutType == null && workoutTypes.contains(trimmed)) {
      result.workoutType = trimmed;
      continue;
    }
    final match = _linePattern.firstMatch(trimmed);
    final name = match?.group(1)?.trim() ?? '';
    if (match != null && knownExercises.contains(name)) {
      result.exercises.add(ExerciseLine(
        name: name,
        weight: match.group(2) ?? '',
        sets: match.group(3) ?? '',
        reps: match.group(4) ?? '',
      ));
    } else {
      result.freeText.add(trimmed);
    }
  }
  return result;
}
