import 'package:flutter/foundation.dart' show immutable, mapEquals;
import 'package:soliplex_client/soliplex_client.dart';

sealed class QuizInput {
  const QuizInput();

  String get answerText;

  bool get isValid;
}

@immutable
class MultipleChoiceInput extends QuizInput {
  const MultipleChoiceInput(this.selectedOption);

  final String selectedOption;

  @override
  String get answerText => selectedOption;

  @override
  bool get isValid => selectedOption.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultipleChoiceInput && selectedOption == other.selectedOption;

  @override
  int get hashCode => selectedOption.hashCode;

  @override
  String toString() => 'MultipleChoiceInput($selectedOption)';
}

@immutable
class TextInput extends QuizInput {
  const TextInput(this.text);

  final String text;

  @override
  String get answerText => text.trim();

  @override
  bool get isValid => text.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextInput && text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextInput($text)';
}

/// State machine for the current question's answer submission.
///
/// Transitions:
/// ```text
/// AwaitingInput ──(input)──► Composing ◄──(clear)───┐
///                                │                   │
///                                └───────────────────┘
///                                │ (submit)
///                                ▼
///                           Submitting
///                             │    │
///                  (success)  │    │ (error)
///                             ▼    ▼
///                        Answered  Composing (preserved input)
///                             │
///                      (next question)
///                             ▼
///                       AwaitingInput
/// ```
@immutable
sealed class QuestionState {
  const QuestionState();
}

@immutable
class AwaitingInput extends QuestionState {
  const AwaitingInput();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AwaitingInput;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AwaitingInput()';
}

@immutable
class Composing extends QuestionState {
  const Composing(this.input);

  final QuizInput input;

  bool get canSubmit => input.isValid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Composing && input == other.input;

  @override
  int get hashCode => input.hashCode;

  @override
  String toString() => 'Composing($input)';
}

@immutable
class Submitting extends QuestionState {
  const Submitting(this.input);

  final QuizInput input;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Submitting && input == other.input;

  @override
  int get hashCode => input.hashCode;

  @override
  String toString() => 'Submitting($input)';
}

@immutable
class Answered extends QuestionState {
  const Answered(this.input, this.result);

  final QuizInput input;

  final QuizAnswerResult result;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Answered && input == other.input && result == other.result;

  @override
  int get hashCode => Object.hash(input, result);

  @override
  String toString() => 'Answered($input, correct: ${result.isCorrect})';
}

@immutable
sealed class QuizSession {
  const QuizSession();
}

@immutable
class QuizNotStarted extends QuizSession {
  const QuizNotStarted();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QuizNotStarted;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'QuizNotStarted()';
}

/// Invariants:
/// - [quiz] must have at least one question
/// - [currentIndex] must be >= 0 and < quiz.questionCount
@immutable
class QuizInProgress extends QuizSession {
  /// The [results] map is made unmodifiable to preserve immutability.
  QuizInProgress({
    required this.quiz,
    required this.currentIndex,
    required Map<String, QuizAnswerResult> results,
    required this.questionState,
  }) : results = Map.unmodifiable(results) {
    if (!quiz.hasQuestions) {
      throw ArgumentError.value(
          quiz, 'quiz', 'Quiz must have at least one question');
    }
    if (currentIndex < 0 || currentIndex >= quiz.questionCount) {
      throw RangeError.range(
          currentIndex, 0, quiz.questionCount - 1, 'currentIndex');
    }
  }

  final Quiz quiz;

  final int currentIndex;

  /// Keyed by question ID.
  final Map<String, QuizAnswerResult> results;

  final QuestionState questionState;

  QuizQuestion get currentQuestion => quiz.questions[currentIndex];

  bool get isLastQuestion => currentIndex >= quiz.questionCount - 1;

  int get answeredCount => results.length;

  /// Fraction from 0.0 to 1.0.
  double get progress => answeredCount / quiz.questionCount;
  QuizInProgress copyWith({
    int? currentIndex,
    Map<String, QuizAnswerResult>? results,
    QuestionState? questionState,
  }) =>
      QuizInProgress(
        quiz: quiz,
        currentIndex: currentIndex ?? this.currentIndex,
        results: results ?? this.results,
        questionState: questionState ?? this.questionState,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizInProgress &&
          quiz == other.quiz &&
          currentIndex == other.currentIndex &&
          mapEquals(results, other.results) &&
          questionState == other.questionState;

  @override
  int get hashCode => Object.hash(
        quiz,
        currentIndex,
        Object.hashAll(results.keys),
        Object.hashAll(results.values),
        questionState,
      );

  @override
  String toString() =>
      'QuizInProgress(quiz: ${quiz.id}, question: ${currentIndex + 1}/'
      '${quiz.questionCount}, state: $questionState)';
}

@immutable
class QuizCompleted extends QuizSession {
  /// The [results] map is made unmodifiable to preserve immutability.
  QuizCompleted({
    required this.quiz,
    required Map<String, QuizAnswerResult> results,
  }) : results = Map.unmodifiable(results) {
    if (results.isEmpty) {
      throw ArgumentError.value(
          results, 'results', 'Completed quiz must have at least one result');
    }
  }

  final Quiz quiz;

  /// Keyed by question ID.
  final Map<String, QuizAnswerResult> results;

  int get correctCount => results.values.where((r) => r.isCorrect).length;

  int get totalAnswered => results.length;

  /// Percentage from 0 to 100.
  int get scorePercent =>
      totalAnswered > 0 ? (correctCount * 100 ~/ totalAnswered) : 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizCompleted &&
          quiz == other.quiz &&
          mapEquals(results, other.results);

  @override
  int get hashCode => Object.hash(
        quiz,
        Object.hashAll(results.keys),
        Object.hashAll(results.values),
      );

  @override
  String toString() =>
      'QuizCompleted(quiz: ${quiz.id}, score: $correctCount/$totalAnswered)';
}
