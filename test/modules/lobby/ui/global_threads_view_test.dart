import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room, ThreadInfo;
import 'package:soliplex_client/soliplex_client.dart' show NotFoundException;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';

import '../../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

ThreadInfo _thread(String id, String roomId, {String? name}) => ThreadInfo(
      id: id,
      roomId: roomId,
      name: name ?? id,
      createdAt: DateTime.utc(2026),
    );

Widget _buildApp(
  ServerManager manager, {
  ApiResolver? apiResolver,
  void Function(String alias, String roomId, String threadId)? onThreadRoute,
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
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/room/:alias/:roomId',
        builder: (_, __) => const Scaffold(body: Text('Room')),
      ),
      GoRoute(
        path: '/room/:alias/:roomId/thread/:threadId',
        builder: (_, state) {
          onThreadRoute?.call(
            state.pathParameters['alias']!,
            state.pathParameters['roomId']!,
            state.pathParameters['threadId']!,
          );
          return const Scaffold(body: Text('Thread'));
        },
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

/// Seeds one connected server and pumps the lobby on a wide viewport.
Future<FakeSoliplexApi> _pumpLobby(
  WidgetTester tester, {
  required List<Room> rooms,
  required List<ThreadInfo> threads,
  Exception? threadsError,
  void Function(String alias, String roomId, String threadId)? onThreadRoute,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final manager = _createManager();
  manager.addServer(
    serverId: 'local',
    serverUrl: Uri.parse('http://localhost:8000'),
    requiresAuth: false,
  );

  final fakeApi = FakeSoliplexApi()
    ..nextRooms = rooms
    ..allThreads = threads
    ..nextAllThreadsError = threadsError;

  await tester.pumpWidget(
    _buildApp(
      manager,
      apiResolver: (_) => fakeApi,
      onThreadRoute: onThreadRoute,
    ),
  );
  await tester.pumpAndSettle();
  return fakeApi;
}

Future<void> _openThreadsTab(WidgetTester tester) async {
  await tester.tap(find.text('Threads'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('lobby threads tab', () {
    testWidgets('opens on the rooms tab', (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: const [],
      );

      expect(find.text('Rooms'), findsOneWidget);
      expect(find.text('Threads'), findsOneWidget);
      // The rooms filter belongs to the rooms tab, and it is showing.
      expect(find.text('Filter rooms'), findsOneWidget);
    });

    testWidgets('groups threads under a heading per room', (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Manuals'),
        ],
        threads: [
          _thread('t1', 'r1', name: 'Alpha'),
          _thread('t2', 'r1', name: 'Beta'),
          _thread('t3', 'r2', name: 'Gamma'),
        ],
      );
      await _openThreadsTab(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);

      // Room names come from the already-loaded room list, and each room
      // heads its block exactly once even though it holds two threads.
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Manuals'), findsOneWidget);
    });

    testWidgets('falls back to the room id when the name is unknown',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'ghost-room', name: 'Orphan')],
      );
      await _openThreadsTab(tester);

      expect(find.text('ghost-room'), findsOneWidget);
    });

    testWidgets('hides the rooms filter on the threads tab', (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1')],
      );
      await _openThreadsTab(tester);

      // Filtering and sorting apply to rooms, not to this listing.
      expect(find.text('Filter rooms'), findsNothing);
    });

    testWidgets('opens the room and thread that was tapped', (tester) async {
      String? alias;
      String? roomId;
      String? threadId;

      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        onThreadRoute: (a, r, t) {
          alias = a;
          roomId = r;
          threadId = t;
        },
      );
      await _openThreadsTab(tester);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(roomId, equals('r1'));
      expect(threadId, equals('t1'));
      expect(alias, isNotNull);
    });

    testWidgets('shows an empty state when there are no threads',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: const [],
      );
      await _openThreadsTab(tester);

      expect(find.text('No threads yet'), findsOneWidget);
    });

    testWidgets('explains that an older server cannot aggregate threads',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: const [],
        threadsError: const NotFoundException(message: 'no route'),
      );
      await _openThreadsTab(tester);

      // A 404 here is an old backend, not a fault: no retry is offered,
      // because retrying would 404 forever.
      expect(find.text('Threads need a newer server'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('offers a retry when the listing genuinely fails',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: const [],
        threadsError: Exception('boom'),
      );
      await _openThreadsTab(tester);

      expect(find.text('Could not load threads'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('fetches the next page when scrolled near the bottom',
        (tester) async {
      // More threads than one screen holds, so the listing has to page.
      final threads = [
        for (var i = 0; i < 60; i++)
          _thread('t$i', 'r1', name: 'Thread ${i.toString().padLeft(2, '0')}'),
      ];

      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: threads,
      );
      await _openThreadsTab(tester);

      expect(api.getAllThreadsCallCount, equals(1));

      await tester.drag(find.byType(ListView).last, const Offset(0, -4000));
      await tester.pumpAndSettle();

      // Reaching the end pulled the second page rather than stopping at 50.
      expect(api.getAllThreadsCallCount, greaterThan(1));
      expect(api.allThreadsCalls.last.offset, equals(50));
    });
  });
}
