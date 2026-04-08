import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_welcome.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows quiz section when room has quizzes', (tester) async {
    String? tappedQuizId;
    await tester.pumpWidget(wrap(
      RoomWelcome(
        room: Room(
          id: 'room-1',
          name: 'Test Room',
          quizzes: {'q1': 'Intro Quiz'},
        ),
        fallback: const Text('fallback'),
        onQuizTapped: (id) => tappedQuizId = id,
      ),
    ));
    expect(find.text('Intro Quiz'), findsOneWidget);
    await tester.tap(find.text('Intro Quiz'));
    expect(tappedQuizId, 'q1');
  });

  testWidgets('hides quiz section when no quizzes', (tester) async {
    await tester.pumpWidget(wrap(
      RoomWelcome(
        room: Room(id: 'room-1', name: 'Test Room'),
        fallback: const Text('fallback'),
      ),
    ));
    expect(find.byIcon(Icons.quiz), findsNothing);
  });
}
