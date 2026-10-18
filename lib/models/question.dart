/// One multiple-choice question from `data/questions/<course>.json`,
/// written by Claude from the course slides.
class Question {
  const Question({
    required this.id,
    required this.course,
    required this.source,
    required this.question,
    required this.options,
    required this.answer,
    required this.explanation,
  });

  final String id;
  final String course; // e.g. "DSM 5001"
  final String source; // slide reference, e.g. "Hafta 3, slayt 12"
  final String question;
  final List<String> options; // exactly four, shown as A–D
  final int answer; // index into [options]
  final String explanation;

  /// Throws on malformed input, so a broken entry can be skipped instead
  /// of breaking the quiz.
  factory Question.fromJson(Map<String, dynamic> json) {
    final options = List<String>.from(json['options'] as List);
    final answer = json['answer'] as int;
    if (options.length != 4 || answer < 0 || answer > 3) {
      throw FormatException(
          'Question ${json['id']}: needs 4 options and answer 0-3');
    }
    return Question(
      id: json['id'] as String,
      course: json['course'] as String,
      source: json['source'] as String,
      question: json['question'] as String,
      options: options,
      answer: answer,
      explanation: json['explanation'] as String,
    );
  }
}

/// One answered question — kept on the phone and uploaded to
/// `data/results/` so Claude can see weak topics and flagged questions.
class Attempt {
  Attempt({
    required this.at,
    required this.id,
    required this.course,
    required this.chosen,
    required this.correct,
    this.flagged = false,
  });

  final DateTime at;
  final String id;
  final String course;
  final int chosen;
  final bool correct;
  final bool flagged; // "bad question" report

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'id': id,
        'course': course,
        'chosen': chosen,
        'correct': correct,
        if (flagged) 'flagged': true,
      };

  factory Attempt.fromJson(Map<String, dynamic> json) => Attempt(
        at: DateTime.parse(json['at'] as String),
        id: json['id'] as String,
        course: json['course'] as String,
        chosen: json['chosen'] as int,
        correct: json['correct'] as bool,
        flagged: json['flagged'] == true,
      );
}
