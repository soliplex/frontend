import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_card.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_markings_row.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/unread_dot.dart';

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

// A deliberately long marking to stress the markings row under large text
// scaling — the sort of value a real "controlled unclassified" deployment uses.
ClassificationTheme _longClassifications() => ClassificationTheme(
      defaultId: 'cui',
      levels: const [
        ClassificationLevel(
          id: 'cui',
          label: 'CONTROLLED UNCLASSIFIED INFORMATION//SP-EXPT',
          background: Colors.black12,
          foreground: Colors.black87,
        ),
      ],
    );

Widget _buildCard({
  required Room room,
  VoidCallback? onTap,
  VoidCallback? onInfoTap,
  bool isUnread = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: RoomCard(
        room: room,
        onTap: onTap ?? () {},
        onInfoTap: onInfoTap ?? () {},
        isUnread: isUnread,
      ),
    ),
  );
}

void main() {
  group('RoomCard', () {
    testWidgets('displays room name and description', (tester) async {
      const room = Room(id: 'r1', name: 'Test Room', description: 'A room');

      await tester.pumpWidget(_buildCard(room: room));

      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('A room'), findsOneWidget);
    });

    testWidgets('shows the unread dot only when isUnread', (tester) async {
      const room = Room(id: 'r1', name: 'Test Room');

      await tester.pumpWidget(_buildCard(room: room));
      expect(find.byType(UnreadDot), findsNothing);

      await tester.pumpWidget(_buildCard(room: room, isUnread: true));
      expect(find.byType(UnreadDot), findsOneWidget);
    });

    testWidgets('hides description when empty', (tester) async {
      const room = Room(id: 'r1', name: 'Test Room');

      await tester.pumpWidget(_buildCard(room: room));

      expect(find.text('Test Room'), findsOneWidget);
      final listTile = tester.widget<ListTile>(find.byType(ListTile));
      expect(listTile.subtitle, isNull);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      const room = Room(id: 'r1', name: 'Test Room');

      await tester.pumpWidget(_buildCard(
        room: room,
        onTap: () => tapped = true,
      ));

      await tester.tap(find.byType(ListTile));
      expect(tapped, isTrue);
    });

    testWidgets('shows quiz icon when room has quizzes', (tester) async {
      const room = Room(id: 'r1', name: 'Room 1', quizzes: {'q1': 'Quiz'});

      await tester.pumpWidget(_buildCard(room: room));

      expect(find.byIcon(Icons.quiz), findsOneWidget);
    });

    testWidgets('hides quiz icon when no quizzes', (tester) async {
      const room = Room(id: 'r1', name: 'Room 1');

      await tester.pumpWidget(_buildCard(room: room));

      expect(find.byIcon(Icons.quiz), findsNothing);
    });

    testWidgets('has info icon button that calls onInfoTap', (tester) async {
      var infoTapped = false;
      const room = Room(id: 'r1', name: 'Test Room');

      await tester.pumpWidget(_buildCard(
        room: room,
        onInfoTap: () => infoTapped = true,
      ));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.info_outline));
      expect(infoTapped, isTrue);
    });

    testWidgets('carries a classification badge seam', (tester) async {
      const room = Room(id: 'r1', name: 'Test Room');

      await tester.pumpWidget(_buildCard(room: room));

      expect(find.byType(SoliplexClassificationBadge), findsOneWidget);
    });

    testWidgets('shows the configured default marking', (tester) async {
      const room = Room(id: 'r1', name: 'Test Room');

      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(classifications: _classifications()),
          home: Scaffold(
            body: RoomCard(room: room, onTap: () {}, onInfoTap: () {}),
          ),
        ),
      );

      expect(find.text('INTERNAL'), findsOneWidget);
    });

    testWidgets('puts the marking and quiz on their own row below the tile',
        (tester) async {
      const room = Room(id: 'r1', name: 'Test Room', quizzes: {'q1': 'Quiz'});

      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(classifications: _classifications()),
          home: Scaffold(
            body: RoomCard(room: room, onTap: () {}, onInfoTap: () {}),
          ),
        ),
      );

      // The markings sit in a dedicated row, not the tile's trailing slot, so
      // they clear the ListTile's bottom edge instead of squeezing the name.
      expect(find.byType(RoomMarkingsRow), findsOneWidget);
      final tileBottom = tester.getRect(find.byType(ListTile)).bottom;
      expect(
        tester.getRect(find.byIcon(Icons.quiz)).top,
        greaterThanOrEqualTo(tileBottom),
      );
      expect(
        tester.getRect(find.text('INTERNAL')).top,
        greaterThanOrEqualTo(tileBottom),
      );
    });

    testWidgets('does not overflow under a large accessibility text scale',
        (tester) async {
      const room = Room(
        id: 'r1',
        name: 'A room with a deliberately very long name that overflows',
        description: 'A long description that also needs to wrap gracefully',
        quizzes: {'q1': 'Quiz'},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(classifications: _longClassifications()),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            // Cards live in a scrolling list in production, so vertical growth
            // is fine; a scroll view here isolates the guard that matters — the
            // markings row must not overflow *horizontally* when text scales.
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: RoomCard(room: room, onTap: () {}, onInfoTap: () {}),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
