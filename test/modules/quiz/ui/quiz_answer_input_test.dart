// test/modules/quiz/ui/quiz_answer_input_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';
import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_answer_input.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('QuizMultipleChoiceInput', () {
    testWidgets('renders all options', (tester) async {
      await tester.pumpWidget(wrap(
        QuizMultipleChoiceInput(
          options: const ['A', 'B', 'C'],
          selectedOption: null,
          questionState: const AwaitingInput(),
          onSelected: (_) {},
        ),
      ));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('calls onSelected when option tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(wrap(
        QuizMultipleChoiceInput(
          options: const ['A', 'B'],
          selectedOption: null,
          questionState: const AwaitingInput(),
          onSelected: (v) => selected = v,
        ),
      ));
      await tester.tap(find.text('A'));
      expect(selected, 'A');
    });

    testWidgets('disables options when answered', (tester) async {
      String? selected;
      await tester.pumpWidget(wrap(
        QuizMultipleChoiceInput(
          options: const ['A', 'B'],
          selectedOption: 'A',
          questionState: const Answered(
            MultipleChoiceInput('A'),
            CorrectAnswer(),
          ),
          onSelected: (v) => selected = v,
        ),
      ));
      await tester.tap(find.text('B'));
      expect(selected, isNull);
    });
  });

  group('QuizTextInput', () {
    testWidgets('renders text field', (tester) async {
      await tester.pumpWidget(wrap(
        QuizTextInput(
          controller: TextEditingController(),
          questionState: const AwaitingInput(),
          onChanged: (_) {},
          onSubmitted: () {},
        ),
      ));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('calls onChanged when typing', (tester) async {
      String? changed;
      await tester.pumpWidget(wrap(
        QuizTextInput(
          controller: TextEditingController(),
          questionState: const AwaitingInput(),
          onChanged: (v) => changed = v,
          onSubmitted: () {},
        ),
      ));
      await tester.enterText(find.byType(TextField), 'hello');
      expect(changed, 'hello');
    });

    testWidgets('disables text field when answered', (tester) async {
      await tester.pumpWidget(wrap(
        QuizTextInput(
          controller: TextEditingController(),
          questionState: const Answered(TextInput('x'), CorrectAnswer()),
          onChanged: (_) {},
          onSubmitted: () {},
        ),
      ));
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });
  });
}
