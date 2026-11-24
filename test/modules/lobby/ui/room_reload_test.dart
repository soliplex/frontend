import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room;
import 'package:soliplex_client/soliplex_client.dart'
    show ApiException, RoomConfigsReloaded;
import 'package:soliplex_design/soliplex_design.dart' show soliplexLightTheme;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';

import '../../../helpers/fakes.dart';

final _reloadButton = find.byTooltip('Reload room configs');

/// Pumps the lobby with one connected server whose administrator check
/// answers [isAdmin].
Future<FakeSoliplexApi> _pumpLobby(
  WidgetTester tester, {
  bool isAdmin = true,
  Size size = const Size(1000, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final clients = AuthzOnlyClients(isAdminUser: isAdmin);
  final manager = ServerManager(
    authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
    clientFactory: ({getToken, tokenRefresher}) => clients.create(),
    storage: InMemoryServerStorage(),
  );
  manager.addServer(
    serverId: 'local',
    serverUrl: Uri.parse('http://localhost:8000'),
    requiresAuth: false,
  );
  final fakeApi = FakeSoliplexApi()
    ..nextRooms = const [Room(id: 'r1', name: 'General')]
    ..allThreads = const []
    ..labels = const [];

  final router = GoRouter(
    initialLocation: '/lobby',
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, __) => LobbyScreen(
          serverManager: manager,
          identity: testIdentity(),
          apiResolver: (_) => fakeApi,
        ),
      ),
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('H'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: soliplexLightTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fakeApi;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('reload rooms control', () {
    testWidgets('an administrator sees it', (tester) async {
      await _pumpLobby(tester);

      expect(_reloadButton, findsOneWidget);
    });

    testWidgets('an administrator sees it on a phone too', (tester) async {
      await _pumpLobby(tester, size: const Size(400, 800));

      expect(_reloadButton, findsOneWidget);
    });

    testWidgets('a non-administrator does not', (tester) async {
      await _pumpLobby(tester, isAdmin: false);

      expect(_reloadButton, findsNothing);
    });

    testWidgets('reloads, re-fetches the rooms and says what changed',
        (tester) async {
      final fakeApi = await _pumpLobby(tester);
      fakeApi
        ..nextRoomReload = const RoomConfigsReloaded(added: ['r2'])
        ..nextRooms = const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Fresh'),
        ];

      await tester.tap(_reloadButton);
      await tester.pumpAndSettle();

      expect(fakeApi.reloadRoomConfigsCallCount, 1);
      expect(find.text('Rooms reloaded: 1 added'), findsOneWidget);
      expect(find.text('Fresh'), findsOneWidget);
    });

    testWidgets('a multi-worker server is told to restart', (tester) async {
      final fakeApi = await _pumpLobby(tester);
      fakeApi.nextRoomReloadThrow =
          const ApiException(message: 'Conflict', statusCode: 409);

      await tester.tap(_reloadButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Restart it'), findsOneWidget);
    });
  });

  group('roomReloadMessage', () {
    test('names each kind of change that happened', () {
      expect(
        roomReloadMessage(
          const RoomsReloaded(
            RoomConfigsReloaded(
              added: ['a'],
              removed: ['b', 'c'],
              changed: ['d'],
            ),
          ),
        ),
        'Rooms reloaded: 1 added, 2 removed, 1 changed',
      );
    });

    test('says so when nothing changed', () {
      expect(
        roomReloadMessage(const RoomsReloaded(RoomConfigsReloaded())),
        'Room configs are already up to date',
      );
    });

    test('has a message for every failure', () {
      for (final outcome in const <RoomReloadOutcome>[
        RoomReloadNeedsRestart(),
        RoomReloadRefused(),
        RoomReloadSignedOut(),
        RoomReloadFailed(),
      ]) {
        expect(roomReloadMessage(outcome), isNotEmpty);
      }
    });
  });
}
