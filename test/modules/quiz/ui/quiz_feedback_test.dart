import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_feedback.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows Correct! for correct answer', (tester) async {
    await tester.pumpWidget(
      wrap(const QuizAnswerFeedback(result: CorrectAnswer())),
    );
    expect(find.text('Correct!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows expected answer for incorrect', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QuizAnswerFeedback(
          result: IncorrectAnswer(expectedAnswer: 'Paris'),
        ),
      ),
    );
    expect(find.text('Incorrect'), findsOneWidget);
    expect(find.text('Expected: Paris'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
  });

  testWidgets('QuizErrorFeedback shows error message and retry', (
    tester,
  ) async {
    bool retryCalled = false;
    await tester.pumpWidget(
      wrap(
        QuizErrorFeedback(
          message: 'Network error',
          onRetry: () => retryCalled = true,
        ),
      ),
    );
    expect(find.text('Network error'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retryCalled, isTrue);
  });
}
