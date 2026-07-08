import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room, RoomStats;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_sort_mode.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_card.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_grid_card.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/server_sidebar.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/unread_dot.dart';

import '../../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildApp(
  ServerManager manager, {
  void Function(Uri location)? onHomeRoute,
  ApiResolver? apiResolver,
}) {
  final router = GoRouter(
    initialLocation: '/lobby',
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, __) => LobbyScreen(
          serverManager: manager,
          identity: testIdentity(),
          apiResolver: apiResolver,
        ),
      ),
      GoRoute(
        path: '/',
        builder: (_, state) {
          onHomeRoute?.call(state.uri);
          return const Scaffold(body: Text('Home'));
        },
      ),
      GoRoute(
        path: '/room/:alias/:roomId',
        builder: (_, __) => const Scaffold(body: Text('Room')),
      ),
    ],
  );
  // The sidebar's per-tile ⋮ menu is a ConsumerWidget, so the tree needs a
  // ProviderScope; the auth providers are only read when a logout fires.
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LobbyScreen', () {
    testWidgets('shows sidebar on wide viewport with Add Server visible',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // No hamburger menu icon in wide layout
      expect(find.byIcon(Icons.menu), findsNothing);

      // Sidebar Add Server button is directly visible (no Drawer wrapping it)
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Add Server'), findsWidgets);
    });

    testWidgets(
        'uses drawer on narrow viewport — hamburger opens drawer with Add Server',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // Hamburger icon present in narrow layout
      expect(find.byIcon(Icons.menu), findsOneWidget);

      // Drawer not yet open
      expect(find.byType(Drawer), findsNothing);

      // Open the drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer is now open and contains the sidebar with Add Server
      expect(find.byType(Drawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Add Server'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('wide layout insets content below the top safe area',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 50);
      addTearDown(tester.view.reset);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // The wide layout has no AppBar, so without a SafeArea the sidebar
      // would paint under the status bar / notch. It must start below the
      // top inset.
      expect(
        tester.getTopLeft(find.byType(ServerSidebar)).dy,
        greaterThanOrEqualTo(50.0),
      );
    });

    testWidgets('narrow drawer insets the sidebar below the top safe area',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 50);
      addTearDown(tester.view.reset);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // A Drawer applies no inset of its own; without a SafeArea the brand
      // header would paint under the status bar / notch.
      expect(
        tester.getTopLeft(find.byType(ServerSidebar)).dy,
        greaterThanOrEqualTo(50.0),
      );
    });

    testWidgets('shows empty state CTA when no servers connected',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // Empty state: prominent Add Server CTA in the room content area
      expect(find.text('No servers connected'), findsOneWidget);
    });

    testWidgets(
      'expired-session row renders Sign in button that routes to '
      'homeWithUrl with returnTo=lobby',
      (tester) async {
        // The whole purpose of keeping the expired row visible is to
        // give the user a way to recover. A regression that removed
        // the button or mis-wired its onPressed would re-introduce
        // the "invisible expired server" bug this commit fixes.
        tester.view.physicalSize = const Size(900, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'auth-server',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        entry.auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        entry.auth.markSessionExpired();

        Uri? homeLocation;
        await tester.pumpWidget(
          _buildApp(manager, onHomeRoute: (uri) => homeLocation = uri),
        );
        await tester.pump();

        // The panel description is unique to the RoomsExpired arm, so it
        // pins the panel without ambiguity.
        expect(
          find.text('Sign in again to view rooms on this server.'),
          findsOneWidget,
        );
        expect(find.text('Sign in'), findsOneWidget);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();

        expect(homeLocation, isNotNull);
        expect(
          homeLocation!.queryParameters['url'],
          'https://api.example.com',
        );
        expect(homeLocation!.queryParameters['returnTo'], '/lobby');
      },
    );

    testWidgets(
      'signed-out row renders Sign in button that routes to '
      'homeWithUrl with returnTo=lobby',
      (tester) async {
        // A logged-out (or inactivity-timed-out) server stays selected in
        // the single-server lobby. Without a recoverable affordance the
        // content pane is blank, stranding the user; the row must offer a
        // sign-in path instead.
        tester.view.physicalSize = const Size(900, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'auth-server',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        entry.auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        entry.auth.logout();

        Uri? homeLocation;
        await tester.pumpWidget(
          _buildApp(manager, onHomeRoute: (uri) => homeLocation = uri),
        );
        await tester.pump();

        // Copy is unique to the RoomsSignedOut arm so it pins the panel
        // without colliding with the RoomsExpired arm's "again" wording.
        expect(
          find.text('Sign in to view rooms on this server.'),
          findsOneWidget,
        );
        expect(find.text('Sign in'), findsOneWidget);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();

        expect(homeLocation, isNotNull);
        expect(
          homeLocation!.queryParameters['url'],
          'https://api.example.com',
        );
        expect(homeLocation!.queryParameters['returnTo'], '/lobby');
      },
    );

    testWidgets('toggle switches loaded rooms from list to grid cards',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'room-1', name: 'General')];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      // List mode (default): list-row card, no grid card.
      expect(find.byType(RoomCard), findsOneWidget);
      expect(find.byType(RoomGridCard), findsNothing);

      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();

      expect(find.byType(RoomGridCard), findsOneWidget);
      expect(find.byType(RoomCard), findsNothing);
    });

    testWidgets(
        'tapping a room does not mark it read '
        '(room-screen rollup owns room read state)', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'room-1', name: 'General')];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RoomCard));
      await tester.pumpAndSettle();

      // Reached the room route, but persisted NO room read marker: opening a
      // room must not stamp it read — the room screen's per-thread rollup owns
      // that, so a genuinely-unread thread isn't hidden.
      expect(find.text('Room'), findsOneWidget);
      expect(
        await LobbyReadMarkerStorage.loadServer(
            serverId: 'local', userId: null),
        isEmpty,
      );
    });

    testWidgets('honors the persisted grid mode on load', (tester) async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_view_mode': 'grid'},
      );
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'room-1', name: 'General')];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      expect(find.byType(RoomGridCard), findsOneWidget);
      expect(find.byType(RoomCard), findsNothing);
    });

    testWidgets('forces list and hides the toggle below the tablet breakpoint',
        (tester) async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_view_mode': 'grid'},
      );
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'room-1', name: 'General')];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      // Phone width forces list even though 'grid' is persisted, and the
      // view-mode toggle is hidden so the choice can't be changed here.
      expect(find.byType(RoomCard), findsOneWidget);
      expect(find.byType(RoomGridCard), findsNothing);
      expect(find.byIcon(Icons.grid_view), findsNothing);
    });

    testWidgets('search filters rooms by name within the section',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Random'),
        ];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();
      expect(find.byType(RoomCard), findsNWidgets(2));

      await tester.enterText(
          find.widgetWithIcon(TextField, Icons.search), 'gen');
      await tester.pumpAndSettle();

      expect(find.byType(RoomCard), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Random'), findsNothing);
    });

    testWidgets('shows no-match copy when the filter excludes everything',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithIcon(TextField, Icons.search), 'zzz');
      await tester.pumpAndSettle();

      expect(find.byType(RoomCard), findsNothing);
      expect(find.textContaining('No rooms match'), findsOneWidget);
    });

    testWidgets('clear button resets the filter', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Random'),
        ];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithIcon(TextField, Icons.search), 'gen');
      await tester.pumpAndSettle();
      expect(find.byType(RoomCard), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.byType(RoomCard), findsNWidgets(2));
    });

    testWidgets(
        'sorting by recent activity reorders rooms by their last message',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      // 'General' is listed first but has the older message; 'Random' has the
      // newer one, so recent-activity sorting must put 'Random' on top.
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Random'),
        ]
        ..roomsStats = {
          'r1': RoomStats(lastActivity: DateTime.utc(2026, 1)),
          'r2': RoomStats(lastActivity: DateTime.utc(2026, 6)),
        };

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      List<String> roomOrder() => tester
          .widgetList<RoomCard>(find.byType(RoomCard))
          .map((c) => c.room.name)
          .toList();

      // Default sort (none): backend order is preserved.
      expect(roomOrder(), ['General', 'Random']);

      // Open the sort dropdown and choose "Recent activity" (the offstage
      // measurement copy of the entry isn't hit-testable, so target the
      // on-screen one).
      await tester.tap(find.byType(DropdownMenu<LobbySortMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent activity').hitTestable());
      await tester.pumpAndSettle();

      expect(roomOrder(), ['Random', 'General']);
    });

    testWidgets('shows an unread dot for a room with unseen activity',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')]
        ..roomsStats = {'r1': RoomStats(lastActivity: DateTime.utc(2026, 6))};

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      // The room has activity and no read marker, so it reads as unread.
      expect(find.byType(UnreadDot), findsOneWidget);
    });

    testWidgets('recent-activity sort groups rooms under date-bucket headers',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final now = DateTime.now().toUtc();
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'Fresh'),
          Room(id: 'r2', name: 'Stale'),
        ]
        ..roomsStats = {
          'r1': RoomStats(lastActivity: now),
          'r2': RoomStats(
            lastActivity: now.subtract(const Duration(days: 10)),
          ),
        };

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      // No section headers until sorting by recent activity.
      expect(find.text('Today'), findsNothing);

      await tester.tap(find.byType(DropdownMenu<LobbySortMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent activity').hitTestable());
      await tester.pumpAndSettle();

      // Two buckets: today (Fresh) and ~10 days ago (This month).
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
    });

    testWidgets('recent-activity sort keeps undated rooms last in input order',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 6, 1);
      // Alpha and Charlie have no activity (undated); Bravo/Delta are dated.
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'Alpha'),
          Room(id: 'r2', name: 'Bravo'),
          Room(id: 'r3', name: 'Charlie'),
          Room(id: 'r4', name: 'Delta'),
        ]
        ..roomsStats = {
          'r1': RoomStats(),
          'r2': RoomStats(lastActivity: newer),
          'r3': RoomStats(),
          'r4': RoomStats(lastActivity: older),
        };

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      List<String> roomOrder() => tester
          .widgetList<RoomCard>(find.byType(RoomCard))
          .map((c) => c.room.name)
          .toList();

      expect(roomOrder(), ['Alpha', 'Bravo', 'Charlie', 'Delta']);

      await tester.tap(find.byType(DropdownMenu<LobbySortMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent activity').hitTestable());
      await tester.pumpAndSettle();

      // Dated rooms first (newest -> oldest), then undated in original order.
      expect(roomOrder(), ['Bravo', 'Delta', 'Alpha', 'Charlie']);
    });

    testWidgets(
        'unread-first sort groups unread rooms above read rooms with headers',
        (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      // 'Fresh' has activity and no read marker -> unread. 'Quiet' has no
      // activity -> read. Backend lists the read room first, so the grouping
      // (not the input order) is what pulls 'Fresh' to the top.
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'Quiet'),
          Room(id: 'r2', name: 'Fresh'),
        ]
        ..roomsStats = {
          'r1': RoomStats(),
          'r2': RoomStats(lastActivity: DateTime.utc(2026, 6)),
        };

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      // No section headers under the default 'None' sort.
      expect(find.text('Unread'), findsNothing);
      expect(find.text('Read'), findsNothing);

      await tester.tap(find.byType(DropdownMenu<LobbySortMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unread first').hitTestable());
      await tester.pumpAndSettle();

      // Both section headers present.
      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);

      // The unread room card sits above the read room card.
      final freshY = tester.getTopLeft(find.text('Fresh')).dy;
      final quietY = tester.getTopLeft(find.text('Quiet')).dy;
      expect(freshY, lessThan(quietY));
    });

    testWidgets(
        'shows only the selected server, and switching the sidebar '
        'selection swaps the shown rooms', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      manager.addServer(
        serverId: 'other',
        serverUrl: Uri.parse('http://other.test:8000'),
        requiresAuth: false,
      );

      final localApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')];
      final otherApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r2', name: 'Special')];

      await tester.pumpWidget(_buildApp(
        manager,
        apiResolver: (entry) => entry.serverId == 'local' ? localApi : otherApi,
      ));
      await tester.pumpAndSettle();

      // First server is auto-selected: only its room shows.
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Special'), findsNothing);

      // Select the second server in the sidebar.
      await tester.tap(find.text('http://other.test:8000'));
      await tester.pumpAndSettle();

      expect(find.text('Special'), findsOneWidget);
      expect(find.text('General'), findsNothing);
    });

    testWidgets(
        'selecting a server in the narrow drawer closes it and swaps '
        'the shown rooms', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      manager.addServer(
        serverId: 'other',
        serverUrl: Uri.parse('http://other.test:8000'),
        requiresAuth: false,
      );

      final localApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')];
      final otherApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r2', name: 'Special')];

      await tester.pumpWidget(_buildApp(
        manager,
        apiResolver: (entry) => entry.serverId == 'local' ? localApi : otherApi,
      ));
      await tester.pumpAndSettle();

      // First server is auto-selected; open the drawer to switch.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Tap the second server's tile inside the drawer.
      await tester.tap(find.text('http://other.test:8000'));
      await tester.pumpAndSettle();

      // The drawer closes and the newly-selected server's rooms show.
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Special'), findsOneWidget);
      expect(find.text('General'), findsNothing);
    });

    testWidgets(
        'unread room card long-press marks it read: persists the marker '
        'and clears the dot', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')]
        ..roomsStats = {'r1': RoomStats(lastActivity: DateTime.utc(2026, 6))};

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();

      // Unread to begin with (activity, no marker).
      expect(find.byType(UnreadDot), findsOneWidget);

      await tester.longPress(find.byType(RoomCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      // The dot clears reactively, and the room's marker is persisted keyed by
      // its id (so the gating wired the correct room, not just any room).
      expect(find.byType(UnreadDot), findsNothing);
      expect(
        (await LobbyReadMarkerStorage.loadServer(
                serverId: 'local', userId: null))
            .keys,
        contains('r1'),
      );
    });

    testWidgets('a read room card offers no Mark as read menu', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      // No activity => not unread => the gating passes a null callback, so the
      // context menu adds no gesture and a long-press opens nothing.
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')];

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();
      expect(find.byType(UnreadDot), findsNothing);

      await tester.longPress(find.byType(RoomCard));
      await tester.pumpAndSettle();
      expect(find.text('Mark as read'), findsNothing);
    });

    testWidgets(
        'unread room grid card long-press marks it read (grid layout wires '
        'the same gating)', (tester) async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_view_mode': 'grid'},
      );
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')]
        ..roomsStats = {'r1': RoomStats(lastActivity: DateTime.utc(2026, 6))};

      await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
      await tester.pumpAndSettle();
      expect(find.byType(RoomGridCard), findsOneWidget);
      expect(find.byType(UnreadDot), findsOneWidget);

      await tester.longPress(find.byType(RoomGridCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      expect(find.byType(UnreadDot), findsNothing);
      expect(
        (await LobbyReadMarkerStorage.loadServer(
                serverId: 'local', userId: null))
            .keys,
        contains('r1'),
      );
    });
  });
}
