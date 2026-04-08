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

  testWidgets('shows singular header for one quiz', (tester) async {
    await tester.pumpWidget(wrap(
      RoomWelcome(
        room: Room(
          id: 'room-1',
          name: 'Test Room',
          quizzes: {'q1': 'Intro Quiz'},
        ),
        fallback: const Text('fallback'),
      ),
    ));
    expect(find.text('Quiz Available'), findsOneWidget);
  });

  testWidgets('shows plural header for multiple quizzes', (tester) async {
    await tester.pumpWidget(wrap(
      RoomWelcome(
        room: Room(
          id: 'room-1',
          name: 'Test Room',
          quizzes: {'q1': 'Quiz A', 'q2': 'Quiz B'},
        ),
        fallback: const Text('fallback'),
      ),
    ));
    expect(find.text('2 Quizzes Available'), findsOneWidget);
  });

  testWidgets('shows fallback when room has no content', (tester) async {
    await tester.pumpWidget(wrap(
      const RoomWelcome(
        room: Room(id: 'room-1', name: 'Empty Room'),
        fallback: Text('fallback'),
      ),
    ));
    expect(find.text('fallback'), findsOneWidget);
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

  testWidgets('shows fallback when room is null', (tester) async {
    await tester.pumpWidget(wrap(
      const RoomWelcome(
        room: null,
        fallback: Text('fallback'),
      ),
    ));
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('shows welcome message when present', (tester) async {
    await tester.pumpWidget(wrap(
      const RoomWelcome(
        room: Room(
          id: 'room-1',
          name: 'Research Bot',
          welcomeMessage: 'Welcome! Ask me anything.',
        ),
        fallback: Text('fallback'),
      ),
    ));
    expect(find.text('Research Bot'), findsOneWidget);
    expect(find.text('Welcome! Ask me anything.'), findsOneWidget);
  });
}
