import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info/quizzes_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows quiz titles', (tester) async {
    await tester.pumpWidget(
      wrap(
        QuizzesCard(
          quizzes: const {'q1': 'Intro Quiz', 'q2': 'Advanced'},
          onQuizTapped: (_) {},
        ),
      ),
    );
    expect(find.text('QUIZZES (2)'), findsOneWidget);
    expect(find.text('Intro Quiz'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
  });

  testWidgets('shows empty message when no quizzes', (tester) async {
    await tester.pumpWidget(
      wrap(const QuizzesCard(quizzes: {}, onQuizTapped: null)),
    );
    expect(find.text('QUIZZES'), findsOneWidget);
    expect(find.text('No quizzes in this room.'), findsOneWidget);
  });

  testWidgets('fires onQuizTapped', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      wrap(
        QuizzesCard(
          quizzes: const {'q1': 'Quiz 1'},
          onQuizTapped: (id) => tapped = id,
        ),
      ),
    );
    await tester.tap(find.text('Quiz 1'));
    expect(tapped, 'q1');
  });
}
