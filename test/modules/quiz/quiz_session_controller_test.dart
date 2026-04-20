import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';
import 'package:soliplex_frontend/src/modules/quiz/quiz_session_controller.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSoliplexApi api;
  late QuizSessionController controller;

  setUp(() {
    api = FakeSoliplexApi();
    controller = QuizSessionController(
      api: api,
      roomId: 'room-1',
      logger: testLogger(),
    );
  });

  tearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });

  test('initial state is QuizNotStarted', () {
    expect(controller.session.value, isA<QuizNotStarted>());
  });

  test('start transitions to QuizInProgress', () {
    controller.start(_quiz());
    final state = controller.session.value;
    expect(state, isA<QuizInProgress>());
    expect((state as QuizInProgress).currentIndex, 0);
  });

  test('start throws on empty quiz', () {
    expect(
      () =>
          controller.start(Quiz(id: 'q', title: 'Empty', questions: const [])),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('updateInput transitions to Composing', () {
    controller.start(_quiz());
    controller.updateInput(const TextInput('hello'));
    final state = controller.session.value as QuizInProgress;
    expect(state.questionState, isA<Composing>());
  });

  test('clearInput returns to AwaitingInput', () {
    controller.start(_quiz());
    controller.updateInput(const TextInput('hello'));
    controller.clearInput();
    final state = controller.session.value as QuizInProgress;
    expect(state.questionState, isA<AwaitingInput>());
  });

  test('submitAnswer transitions through Submitting to Answered', () async {
    api.nextQuizAnswerResult = const CorrectAnswer();
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    final state = controller.session.value as QuizInProgress;
    expect(state.questionState, isA<Answered>());
    expect((state.questionState as Answered).result.isCorrect, isTrue);
    expect(controller.submissionError.value, isNull);
  });

  test('submitAnswer sets error on failure and preserves input', () async {
    api.nextQuizAnswerError = Exception('network down');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    final state = controller.session.value as QuizInProgress;
    expect(state.questionState, isA<Composing>());
    expect(controller.submissionError.value, isNotNull);
  });

  test('updateInput clears submissionError', () async {
    api.nextQuizAnswerError = Exception('fail');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    expect(controller.submissionError.value, isNotNull);
    controller.updateInput(const TextInput('new'));
    expect(controller.submissionError.value, isNull);
  });

  test('nextQuestion advances index', () async {
    api.nextQuizAnswerResult = const CorrectAnswer();
    controller.start(_quiz());
    controller.updateInput(const TextInput('a'));
    await controller.submitAnswer();
    controller.nextQuestion();
    final state = controller.session.value as QuizInProgress;
    expect(state.currentIndex, 1);
    expect(state.questionState, isA<AwaitingInput>());
  });

  test('nextQuestion on last question transitions to QuizCompleted', () async {
    final quiz = Quiz(
      id: 'q',
      title: 'One Q',
      questions: const [QuizQuestion(id: 'q-1', text: 'Q1', type: FreeForm())],
    );
    api.nextQuizAnswerResult = const CorrectAnswer();
    controller.start(quiz);
    controller.updateInput(const TextInput('a'));
    await controller.submitAnswer();
    controller.nextQuestion();
    expect(controller.session.value, isA<QuizCompleted>());
  });

  test('retake restarts from beginning', () async {
    api.nextQuizAnswerResult = const CorrectAnswer();
    controller.start(_quiz());
    controller.updateInput(const TextInput('a'));
    await controller.submitAnswer();
    controller.retake();
    final state = controller.session.value as QuizInProgress;
    expect(state.currentIndex, 0);
    expect(state.results, isEmpty);
  });

  test('reset returns to QuizNotStarted', () {
    controller.start(_quiz());
    controller.reset();
    expect(controller.session.value, isA<QuizNotStarted>());
  });

  test('reset clears submissionError', () async {
    api.nextQuizAnswerError = Exception('fail');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    expect(controller.submissionError.value, isNotNull);
    controller.reset();
    expect(controller.submissionError.value, isNull);
  });

  group('guard clauses', () {
    test('updateInput ignored when Submitting', () async {
      api.submitQuizAnswerCompleter = Completer<QuizAnswerResult>();
      controller.start(_quiz());
      controller.updateInput(const TextInput('original'));
      // Start submit — transitions to Submitting
      final future = controller.submitAnswer();
      controller.updateInput(const TextInput('changed'));
      final state = controller.session.value as QuizInProgress;
      // Should still be Submitting with original input
      expect(state.questionState, isA<Submitting>());
      expect((state.questionState as Submitting).input.answerText, 'original');
      // Complete the future to avoid dangling
      api.submitQuizAnswerCompleter!.complete(const CorrectAnswer());
      await future;
    });

    test('updateInput ignored when Answered', () async {
      api.nextQuizAnswerResult = const CorrectAnswer();
      controller.start(_quiz());
      controller.updateInput(const TextInput('answer'));
      await controller.submitAnswer();
      controller.updateInput(const TextInput('new'));
      final state = controller.session.value as QuizInProgress;
      expect(state.questionState, isA<Answered>());
    });

    test('submitAnswer no-op when AwaitingInput', () async {
      controller.start(_quiz());
      await controller.submitAnswer();
      final state = controller.session.value as QuizInProgress;
      expect(state.questionState, isA<AwaitingInput>());
    });

    test(
      'submitAnswer no-op when Composing with whitespace-only input',
      () async {
        controller.start(_quiz());
        controller.updateInput(const TextInput('   '));
        await controller.submitAnswer();
        final state = controller.session.value as QuizInProgress;
        expect(state.questionState, isA<Composing>());
        expect(api.submitQuizAnswerCallCount, 0);
      },
    );

    test('submitAnswer no-op when QuizNotStarted', () async {
      await controller.submitAnswer();
      expect(controller.session.value, isA<QuizNotStarted>());
    });

    test('nextQuestion no-op when Composing', () {
      controller.start(_quiz());
      controller.updateInput(const TextInput('hello'));
      controller.nextQuestion();
      final state = controller.session.value as QuizInProgress;
      expect(state.currentIndex, 0);
      expect(state.questionState, isA<Composing>());
    });

    test('clearInput no-op when AwaitingInput', () {
      controller.start(_quiz());
      controller.clearInput();
      final state = controller.session.value as QuizInProgress;
      expect(state.questionState, isA<AwaitingInput>());
    });

    test('retake no-op when QuizNotStarted', () {
      controller.retake();
      expect(controller.session.value, isA<QuizNotStarted>());
    });

    test('updateInput rejects TextInput for MultipleChoice question', () {
      controller.start(
        Quiz(
          id: 'q',
          title: 'MC Quiz',
          questions: [
            QuizQuestion(
              id: 'q-1',
              text: 'Pick one',
              type: MultipleChoice(['A', 'B', 'C']),
            ),
          ],
        ),
      );
      controller.updateInput(const TextInput('typed text'));
      final state = controller.session.value as QuizInProgress;
      expect(state.questionState, isA<AwaitingInput>());
    });

    test('updateInput rejects MultipleChoiceInput for FreeForm question', () {
      controller.start(_quiz());
      controller.updateInput(const MultipleChoiceInput('A'));
      final state = controller.session.value as QuizInProgress;
      expect(state.questionState, isA<AwaitingInput>());
    });
  });

  test('dispose during in-flight submit does not throw', () async {
    final completer = Completer<QuizAnswerResult>();
    api.submitQuizAnswerCompleter = completer;
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    final future = controller.submitAnswer();
    controller.dispose();
    completer.complete(const CorrectAnswer());
    // Should complete without error
    await future;
  });

  test('submission error uses user-friendly message', () async {
    api.nextQuizAnswerError = Exception('raw error text');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    expect(
      controller.submissionError.value,
      'Could not submit your answer. Please try again.',
    );
  });

  test('NotFoundException shows specific error message', () async {
    api.nextQuizAnswerError = const NotFoundException(message: 'question gone');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    expect(
      controller.submissionError.value,
      'This question is no longer available.',
    );
  });

  test('NetworkException shows specific error message', () async {
    api.nextQuizAnswerError = const NetworkException(
      message: 'connection refused',
    );
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    expect(
      controller.submissionError.value,
      'Could not reach the server. Check your connection and try again.',
    );
  });

  test('AuthException shows session-expired message', () async {
    api.nextQuizAnswerError = const AuthException(message: 'session expired');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    expect(
      controller.submissionError.value,
      'Your session has expired. Please sign in again.',
    );
  });

  test('non-Exception error preserves input and sets error message', () async {
    api.nextQuizAnswerThrowable = StateError('unexpected');
    controller.start(_quiz());
    controller.updateInput(const TextInput('answer'));
    await controller.submitAnswer();
    final state = controller.session.value as QuizInProgress;
    expect(state.questionState, isA<Composing>());
    expect((state.questionState as Composing).input.answerText, 'answer');
    expect(
      controller.submissionError.value,
      'An unexpected error occurred. Please try again.',
    );
  });

  test('retake from QuizCompleted restarts quiz', () async {
    final quiz = Quiz(
      id: 'q',
      title: 'One Q',
      questions: const [QuizQuestion(id: 'q-1', text: 'Q1', type: FreeForm())],
    );
    api.nextQuizAnswerResult = const CorrectAnswer();
    controller.start(quiz);
    controller.updateInput(const TextInput('a'));
    await controller.submitAnswer();
    controller.nextQuestion();
    expect(controller.session.value, isA<QuizCompleted>());

    controller.retake();
    final state = controller.session.value as QuizInProgress;
    expect(state.currentIndex, 0);
    expect(state.results, isEmpty);
    expect(state.questionState, isA<AwaitingInput>());
  });
}

Quiz _quiz() => Quiz(
  id: 'quiz-1',
  title: 'Test',
  questions: const [
    QuizQuestion(id: 'q-1', text: 'Q1', type: FreeForm()),
    QuizQuestion(id: 'q-2', text: 'Q2', type: FreeForm()),
  ],
);
