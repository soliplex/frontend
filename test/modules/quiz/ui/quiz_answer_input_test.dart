import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';
import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_answer_input.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('QuizMultipleChoiceInput', () {
    testWidgets('renders all options', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B', 'C'],
            selectedOption: null,
            questionState: const AwaitingInput(),
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('calls onSelected when option tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B'],
            selectedOption: null,
            questionState: const AwaitingInput(),
            onSelected: (v) => selected = v,
          ),
        ),
      );
      await tester.tap(find.text('A'));
      expect(selected, 'A');
    });

    testWidgets('shows check icon on correct selected option', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B'],
            selectedOption: 'A',
            questionState: const Answered(
              MultipleChoiceInput('A'),
              CorrectAnswer(),
            ),
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows cancel icon on wrong selected option', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B'],
            selectedOption: 'A',
            questionState: const Answered(
              MultipleChoiceInput('A'),
              IncorrectAnswer(expectedAnswer: 'B'),
            ),
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('highlights correct option when answer is incorrect', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B'],
            selectedOption: 'A',
            questionState: const Answered(
              MultipleChoiceInput('A'),
              IncorrectAnswer(expectedAnswer: 'B'),
            ),
            onSelected: (_) {},
          ),
        ),
      );
      // The correct option 'B' should show check_circle
      // The wrong selected option 'A' should show cancel
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('disables options when submitting', (tester) async {
      String? selected;
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B'],
            selectedOption: 'A',
            questionState: const Submitting(MultipleChoiceInput('A')),
            onSelected: (v) => selected = v,
          ),
        ),
      );
      await tester.tap(find.text('B'));
      expect(selected, isNull);
    });

    testWidgets('disables options when answered', (tester) async {
      String? selected;
      await tester.pumpWidget(
        wrap(
          QuizMultipleChoiceInput(
            options: const ['A', 'B'],
            selectedOption: 'A',
            questionState: const Answered(
              MultipleChoiceInput('A'),
              CorrectAnswer(),
            ),
            onSelected: (v) => selected = v,
          ),
        ),
      );
      await tester.tap(find.text('B'));
      expect(selected, isNull);
    });
  });

  group('QuizTextInput', () {
    testWidgets('renders text field', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuizTextInput(
            controller: TextEditingController(),
            questionState: const AwaitingInput(),
            onChanged: (_) {},
            onSubmitted: () {},
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('calls onChanged when typing', (tester) async {
      String? changed;
      await tester.pumpWidget(
        wrap(
          QuizTextInput(
            controller: TextEditingController(),
            questionState: const AwaitingInput(),
            onChanged: (v) => changed = v,
            onSubmitted: () {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      expect(changed, 'hello');
    });

    testWidgets('disables text field when submitting', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuizTextInput(
            controller: TextEditingController(text: 'answer'),
            questionState: const Submitting(TextInput('answer')),
            onChanged: (_) {},
            onSubmitted: () {},
          ),
        ),
      );
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('disables text field when answered', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuizTextInput(
            controller: TextEditingController(),
            questionState: const Answered(TextInput('x'), CorrectAnswer()),
            onChanged: (_) {},
            onSubmitted: () {},
          ),
        ),
      );
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });
  });
}
