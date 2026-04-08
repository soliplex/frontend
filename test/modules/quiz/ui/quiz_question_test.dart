// test/modules/quiz/ui/quiz_question_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';
import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_question.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows question text and progress', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(
        id: 'q',
        title: 'Test',
        questions: const [
          QuizQuestion(id: 'q1', text: 'What is 2+2?', type: FreeForm()),
          QuizQuestion(id: 'q2', text: 'Q2', type: FreeForm()),
        ],
      ),
      currentIndex: 0,
      results: const {},
      questionState: const AwaitingInput(),
    );
    await tester.pumpWidget(wrap(
      QuizQuestionView(
        session: session,
        answerController: TextEditingController(),
        submissionError: null,
        onSelectOption: (_) {},
        onTextChanged: (_) {},
        onSubmit: () {},
        onNext: () {},
        onRetry: () {},
      ),
    ));
    expect(find.text('What is 2+2?'), findsOneWidget);
    expect(find.text('Question 1 of 2'), findsOneWidget);
  });

  testWidgets('submit button disabled when awaiting input', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {},
      questionState: const AwaitingInput(),
    );
    await tester.pumpWidget(wrap(
      QuizQuestionView(
        session: session,
        answerController: TextEditingController(),
        submissionError: null,
        onSelectOption: (_) {},
        onTextChanged: (_) {},
        onSubmit: () {},
        onNext: () {},
        onRetry: () {},
      ),
    ));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows error feedback when submissionError set', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {},
      questionState: const Composing(TextInput('answer')),
    );
    await tester.pumpWidget(wrap(
      QuizQuestionView(
        session: session,
        answerController: TextEditingController(text: 'answer'),
        submissionError: 'Network error',
        onSelectOption: (_) {},
        onTextChanged: (_) {},
        onSubmit: () {},
        onNext: () {},
        onRetry: () {},
      ),
    ));
    expect(find.text('Network error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
