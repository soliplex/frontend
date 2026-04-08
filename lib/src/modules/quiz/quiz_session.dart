import 'package:flutter/foundation.dart' show immutable, mapEquals;
import 'package:soliplex_client/soliplex_client.dart';

// ============================================================
// QuizInput - answer input types
// ============================================================

sealed class QuizInput {
  const QuizInput();

  /// The answer text to submit to the API.
  String get answerText;

  /// Whether this input is valid for submission.
  bool get isValid;
}

/// Multiple choice selection.
@immutable
class MultipleChoiceInput extends QuizInput {
  const MultipleChoiceInput(this.selectedOption);

  /// The selected option text.
  final String selectedOption;

  @override
  String get answerText => selectedOption;

  @override
  bool get isValid => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultipleChoiceInput && selectedOption == other.selectedOption;

  @override
  int get hashCode => selectedOption.hashCode;

  @override
  String toString() => 'MultipleChoiceInput($selectedOption)';
}

/// Free-form or fill-in-the-blank text input.
@immutable
class TextInput extends QuizInput {
  const TextInput(this.text);

  /// The entered text.
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

// ============================================================
// QuestionState - submission state machine (null-free)
// ============================================================

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

/// User hasn't entered any input yet.
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

/// User is composing an answer.
@immutable
class Composing extends QuestionState {
  const Composing(this.input);

  /// The current input.
  final QuizInput input;

  /// Whether the input is valid for submission.
  bool get canSubmit => input.isValid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Composing && input == other.input;

  @override
  int get hashCode => input.hashCode;

  @override
  String toString() => 'Composing($input)';
}

/// Answer is being submitted to the server.
@immutable
class Submitting extends QuestionState {
  const Submitting(this.input);

  /// The input being submitted.
  final QuizInput input;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Submitting && input == other.input;

  @override
  int get hashCode => input.hashCode;

  @override
  String toString() => 'Submitting($input)';
}

/// Server has responded with the result.
@immutable
class Answered extends QuestionState {
  const Answered(this.input, this.result);

  /// The submitted input.
  final QuizInput input;

  /// The result from the server.
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

// ============================================================
// QuizSession - sealed state for quiz progression
// ============================================================

/// Sealed class representing the quiz session state.
///
/// Use pattern matching for exhaustive handling:
/// ```dart
/// switch (session) {
///   case QuizNotStarted():
///     // Show quiz intro or selection
///   case QuizInProgress(:final currentIndex, :final questionState):
///     // Show current question based on questionState
///   case QuizCompleted(:final results):
///     // Show results summary
/// }
/// ```
@immutable
sealed class QuizSession {
  const QuizSession();
}

/// No quiz is currently in progress.
///
/// This is the initial state before the user starts a quiz.
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

/// A quiz is currently in progress.
///
/// Invariants:
/// - [quiz] must have at least one question
/// - [currentIndex] must be >= 0 and < quiz.questionCount
///
/// These invariants are enforced by the quiz session controller which is the
/// only production entry point. Direct construction is allowed for testing
/// but callers must ensure validity.
@immutable
class QuizInProgress extends QuizSession {
  /// Creates a quiz in progress state.
  ///
  /// The [results] map is made unmodifiable to preserve immutability.
  QuizInProgress({
    required this.quiz,
    required this.currentIndex,
    required Map<String, QuizAnswerResult> results,
    required this.questionState,
  })  : assert(currentIndex >= 0, 'currentIndex must be non-negative'),
        results = Map.unmodifiable(results);

  /// The quiz being taken.
  final Quiz quiz;

  /// Index of the current question (0-based).
  final int currentIndex;

  /// Results for answered questions, keyed by question ID (unmodifiable).
  final Map<String, QuizAnswerResult> results;

  /// Current question's answer state machine.
  final QuestionState questionState;

  /// The current question.
  QuizQuestion get currentQuestion => quiz.questions[currentIndex];

  /// Whether we're on the last question.
  bool get isLastQuestion => currentIndex >= quiz.questionCount - 1;

  /// Number of questions answered so far.
  int get answeredCount => results.length;

  /// Progress as a fraction (0.0 to 1.0).
  double get progress =>
      quiz.questionCount > 0 ? answeredCount / quiz.questionCount : 0.0;

  /// Creates a copy with the given fields replaced.
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
        Object.hashAll(results.entries),
        questionState,
      );

  @override
  String toString() =>
      'QuizInProgress(quiz: ${quiz.id}, question: ${currentIndex + 1}/'
      '${quiz.questionCount}, state: $questionState)';
}

/// Quiz has been completed.
@immutable
class QuizCompleted extends QuizSession {
  /// Creates a completed quiz state.
  ///
  /// The [results] map is made unmodifiable to preserve immutability.
  QuizCompleted({
    required this.quiz,
    required Map<String, QuizAnswerResult> results,
  }) : results = Map.unmodifiable(results);

  /// The completed quiz.
  final Quiz quiz;

  /// Results for all answered questions, keyed by question ID (unmodifiable).
  final Map<String, QuizAnswerResult> results;

  /// Number of correct answers.
  int get correctCount => results.values.where((r) => r.isCorrect).length;

  /// Total number of questions answered.
  int get totalAnswered => results.length;

  /// Score as a percentage (0-100).
  int get scorePercent =>
      totalAnswered > 0 ? (correctCount * 100 ~/ totalAnswered) : 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizCompleted &&
          quiz == other.quiz &&
          mapEquals(results, other.results);

  @override
  int get hashCode => Object.hash(quiz, Object.hashAll(results.entries));

  @override
  String toString() =>
      'QuizCompleted(quiz: ${quiz.id}, score: $correctCount/$totalAnswered)';
}
