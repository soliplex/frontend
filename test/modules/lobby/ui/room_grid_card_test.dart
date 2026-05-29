import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_grid_card.dart';

Widget _harness(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('RoomGridCard', () {
    testWidgets('renders name and description', (tester) async {
      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: const Room(
            id: 'r1',
            name: 'General',
            description: 'Team-wide chat',
          ),
          onTap: () {},
          onInfoTap: () {},
        ),
      ));

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Team-wide chat'), findsOneWidget);
    });

    testWidgets('shows the quiz badge only when the room has quizzes',
        (tester) async {
      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: const Room(id: 'r1', name: 'No quiz'),
          onTap: () {},
          onInfoTap: () {},
        ),
      ));
      expect(find.byIcon(Icons.quiz), findsNothing);

      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: const Room(
            id: 'r2',
            name: 'Has quiz',
            quizzes: {'q1': 'Quiz One'},
          ),
          onTap: () {},
          onInfoTap: () {},
        ),
      ));
      expect(find.byIcon(Icons.quiz), findsOneWidget);
    });

    testWidgets('fires onTap and onInfoTap', (tester) async {
      var tapped = 0;
      var infoTapped = 0;
      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: const Room(id: 'r1', name: 'General'),
          onTap: () => tapped++,
          onInfoTap: () => infoTapped++,
        ),
      ));

      await tester.tap(find.byIcon(Icons.info_outline));
      expect(infoTapped, 1);
      expect(tapped, 0);

      await tester.tap(find.text('General'));
      expect(tapped, 1);
    });
  });
}
