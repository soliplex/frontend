import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';
import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_results.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows score and correct count', (tester) async {
    await tester.pumpWidget(wrap(
      QuizResultsView(
        session: QuizCompleted(
          quiz: Quiz(
            id: 'q',
            title: 'Test',
            questions: const [
              QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
              QuizQuestion(id: 'q2', text: 'Q', type: FreeForm()),
            ],
          ),
          results: const {
            'q1': CorrectAnswer(),
            'q2': IncorrectAnswer(expectedAnswer: 'X'),
          },
        ),
        onBack: () {},
        onRetake: () {},
      ),
    ));
    expect(find.text('Quiz Complete!'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1 of 2 correct'), findsOneWidget);
  });

  testWidgets('shows trophy icon for score >= 70%', (tester) async {
    await tester.pumpWidget(wrap(
      QuizResultsView(
        session: QuizCompleted(
          quiz: Quiz(id: 'q', title: 'T', questions: const [
            QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
            QuizQuestion(id: 'q2', text: 'Q', type: FreeForm()),
            QuizQuestion(id: 'q3', text: 'Q', type: FreeForm()),
          ]),
          results: const {
            'q1': CorrectAnswer(),
            'q2': CorrectAnswer(),
            'q3': IncorrectAnswer(expectedAnswer: 'X'),
          },
        ),
        onBack: () {},
        onRetake: () {},
      ),
    ));
    expect(find.text('66%'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
  });

  testWidgets('shows refresh icon for score < 40%', (tester) async {
    await tester.pumpWidget(wrap(
      QuizResultsView(
        session: QuizCompleted(
          quiz: Quiz(id: 'q', title: 'T', questions: const [
            QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
            QuizQuestion(id: 'q2', text: 'Q', type: FreeForm()),
            QuizQuestion(id: 'q3', text: 'Q', type: FreeForm()),
          ]),
          results: const {
            'q1': CorrectAnswer(),
            'q2': IncorrectAnswer(expectedAnswer: 'X'),
            'q3': IncorrectAnswer(expectedAnswer: 'Y'),
          },
        ),
        onBack: () {},
        onRetake: () {},
      ),
    ));
    expect(find.text('33%'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('shows trophy icon for perfect score', (tester) async {
    await tester.pumpWidget(wrap(
      QuizResultsView(
        session: QuizCompleted(
          quiz: Quiz(id: 'q', title: 'T', questions: const [
            QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
          ]),
          results: const {'q1': CorrectAnswer()},
        ),
        onBack: () {},
        onRetake: () {},
      ),
    ));
    expect(find.text('100%'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
  });

  testWidgets('back and retake buttons fire callbacks', (tester) async {
    bool backCalled = false;
    bool retakeCalled = false;
    await tester.pumpWidget(wrap(
      QuizResultsView(
        session: QuizCompleted(
          quiz: Quiz(id: 'q', title: 'T', questions: const [
            QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
          ]),
          results: const {'q1': CorrectAnswer()},
        ),
        onBack: () => backCalled = true,
        onRetake: () => retakeCalled = true,
      ),
    ));
    await tester.tap(find.text('Back to Room'));
    expect(backCalled, isTrue);
    await tester.tap(find.text('Retake Quiz'));
    expect(retakeCalled, isTrue);
  });
}
