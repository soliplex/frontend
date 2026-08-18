import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room, ThreadInfo;
import 'package:soliplex_client/soliplex_client.dart'
    show NotFoundException, ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart'
    show SoliplexSpacing, soliplexLightTheme;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/global_threads_view.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/labels_view.dart'
    show LabelChip;
import 'package:soliplex_frontend/src/modules/lobby/ui/thread_search_field.dart'
    show kThreadSearchDebounce;
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
  // The real app runs under the Soliplex theme, and the branded chips
  // read their palette from its ThemeData extension — a bare MaterialApp
  // makes them throw, which is a test artefact rather than a bug.
  return ProviderScope(
    child: MaterialApp.router(
      theme: soliplexLightTheme(),
      routerConfig: router,
    ),
  );
}

/// Seeds one connected server and pumps the lobby on a wide viewport.
Future<FakeSoliplexApi> _pumpLobby(
  WidgetTester tester, {
  required List<Room> rooms,
  required List<ThreadInfo> threads,
  List<ThreadLabel> labels = const [],
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
    ..labels = labels
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

/// The overflow buttons belonging to thread rows.
///
/// Scoped to the listing because the server tiles in the sidebar carry
/// their own `more_vert`, and an unscoped finder matches those too.
Finder _threadMenus() => find.descendant(
      of: find.byType(GlobalThreadsView),
      matching: find.byIcon(Icons.more_vert),
    );

/// Opens the overflow menu on the [index]th thread row.
Future<void> _openThreadMenu(WidgetTester tester, {int index = 0}) async {
  await tester.tap(_threadMenus().at(index));
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

    testWidgets('every room rule spans the full pane width', (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [
          Room(id: 'r1', name: 'Ops'),
          Room(id: 'r2', name: 'A considerably longer room name'),
        ],
        threads: [
          _thread('t1', 'r1', name: 'Alpha'),
          _thread('t2', 'r2', name: 'Beta'),
        ],
      );
      await _openThreadsTab(tester);

      // Measure what was laid out, not what was declared. The rule used to
      // share a row with the room name, which handed it exactly half the
      // pane however short the name was — so it read as a stunted version
      // of the full-width rule under the server heading.
      final paneWidth = tester.getSize(find.byType(GlobalThreadsView)).width;
      final expected = paneWidth - SoliplexSpacing.s4 * 2;

      final rules = find
          .descendant(
            of: find.byType(GlobalThreadsView),
            matching: find.byType(Divider),
          )
          .evaluate()
          .map((element) => element.size!.width)
          .toList();

      expect(rules.length, equals(2));
      for (final width in rules) {
        expect(width, closeTo(expected, 0.01));
      }
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

    testWidgets('offers properties, rename and delete per thread',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
      );
      await _openThreadsTab(tester);

      await _openThreadMenu(tester);

      expect(find.text('Properties'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('renames a thread in place', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
      );
      await _openThreadsTab(tester);

      await _openThreadMenu(tester);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Renamed');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
      await tester.pumpAndSettle();

      expect(api.lastUpdatedName, equals('Renamed'));
      // Repainted from the write rather than a refetch.
      expect(find.text('Renamed'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('deletes a thread from the listing', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [
          _thread('t1', 'r1', name: 'Alpha'),
          _thread('t2', 'r1', name: 'Beta'),
        ],
      );
      await _openThreadsTab(tester);

      await _openThreadMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(api.lastDeletedThreadId, equals('t1'));
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('edits a thread\'s labels from its properties', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 1, name: 'Manuals', color: '#42D76D'),
          ThreadLabel(id: 2, name: 'Urgent', color: '#D93025'),
        ],
      );
      await _openThreadsTab(tester);

      await _openThreadMenu(tester);
      await tester.tap(find.text('Properties'));
      await tester.pumpAndSettle();

      // The whole catalogue is offered; tapping attaches.
      expect(find.text('Manuals'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
      await tester.tap(find.text('Manuals'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.setThreadLabelsCalls.single.labelIds, equals([1]));
      // Name and description travel together, because the metadata row
      // is replaced wholesale.
      expect(api.lastUpdatedName, equals('Alpha'));
      expect(api.lastUpdatedDescription, isNotNull);
    });

    testWidgets('says so when the server has no labels yet', (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
      );
      await _openThreadsTab(tester);

      await _openThreadMenu(tester);
      await tester.tap(find.text('Properties'));
      await tester.pumpAndSettle();

      expect(find.text('This server has no labels yet.'), findsOneWidget);
    });

    testWidgets('filters by name as you type', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [
          _thread('t1', 'r1', name: 'Osprey Manual'),
          _thread('t2', 'r1', name: 'Unrelated'),
        ],
      );
      await _openThreadsTab(tester);

      await tester.enterText(find.byType(TextField).last, 'osprey');
      // Past the debounce, so a word costs one request not five.
      await tester.pump(kThreadSearchDebounce);
      await tester.pumpAndSettle();

      expect(api.allThreadsCalls.last.query, equals('osprey'));
      expect(find.text('Osprey Manual'), findsOneWidget);
      expect(find.text('Unrelated'), findsNothing);
    });

    testWidgets('suggests labels for an in-progress @ token', (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 1, name: 'Manuals', color: '#42D76D'),
          ThreadLabel(id: 2, name: 'Urgent', color: '#D93025'),
        ],
      );
      await _openThreadsTab(tester);

      await tester.enterText(find.byType(TextField).last, '@man');
      await tester.pumpAndSettle();

      // Only the matching label is offered, and matching folds case.
      expect(find.widgetWithText(LabelChip, 'Manuals'), findsOneWidget);
      expect(find.widgetWithText(LabelChip, 'Urgent'), findsNothing);
    });

    testWidgets('completing a suggestion filters by that label',
        (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 7, name: 'Manuals', color: '#42D76D'),
        ],
      );
      await _openThreadsTab(tester);

      await tester.enterText(find.byType(TextField).last, '@man');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(LabelChip, 'Manuals'));
      await tester.pumpAndSettle();

      // The name resolves to its id — the wire filter is by id, and the
      // name is only ever for humans.
      expect(api.allThreadsCalls.last.labelIds, equals([7]));
      // The menu closes once a choice is made.
      expect(find.widgetWithText(LabelChip, 'Manuals'), findsNothing);
    });

    testWidgets('the field keeps focus while the menu is used', (tester) async {
      // The bug this pins: a suggestion that takes focus makes the field
      // lose it, and anything hiding the menu on focus loss unmounts the
      // row mid-tap — a menu you can see and cannot click.
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 7, name: 'Manuals', color: '#42D76D'),
        ],
      );
      await _openThreadsTab(tester);

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '@man');
      await tester.pumpAndSettle();

      final focusBefore = tester.widget<TextField>(field).focusNode;
      expect(focusBefore?.hasFocus, isTrue);

      await tester.tap(find.widgetWithText(LabelChip, 'Manuals'));
      await tester.pumpAndSettle();

      // Still focused, so typing continues where it left off.
      expect(focusBefore?.hasFocus, isTrue);
    });

    testWidgets('arrow keys move the highlight and Enter takes it',
        (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 1, name: 'Manual Alpha', color: '#42D76D'),
          ThreadLabel(id: 2, name: 'Manual Beta', color: '#D93025'),
        ],
      );
      await _openThreadsTab(tester);

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '@manual');
      await tester.pumpAndSettle();

      // Down then Enter takes the second, not the first — proving the
      // arrows reach the menu rather than moving the caret.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(api.allThreadsCalls.last.labelIds, equals([2]));
    });

    testWidgets('Tab accepts the highlighted suggestion', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 7, name: 'Manuals', color: '#42D76D'),
        ],
      );
      await _openThreadsTab(tester);

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '@man');
      await tester.pumpAndSettle();

      // Tab completes rather than moving focus out of the field.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(api.allThreadsCalls.last.labelIds, equals([7]));
      expect(find.widgetWithText(LabelChip, 'Manuals'), findsNothing);
    });

    testWidgets('Escape closes the menu without filtering', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 7, name: 'Manuals', color: '#42D76D'),
        ],
      );
      await _openThreadsTab(tester);
      final before = api.getAllThreadsCallCount;

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '@man');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(LabelChip, 'Manuals'), findsNothing);
      expect(api.getAllThreadsCallCount, equals(before));
    });

    testWidgets('completes a label whose name contains spaces', (tester) async {
      // The seeded catalogue really has names like this. Completing one
      // unquoted would round-trip as label "v22" plus the word "Osprey"
      // — a different query from the one that was picked, and one that
      // matches no label at all.
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 4, name: 'V22 Osprey', color: '#42BED7'),
        ],
      );
      await _openThreadsTab(tester);

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '@osp');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(LabelChip, 'V22 Osprey'));
      await tester.pumpAndSettle();

      expect(api.allThreadsCalls.last.labelIds, equals([4]));
      expect(find.text('No such label'), findsNothing);
    });

    testWidgets('does not suggest a label already in the query',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 1, name: 'Manuals', color: '#42D76D'),
        ],
      );
      await _openThreadsTab(tester);

      await tester.enterText(find.byType(TextField).last, '@manuals @man');
      await tester.pumpAndSettle();

      // Offering it twice would suggest a filter that changes nothing.
      expect(find.widgetWithText(LabelChip, 'Manuals'), findsNothing);
    });

    testWidgets('says so when a typed label does not exist', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
        labels: const [
          ThreadLabel(id: 1, name: 'Manuals', color: '#42D76D'),
        ],
      );
      await _openThreadsTab(tester);
      final before = api.getAllThreadsCallCount;

      await tester.enterText(find.byType(TextField).last, '@nonsense ');
      await tester.pump(kThreadSearchDebounce);
      await tester.pumpAndSettle();

      // An unresolvable name cannot be expressed as a filter — an empty
      // label list means *unfiltered* — so dropping it would silently
      // widen the listing to everything, the opposite of what was asked.
      expect(find.text('No such label'), findsOneWidget);
      // Names the offending token, rather than leaving the user to guess
      // which of several is wrong. (The search field also holds the text,
      // so match the message itself.)
      expect(
        find.text('@nonsense does not match any label on this server.'),
        findsOneWidget,
      );
      expect(api.getAllThreadsCallCount, equals(before));
    });

    testWidgets('distinguishes "nothing matched" from "no threads"',
        (tester) async {
      await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [_thread('t1', 'r1', name: 'Alpha')],
      );
      await _openThreadsTab(tester);

      await tester.enterText(find.byType(TextField).last, 'zzz-no-match');
      await tester.pump(kThreadSearchDebounce);
      await tester.pumpAndSettle();

      // Telling someone staring at their own search that "threads you
      // start show up here" would read as a bug.
      expect(find.text('No matching threads'), findsOneWidget);
      expect(find.text('No threads yet'), findsNothing);
    });

    testWidgets('clearing the search widens the listing again', (tester) async {
      final api = await _pumpLobby(
        tester,
        rooms: const [Room(id: 'r1', name: 'General')],
        threads: [
          _thread('t1', 'r1', name: 'Osprey Manual'),
          _thread('t2', 'r1', name: 'Unrelated'),
        ],
      );
      await _openThreadsTab(tester);

      await tester.enterText(find.byType(TextField).last, 'osprey');
      await tester.pump(kThreadSearchDebounce);
      await tester.pumpAndSettle();
      expect(find.text('Unrelated'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(api.allThreadsCalls.last.query, isEmpty);
      expect(find.text('Unrelated'), findsOneWidget);
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
