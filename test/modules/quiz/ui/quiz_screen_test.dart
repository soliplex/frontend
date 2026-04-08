import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_screen.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/test_server_entry.dart';

void main() {
  late FakeSoliplexApi api;

  setUp(() {
    api = FakeSoliplexApi();
  });

  Widget buildScreen({String? returnRoute}) {
    final entry = createTestServerEntry(api: api);
    final router = GoRouter(
      initialLocation: '/room/test-server-8000/room-1/quiz/quiz-1',
      routes: [
        GoRoute(
          path: '/room/:alias/:roomId/quiz/:quizId',
          builder: (_, state) => QuizScreen(
            serverEntry: entry,
            roomId: 'room-1',
            quizId: 'quiz-1',
            returnRoute: returnRoute,
          ),
        ),
        GoRoute(
          path: '/room/:alias/:roomId',
          builder: (_, __) => const Scaffold(body: Text('Room screen')),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('shows loading then quiz title', (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Intro to ML',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q1', type: FreeForm()),
      ],
    );
    await tester.pumpWidget(buildScreen());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Intro to ML'), findsNWidgets(2));
    expect(find.text('Start Quiz'), findsOneWidget);
  });

  testWidgets('shows error with retry on fetch failure', (tester) async {
    api.nextQuizError = Exception('fetch failed');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows network error with retry', (tester) async {
    api.nextQuizError = const NetworkException(message: 'connection refused');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not reach the server. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows auth error with back to room', (tester) async {
    api.nextQuizError = const AuthException(message: 'session expired');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(
      find.text('Your session has expired. Please sign in again.'),
      findsOneWidget,
    );
    expect(find.text('Back to Room'), findsOneWidget);
  });

  testWidgets('shows Back to Room on 404', (tester) async {
    api.nextQuizError = const NotFoundException(message: 'quiz not found');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(find.text('This quiz is no longer available.'), findsOneWidget);
    expect(find.text('Back to Room'), findsOneWidget);
  });

  testWidgets('retry after fetch error loads quiz', (tester) async {
    api.nextQuizError = Exception('network blip');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    // Clear error and set quiz for retry
    api.nextQuizError = null;
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Recovered Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q1', type: FreeForm()),
      ],
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered Quiz'), findsNWidgets(2));
    expect(find.text('Start Quiz'), findsOneWidget);
  });

  testWidgets('full quiz flow: start, answer, complete', (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'What is 1+1?', type: FreeForm()),
      ],
    );
    api.nextQuizAnswerResult = const CorrectAnswer();
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Start the quiz
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('What is 1+1?'), findsOneWidget);
    expect(find.text('Question 1 of 1'), findsOneWidget);

    // Type an answer
    await tester.enterText(find.byType(TextField), '2');
    await tester.pumpAndSettle();

    // Submit
    await tester.tap(find.text('Submit Answer'));
    await tester.pumpAndSettle();

    // See result and proceed to results
    await tester.tap(find.text('See Results'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz Complete!'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('1 of 1 correct'), findsOneWidget);
  });

  testWidgets('multiple choice flow: select, submit, see result',
      (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'MC Quiz',
      questions: [
        QuizQuestion(
          id: 'q1',
          text: 'Pick the capital of France',
          type: MultipleChoice(['London', 'Paris', 'Berlin']),
        ),
      ],
    );
    api.nextQuizAnswerResult = const CorrectAnswer();
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Start the quiz
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Pick the capital of France'), findsOneWidget);

    // Select an option
    await tester.tap(find.text('Paris'));
    await tester.pumpAndSettle();

    // Submit
    await tester.tap(find.text('Submit Answer'));
    await tester.pumpAndSettle();

    // See result and proceed
    expect(find.text('Correct!'), findsOneWidget);
    await tester.tap(find.text('See Results'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz Complete!'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('submission error displays and clears on new input',
      (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q?', type: FreeForm()),
      ],
    );
    api.nextQuizAnswerError = Exception('server error');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Start quiz and submit
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'answer');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Answer'));
    await tester.pumpAndSettle();

    // Error should be visible
    expect(
      find.text('Could not submit your answer. Please try again.'),
      findsOneWidget,
    );

    // Typing new input should clear the error
    await tester.enterText(find.byType(TextField), 'new answer');
    await tester.pumpAndSettle();
    expect(
      find.text('Could not submit your answer. Please try again.'),
      findsNothing,
    );
  });

  testWidgets('returnRoute parameter navigates to custom route',
      (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q?', type: FreeForm()),
      ],
    );
    final entry = createTestServerEntry(api: api);
    final router = GoRouter(
      initialLocation: '/room/test-server-8000/room-1/quiz/quiz-1',
      routes: [
        GoRoute(
          path: '/room/:alias/:roomId/quiz/:quizId',
          builder: (_, state) => QuizScreen(
            serverEntry: entry,
            roomId: 'room-1',
            quizId: 'quiz-1',
            returnRoute: '/lobby',
          ),
        ),
        GoRoute(
          path: '/room/:alias/:roomId',
          builder: (_, __) => const Scaffold(body: Text('Room screen')),
        ),
        GoRoute(
          path: '/lobby',
          builder: (_, __) => const Scaffold(body: Text('Lobby screen')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // On start screen, back should navigate to returnRoute (/lobby)
    await tester.tap(find.byTooltip('Back to room'));
    await tester.pumpAndSettle();
    expect(find.text('Lobby screen'), findsOneWidget);
  });

  testWidgets('retake clears state and restarts quiz', (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q?', type: FreeForm()),
      ],
    );
    api.nextQuizAnswerResult = const CorrectAnswer();
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Complete the quiz
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See Results'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz Complete!'), findsOneWidget);

    // Retake
    await tester.tap(find.text('Retake Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Q?'), findsOneWidget);
    expect(find.text('Question 1 of 1'), findsOneWidget);
  });

  testWidgets('leave-quiz dialog: cancel stays on quiz', (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q?', type: FreeForm()),
        QuizQuestion(id: 'q2', text: 'Q2?', type: FreeForm()),
      ],
    );
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Start quiz to enter QuizInProgress
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();

    // Tap the back button
    await tester.tap(find.byTooltip('Back to room'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Quiz?'), findsOneWidget);
    expect(find.text('Your progress will be lost.'), findsOneWidget);

    // Cancel — should stay on quiz
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Q?'), findsOneWidget);
  });

  testWidgets('leave-quiz dialog: confirm navigates away', (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q?', type: FreeForm()),
        QuizQuestion(id: 'q2', text: 'Q2?', type: FreeForm()),
      ],
    );
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Start quiz to enter QuizInProgress
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();

    // Tap back and confirm
    await tester.tap(find.byTooltip('Back to room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Room screen'), findsOneWidget);
  });

  testWidgets('no dialog when leaving from QuizNotStarted', (tester) async {
    api.nextQuiz = Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q1', text: 'Q?', type: FreeForm()),
      ],
    );
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Still on start screen — back should navigate without dialog
    await tester.tap(find.byTooltip('Back to room'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Quiz?'), findsNothing);
    expect(find.text('Room screen'), findsOneWidget);
  });
}
