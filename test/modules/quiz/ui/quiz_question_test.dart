import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';
import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_answer_input.dart';
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

  testWidgets('shows Next Question button when not last question',
      (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q1', type: FreeForm()),
        QuizQuestion(id: 'q2', text: 'Q2', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {'q1': CorrectAnswer()},
      questionState: const Answered(TextInput('a'), CorrectAnswer()),
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
    expect(find.text('Next Question'), findsOneWidget);
  });

  testWidgets('submit button enabled when Composing with valid input',
      (tester) async {
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
        submissionError: null,
        onSelectOption: (_) {},
        onTextChanged: (_) {},
        onSubmit: () {},
        onNext: () {},
        onRetry: () {},
      ),
    ));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('submit button disabled when Composing with blank input',
      (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {},
      questionState: const Composing(TextInput('   ')),
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

  testWidgets('shows spinner during Submitting state', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {},
      questionState: const Submitting(TextInput('answer')),
    );
    await tester.pumpWidget(wrap(
      QuizQuestionView(
        session: session,
        answerController: TextEditingController(text: 'answer'),
        submissionError: null,
        onSelectOption: (_) {},
        onTextChanged: (_) {},
        onSubmit: () {},
        onNext: () {},
        onRetry: () {},
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('renders multiple choice input for MultipleChoice question',
      (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: [
        QuizQuestion(
          id: 'q1',
          text: 'Pick one',
          type: MultipleChoice(['A', 'B', 'C']),
        ),
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
    expect(find.byType(QuizMultipleChoiceInput), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('renders text input for FillBlank question', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Fill in', type: FillBlank()),
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
    expect(find.byType(QuizTextInput), findsOneWidget);
  });

  testWidgets('shows answer feedback when Answered', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
        QuizQuestion(id: 'q2', text: 'Q2', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {'q1': CorrectAnswer()},
      questionState: const Answered(TextInput('a'), CorrectAnswer()),
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
    expect(find.text('Correct!'), findsOneWidget);
  });

  testWidgets('shows See Results button on last question', (tester) async {
    final session = QuizInProgress(
      quiz: Quiz(id: 'q', title: 'T', questions: const [
        QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
      ]),
      currentIndex: 0,
      results: const {'q1': CorrectAnswer()},
      questionState: const Answered(TextInput('a'), CorrectAnswer()),
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
    expect(find.text('See Results'), findsOneWidget);
  });
}
