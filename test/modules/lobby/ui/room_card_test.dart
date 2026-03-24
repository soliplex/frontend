import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_card.dart';

Widget _buildCard({
  required Room room,
  VoidCallback? onTap,
  VoidCallback? onInfoTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: RoomCard(
        room: room,
        onTap: onTap ?? () {},
        onInfoTap: onInfoTap ?? () {},
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
  });
}
