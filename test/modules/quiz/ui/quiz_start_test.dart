import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/ui/quiz_start.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows quiz title and question count', (tester) async {
    bool startCalled = false;
    await tester.pumpWidget(
      wrap(
        QuizStartView(
          quiz: Quiz(
            id: 'q',
            title: 'Intro to ML',
            questions: const [
              QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
              QuizQuestion(id: 'q2', text: 'Q', type: FreeForm()),
            ],
          ),
          onStart: () => startCalled = true,
        ),
      ),
    );
    expect(find.text('Intro to ML'), findsOneWidget);
    expect(find.text('2 questions'), findsOneWidget);
    await tester.tap(find.text('Start Quiz'));
    expect(startCalled, isTrue);
  });

  testWidgets('shows singular for 1 question', (tester) async {
    await tester.pumpWidget(
      wrap(
        QuizStartView(
          quiz: Quiz(
            id: 'q',
            title: 'Short',
            questions: const [
              QuizQuestion(id: 'q1', text: 'Q', type: FreeForm()),
            ],
          ),
          onStart: () {},
        ),
      ),
    );
    expect(find.text('1 question'), findsOneWidget);
  });
}
