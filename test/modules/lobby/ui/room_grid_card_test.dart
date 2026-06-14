import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_grid_card.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/unread_dot.dart';

// RoomGridCard fills the height of its grid cell (footer pinned to bottom),
// so it must be given a bounded height — mirror that here with a sized cell.
Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 280, height: 220, child: child),
        ),
      ),
    );

ClassificationTheme _classifications() => ClassificationTheme(
      defaultId: 'internal',
      levels: const [
        ClassificationLevel(
          id: 'internal',
          label: 'INTERNAL',
          background: Colors.black12,
          foreground: Colors.black87,
        ),
      ],
    );

void main() {
  group('RoomGridCard', () {
    testWidgets('shows the unread dot only when isUnread', (tester) async {
      const room = Room(id: 'r1', name: 'General');

      await tester.pumpWidget(_harness(
        RoomGridCard(room: room, onTap: () {}, onInfoTap: () {}),
      ));
      expect(find.byType(UnreadDot), findsNothing);

      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: room,
          onTap: () {},
          onInfoTap: () {},
          isUnread: true,
        ),
      ));
      expect(find.byType(UnreadDot), findsOneWidget);
    });

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

    testWidgets('omits the description when empty', (tester) async {
      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: const Room(id: 'r1', name: 'General'),
          onTap: () {},
          onInfoTap: () {},
        ),
      ));

      // Only the name renders; the description block is skipped entirely.
      expect(find.text('General'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
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

    testWidgets('carries a classification badge seam', (tester) async {
      await tester.pumpWidget(_harness(
        RoomGridCard(
          room: const Room(id: 'r1', name: 'General'),
          onTap: () {},
          onInfoTap: () {},
        ),
      ));

      expect(find.byType(SoliplexClassificationBadge), findsOneWidget);
    });

    testWidgets('shows the configured default marking', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(classifications: _classifications()),
          home: Scaffold(
            body: Center(
              child: RoomGridCard(
                room: const Room(id: 'r1', name: 'General'),
                onTap: () {},
                onInfoTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('INTERNAL'), findsOneWidget);
    });
  });
}
