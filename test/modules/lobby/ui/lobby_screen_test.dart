import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_card.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_grid_card.dart';

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
          apiResolver: apiResolver,
        ),
      ),
      GoRoute(
        path: '/servers',
        builder: (_, __) => const Scaffold(body: Text('Servers')),
      ),
      GoRoute(
        path: '/',
        builder: (_, state) {
          onHomeRoute?.call(state.uri);
          return const Scaffold(body: Text('Home'));
        },
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
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

        // The panel description is unique to the RoomsExpired arm
        // (the sidebar tile also renders "Session expired", but only
        // as a subtitle), so it pins the panel without ambiguity.
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

      await tester.enterText(find.byType(TextField), 'gen');
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

      await tester.enterText(find.byType(TextField), 'zzz');
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

      await tester.enterText(find.byType(TextField), 'gen');
      await tester.pumpAndSettle();
      expect(find.byType(RoomCard), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.byType(RoomCard), findsNWidgets(2));
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
  });
}
