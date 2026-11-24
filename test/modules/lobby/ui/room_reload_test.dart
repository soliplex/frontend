import 'dart:async';

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
import 'package:soliplex_frontend/src/modules/lobby/room_reloads.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../helpers/fakes.dart';

final _reloadButton = find.byTooltip('Reload room configs');
final _reloadIconButton =
    find.ancestor(of: _reloadButton, matching: find.byType(IconButton)).first;
final _spinner = find.byType(CircularProgressIndicator);

const _noChange = RoomConfigsReloaded(added: [], removed: [], changed: []);

/// Pumps the lobby with one connected server whose administrator check
/// answers [isAdmin]. The reloads outlive the lobby, as the module's do, and
/// `/elsewhere` stands in for a room the user can leave the lobby for. Without
/// [reloadsFindServer] the reloads see no server, so a reload throws instead
/// of answering.
Future<(FakeSoliplexApi, GoRouter)> _pumpLobby(
  WidgetTester tester, {
  bool isAdmin = true,
  Size size = const Size(1000, 800),
  bool reloadsFindServer = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
  final roomReloads = RoomReloads(
    entryResolver: (id) => reloadsFindServer ? manager.servers.value[id] : null,
    apiResolver: (_) => fakeApi,
  );

  final router = GoRouter(
    initialLocation: '/lobby',
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, __) => LobbyScreen(
          serverManager: manager,
          identity: testIdentity(),
          apiResolver: (_) => fakeApi,
          roomReloads: roomReloads,
        ),
      ),
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('H'))),
      GoRoute(
        path: '/elsewhere',
        builder: (_, __) => const Scaffold(body: Text('Elsewhere')),
      ),
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
  return (fakeApi, router);
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
      final (fakeApi, _) = await _pumpLobby(tester);
      fakeApi
        ..nextRoomReload =
            const RoomConfigsReloaded(added: ['r2'], removed: [], changed: [])
        ..nextRooms = const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Fresh'),
        ];

      await tester.tap(_reloadButton);
      await tester.pumpAndSettle();

      expect(
          find.text('localhost:8000: Rooms reloaded: 1 added'), findsOneWidget);
      expect(find.text('Fresh'), findsOneWidget);
    });

    testWidgets('a multi-worker server is told to restart', (tester) async {
      final (fakeApi, _) = await _pumpLobby(tester);
      fakeApi.nextRoomReloadThrow =
          const ApiException(message: 'Conflict', statusCode: 409);

      await tester.tap(_reloadButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Restart it'), findsOneWidget);
    });

    testWidgets('shows a spinner and takes no press while reloading',
        (tester) async {
      final (fakeApi, _) = await _pumpLobby(tester);
      final gate = Completer<void>();
      fakeApi.roomReloadGate = gate;

      await tester.tap(_reloadButton);
      await tester.pump();

      final spinner = find.descendant(of: _reloadButton, matching: _spinner);
      expect(spinner, findsOneWidget);
      expect(tester.widget<IconButton>(_reloadIconButton).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(spinner, findsNothing);
      expect(tester.widget<IconButton>(_reloadIconButton).onPressed, isNotNull);
    });

    testWidgets('a reload that ends after leaving the lobby still reports',
        (tester) async {
      final (fakeApi, router) = await _pumpLobby(tester);
      final gate = Completer<void>();
      fakeApi.roomReloadGate = gate;
      await tester.tap(_reloadButton);
      await tester.pump();

      router.go('/elsewhere');
      await tester.pumpAndSettle();
      fakeApi.nextRoomReloadThrow =
          const ApiException(message: 'Conflict', statusCode: 409);
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Elsewhere'), findsOneWidget);
      expect(find.textContaining('Restart it'), findsOneWidget);
    });

    testWidgets('a reload ending elsewhere leaves that screen\'s message up',
        (tester) async {
      final (fakeApi, router) = await _pumpLobby(tester);
      final gate = Completer<void>();
      fakeApi.roomReloadGate = gate;
      await tester.tap(_reloadButton);
      await tester.pump();

      router.go('/elsewhere');
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(tester.element(find.text('Elsewhere')))
          .showSnackBar(const SnackBar(content: Text('Saved elsewhere')));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Saved elsewhere'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('localhost:8000: Room configs are already up to date'),
        findsOneWidget,
      );
    });

    testWidgets('a reload that throws instead of answering is still reported',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      await _pumpLobby(tester, reloadsFindServer: false);

      await tester.tap(_reloadButton);
      await tester.pumpAndSettle();

      expect(
        find.text('localhost:8000: Could not confirm the rooms were reloaded'),
        findsOneWidget,
      );
      final record = sink.records
          .where((r) => r.loggerName == 'soliplex.lobby_screen')
          .single;
      expect(record.level, LogLevel.error);
      expect(record.attributes['serverId'], 'local');
    });

    testWidgets('a lobby revisited mid-reload still shows it busy',
        (tester) async {
      final (fakeApi, router) = await _pumpLobby(tester);
      final gate = Completer<void>();
      fakeApi.roomReloadGate = gate;
      await tester.tap(_reloadButton);
      await tester.pump();

      router.go('/elsewhere');
      await tester.pumpAndSettle();
      router.go('/lobby');
      await tester.pump();
      await tester.pump();

      expect(tester.widget<IconButton>(_reloadIconButton).onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('roomReloadMessage', () {
    test('names each kind of change that happened', () {
      expect(
        roomReloadMessage(
          'Demo',
          const RoomsReloaded(
            RoomConfigsReloaded(
              added: ['a'],
              removed: ['b', 'c'],
              changed: ['d'],
            ),
          ),
        ),
        'Demo: Rooms reloaded: 1 added, 2 removed, 1 changed',
      );
    });

    test('says so when nothing changed', () {
      expect(
        roomReloadMessage('Demo', const RoomsReloaded(_noChange)),
        'Demo: Room configs are already up to date',
      );
    });

    test('says what each failure means for the administrator', () {
      expect(
        roomReloadMessage('Demo', const RoomReloadNeedsRestart()),
        'Demo: This server runs several workers and cannot reload rooms in place. '
        'Restart it to pick up room changes.',
      );
      expect(
        roomReloadMessage('Demo', const RoomReloadRefused()),
        'Demo: The server refused to reload rooms',
      );
      expect(
        roomReloadMessage('Demo', const RoomReloadSignedOut()),
        'Demo: Sign in again to reload rooms',
      );
      expect(
        roomReloadMessage('Demo', const RoomReloadUnsupported()),
        'Demo: This server cannot reload rooms. '
        'Restart it to pick up room changes.',
      );
      expect(
        roomReloadMessage('Demo', const RoomReloadUnreadable()),
        "Demo: The server's reply could not be read; "
        'the rooms may have been reloaded.',
      );
      expect(
        roomReloadMessage('Demo', const RoomReloadFailed()),
        'Demo: Could not confirm the rooms were reloaded',
      );
    });
  });
}
