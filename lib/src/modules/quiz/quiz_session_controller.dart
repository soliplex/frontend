import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_client/soliplex_client.dart';

import 'quiz_session.dart';

class QuizSessionController {
  QuizSessionController({
    required SoliplexApi api,
    required String roomId,
    required Logger logger,
  }) : _api = api,
       _roomId = roomId,
       _logger = logger;

  final SoliplexApi _api;
  final String _roomId;
  final Logger _logger;

  final Signal<QuizSession> _session = Signal<QuizSession>(
    const QuizNotStarted(),
  );
  ReadonlySignal<QuizSession> get session => _session;

  final Signal<String?> _submissionError = Signal<String?>(null);
  ReadonlySignal<String?> get submissionError => _submissionError;

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  void start(Quiz quiz) {
    _session.value = QuizInProgress(
      quiz: quiz,
      currentIndex: 0,
      results: const {},
      questionState: const AwaitingInput(),
    );
  }

  void updateInput(QuizInput input) {
    final current = _session.value;
    if (current is! QuizInProgress) return;
    if (current.questionState is Submitting ||
        current.questionState is Answered) {
      return;
    }
    final questionType = current.currentQuestion.type;
    final validInput = switch ((questionType, input)) {
      (MultipleChoice(), MultipleChoiceInput()) => true,
      (FillBlank() || FreeForm(), TextInput()) => true,
      _ => false,
    };
    if (!validInput) {
      _logger.warning(
        'Input type ${input.runtimeType} does not match '
        'question type ${questionType.runtimeType}',
      );
      return;
    }
    _submissionError.value = null;
    _session.value = current.copyWith(questionState: Composing(input));
  }

  void clearInput() {
    final current = _session.value;
    if (current is! QuizInProgress) return;
    if (current.questionState is! Composing) return;
    _session.value = current.copyWith(questionState: const AwaitingInput());
  }

  Future<void> submitAnswer() async {
    final current = _session.value;
    if (current is! QuizInProgress) return;
    final questionState = current.questionState;
    if (questionState is! Composing || !questionState.canSubmit) return;

    final input = questionState.input;
    _session.value = current.copyWith(questionState: Submitting(input));

    try {
      final result = await _api.submitQuizAnswer(
        _roomId,
        current.quiz.id,
        current.currentQuestion.id,
        input.answerText,
      );
      if (_isDisposed) return;

      final afterState = _session.value;
      if (afterState is! QuizInProgress) return;

      final newResults = {
        ...afterState.results,
        afterState.currentQuestion.id: result,
      };
      _session.value = afterState.copyWith(
        results: newResults,
        questionState: Answered(input, result),
      );
    } on Exception catch (e, stackTrace) {
      _logger.error(
        'Failed to submit answer for question '
        '${current.currentQuestion.id} in quiz ${current.quiz.id}',
        error: e,
        stackTrace: stackTrace,
      );
      _recoverFromSubmitError(input, switch (e) {
        AuthException() => 'Your session has expired. Please sign in again.',
        NotFoundException() => 'This question is no longer available.',
        NetworkException() =>
          'Could not reach the server. Check your connection and try again.',
        _ => 'Could not submit your answer. Please try again.',
      });
    } catch (e, stackTrace) {
      _logger.error(
        'Unexpected error submitting answer for question '
        '${current.currentQuestion.id} in quiz ${current.quiz.id}',
        error: e,
        stackTrace: stackTrace,
      );
      _recoverFromSubmitError(
        input,
        'An unexpected error occurred. Please try again.',
      );
    }
  }

  void _recoverFromSubmitError(QuizInput input, String message) {
    if (_isDisposed) return;
    final afterState = _session.value;
    if (afterState is! QuizInProgress) return;
    _session.value = afterState.copyWith(questionState: Composing(input));
    _submissionError.value = message;
  }

  void nextQuestion() {
    final current = _session.value;
    if (current is! QuizInProgress) return;
    if (current.questionState is! Answered) return;

    if (current.isLastQuestion) {
      _session.value = QuizCompleted(
        quiz: current.quiz,
        results: current.results,
      );
    } else {
      _session.value = current.copyWith(
        currentIndex: current.currentIndex + 1,
        questionState: const AwaitingInput(),
      );
    }
  }

  void reset() {
    _session.value = const QuizNotStarted();
    _submissionError.value = null;
  }

  void retake() {
    final current = _session.value;
    final quiz = switch (current) {
      QuizInProgress(:final quiz) => quiz,
      QuizCompleted(:final quiz) => quiz,
      QuizNotStarted() => null,
    };
    if (quiz == null) return;
    _session.value = QuizInProgress(
      quiz: quiz,
      currentIndex: 0,
      results: const {},
      questionState: const AwaitingInput(),
    );
    _submissionError.value = null;
  }

  void dispose() {
    _isDisposed = true;
    _session.dispose();
    _submissionError.dispose();
  }
}
