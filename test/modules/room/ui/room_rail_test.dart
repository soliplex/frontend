import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show PermissionDeniedException, Room;
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
  Set<String> unreadRoomIds = const {},
  int? dividerIndex,
  void Function(String)? onSelectRoom,
  void Function(String)? onMarkRoomRead,
  VoidCallback? onRetryRooms,
  RoomAccount? account,
  VoidCallback? onNetworkInspector,
  VoidCallback? onVersions,
}) =>
    RoomRail(
      rooms: rooms,
      roomsError: roomsError,
      onRetryRooms: onRetryRooms,
      unreadRoomIds: unreadRoomIds,
      dividerIndex: dividerIndex,
      selectedRoomId: selectedRoomId,
      onSelectRoom: onSelectRoom ?? (_) {},
      onMarkRoomRead: onMarkRoomRead,
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

    testWidgets('marks only unread rooms with a dot', (tester) async {
      await tester.pumpWidget(_wrap(_rail(unreadRoomIds: const {'r2'})));
      expect(find.byTooltip('Unread activity'), findsOneWidget);
    });

    testWidgets(
        'long-pressing an unread room offers Mark as read and fires with '
        'its id', (tester) async {
      String? marked;
      await tester.pumpWidget(_wrap(_rail(
        unreadRoomIds: const {'r2'},
        onMarkRoomRead: (id) => marked = id,
      )));

      await tester.longPress(find.text('B')); // Beta = r2, unread
      await tester.pumpAndSettle();
      expect(find.text('Mark as read'), findsOneWidget);
      // The menu surfaces the room name (the avatar shows only 'B').
      expect(find.text('Beta'), findsOneWidget);

      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();
      expect(marked, 'r2');
    });

    testWidgets('long-pressing a read room offers no Mark as read',
        (tester) async {
      await tester.pumpWidget(_wrap(_rail(
        unreadRoomIds: const {'r2'},
        onMarkRoomRead: (_) {},
      )));

      await tester.longPress(find.text('A')); // Alpha = r1, read
      await tester.pumpAndSettle();
      expect(find.text('Mark as read'), findsNothing);
    });

    testWidgets('shows no dots when nothing is unread', (tester) async {
      await tester.pumpWidget(_wrap(_rail()));
      expect(find.byTooltip('Unread activity'), findsNothing);
    });

    testWidgets('renders the divider between the rooms at dividerIndex',
        (tester) async {
      await tester.pumpWidget(_wrap(_rail(
        rooms: const [
          Room(id: 'r1', name: 'Alpha'),
          Room(id: 'r2', name: 'Beta'),
        ],
        dividerIndex: 1,
      )));
      final divider = find.byKey(const ValueKey('rail-unread-divider'));
      expect(divider, findsOneWidget);
      // The divider sits below the first room and above the second — the one
      // thing the index-shift in _buildList encodes.
      final alphaY = tester.getTopLeft(find.text('A')).dy;
      final dividerY = tester.getTopLeft(divider).dy;
      final betaY = tester.getTopLeft(find.text('B')).dy;
      expect(alphaY, lessThan(dividerY));
      expect(dividerY, lessThan(betaY));
    });

    testWidgets('renders no divider when dividerIndex is null', (tester) async {
      await tester.pumpWidget(_wrap(_rail()));
      expect(find.byKey(const ValueKey('rail-unread-divider')), findsNothing);
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

    testWidgets('shows a non-retryable affordance for a permission denial',
        (tester) async {
      await tester.pumpWidget(_wrap(_rail(
        rooms: null,
        roomsError:
            const PermissionDeniedException(statusCode: 403, message: 'no'),
        onRetryRooms: () {},
      )));

      // A 403 is a steady state — re-trying won't help — so the lock glyph
      // replaces the retry error glyph and the button is disabled.
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.lock_outline));
      expect(button.onPressed, isNull);
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

      // Each item carries its own onTap, so verify Versions is wired to its
      // own callback and not to the inspector's.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();
      expect(versions, isTrue);
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
