import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show Room;
import 'package:soliplex_frontend/src/modules/room/ui/room_rail.dart';

import '../../../helpers/test_server_entry.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: RoomRail.width, child: child),
      ),
    );

RoomRail _rail({
  List<Room>? rooms = const [
    Room(id: 'r1', name: 'Alpha'),
    Room(id: 'r2', name: 'Beta'),
  ],
  Object? roomsError,
  String selectedRoomId = 'r1',
  void Function(String)? onSelectRoom,
  VoidCallback? onRetryRooms,
  RoomAccount? account,
  VoidCallback? onNetworkInspector,
  VoidCallback? onVersions,
}) =>
    RoomRail(
      rooms: rooms,
      roomsError: roomsError,
      onRetryRooms: onRetryRooms,
      selectedRoomId: selectedRoomId,
      onSelectRoom: onSelectRoom ?? (_) {},
      entry: createTestServerEntry(),
      account: account,
      onNetworkInspector: onNetworkInspector ?? () {},
      onVersions: onVersions ?? () {},
    );

void main() {
  group('RoomRail', () {
    testWidgets('renders an initial avatar per room', (tester) async {
      await tester.pumpWidget(_wrap(_rail()));
      expect(find.text('A'), findsOneWidget); // Alpha
      expect(find.text('B'), findsOneWidget); // Beta
    });

    testWidgets('tapping a room fires onSelectRoom', (tester) async {
      String? picked;
      await tester.pumpWidget(_wrap(_rail(onSelectRoom: (id) => picked = id)));
      await tester.tap(find.text('B'));
      expect(picked, 'r2');
    });

    testWidgets('shows a spinner while rooms are loading', (tester) async {
      await tester.pumpWidget(_wrap(_rail(rooms: null)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an error affordance that retries', (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(_rail(
        rooms: null,
        roomsError: Exception('boom'),
        onRetryRooms: () => retried = true,
      )));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.error_outline));
      expect(retried, isTrue);
    });

    testWidgets('footer menu exposes the account, inspector, and versions',
        (tester) async {
      var inspector = false;
      var versions = false;
      await tester.pumpWidget(_wrap(_rail(
        account: (name: 'Ada Lovelace', email: 'ada@example.com'),
        onNetworkInspector: () => inspector = true,
        onVersions: () => versions = true,
      )));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // A no-auth test server resolves to Guest regardless of the cached
      // account, since the identity gate requires an ActiveSession.
      expect(find.text('Guest'), findsOneWidget);
      expect(find.text('Network Inspector'), findsOneWidget);
      expect(find.text('Versions'), findsOneWidget);

      await tester.tap(find.text('Network Inspector'));
      await tester.pumpAndSettle();
      expect(inspector, isTrue);
      expect(versions, isFalse);
    });
  });

  group('roomAvatarColor', () {
    test('is deterministic for the same name', () {
      expect(
        roomAvatarColor('Alpha', Brightness.light),
        roomAvatarColor('Alpha', Brightness.light),
      );
    });

    test('varies the tone with brightness', () {
      expect(
        roomAvatarColor('Alpha', Brightness.light),
        isNot(roomAvatarColor('Alpha', Brightness.dark)),
      );
    });
  });
}
