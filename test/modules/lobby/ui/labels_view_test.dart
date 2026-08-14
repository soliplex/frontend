import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room;
import 'package:soliplex_client/soliplex_client.dart'
    show ApiException, NotFoundException, ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart' show soliplexLightTheme;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/labels_view.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';

import '../../../helpers/fakes.dart';

ThreadLabel _label(int id, String name, {int? usageCount}) => ThreadLabel(
      id: id,
      name: name,
      color: '#42D76D',
      usageCount: usageCount,
    );

ServerManager _createManager({required bool requiresAuth}) {
  final manager = ServerManager(
    authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
    clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
    storage: InMemoryServerStorage(),
  );
  manager.addServer(
    serverId: 'local',
    serverUrl: Uri.parse('http://localhost:8000'),
    requiresAuth: requiresAuth,
  );
  return manager;
}

Widget _buildApp(ServerManager manager, {ApiResolver? apiResolver}) {
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
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('H'))),
      GoRoute(
        path: '/room/:alias/:roomId',
        builder: (_, __) => const Scaffold(body: Text('Room')),
      ),
      GoRoute(
        path: '/room/:alias/:roomId/thread/:threadId',
        builder: (_, __) => const Scaffold(body: Text('Thread')),
      ),
    ],
  );
  // Matches production: the branded chips read their palette from the
  // Soliplex ThemeData extension.
  return ProviderScope(
    child: MaterialApp.router(
      theme: soliplexLightTheme(),
      routerConfig: router,
    ),
  );
}

/// Pumps the lobby with one connected server.
///
/// [requiresAuth] false stands in for a server running with
/// authentication disabled, where there is no `/user_info` to read an
/// admin flag from and the only user is necessarily in charge.
Future<FakeSoliplexApi> _pumpLobby(
  WidgetTester tester, {
  required List<ThreadLabel> labels,
  bool requiresAuth = false,
  Exception? labelsError,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final manager = _createManager(requiresAuth: requiresAuth);
  final fakeApi = FakeSoliplexApi()
    ..nextRooms = const [Room(id: 'r1', name: 'General')]
    ..allThreads = const []
    ..labels = labels
    ..nextLabelsError = labelsError;

  await tester.pumpWidget(_buildApp(manager, apiResolver: (_) => fakeApi));
  await tester.pumpAndSettle();
  return fakeApi;
}

Future<void> _openLabelsTab(WidgetTester tester) async {
  await tester.tap(find.text('Labels'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('labels tab visibility', () {
    testWidgets('an administrator sees the tab', (tester) async {
      await _pumpLobby(tester, labels: [_label(1, 'Manuals')]);

      expect(find.text('Labels'), findsOneWidget);
    });

    testWidgets('a non-administrator has no labels tab at all', (tester) async {
      // Every control on the tab is an administrator action, so a
      // read-only version would be a tab of things you cannot do.
      await _pumpLobby(
        tester,
        labels: [_label(1, 'Manuals')],
        requiresAuth: true,
      );

      expect(find.text('Labels'), findsNothing);
      expect(find.text('Rooms'), findsOneWidget);
      expect(find.text('Threads'), findsOneWidget);
    });
  });

  group('labels tab', () {
    testWidgets('lists the catalogue as chips', (tester) async {
      await _pumpLobby(
        tester,
        labels: [_label(1, 'Manuals'), _label(2, 'Urgent')],
      );
      await _openLabelsTab(tester);

      expect(find.widgetWithText(LabelChip, 'Manuals'), findsOneWidget);
      expect(find.widgetWithText(LabelChip, 'Urgent'), findsOneWidget);
    });

    testWidgets('shows a usage count when the server sent one', (tester) async {
      await _pumpLobby(
        tester,
        labels: [_label(1, 'Manuals', usageCount: 3)],
      );
      await _openLabelsTab(tester);

      expect(find.text('3 threads'), findsOneWidget);
    });

    testWidgets('singularises a count of one', (tester) async {
      await _pumpLobby(
        tester,
        labels: [_label(1, 'Manuals', usageCount: 1)],
      );
      await _openLabelsTab(tester);

      expect(find.text('1 thread'), findsOneWidget);
    });

    testWidgets('shows no count when the server withheld it', (tester) async {
      // Absent is not zero — "0 threads" would present a destructive
      // delete as a harmless one.
      await _pumpLobby(tester, labels: [_label(1, 'Manuals')]);
      await _openLabelsTab(tester);

      expect(find.textContaining('thread'), findsNothing);
    });

    testWidgets('carries the create affordance as the first row', (
      tester,
    ) async {
      // A tile in the list, not a button in a bar above it — the server
      // sidebar's idiom. At the head rather than the tail, though: a
      // catalogue can run to hundreds of labels, and burying "new" under
      // all of them would mean scrolling the lot to add one.
      await _pumpLobby(
        tester,
        labels: [_label(1, 'Archived'), _label(2, 'Urgent')],
      );
      await _openLabelsTab(tester);

      // Inside the scrollable rather than pinned above it...
      final list = find.descendant(
        of: find.byType(LabelsView),
        matching: find.byType(ListView),
      );
      expect(
        find.descendant(of: list, matching: find.text('New label')),
        findsOneWidget,
      );

      // ...and above the first label rather than after the last.
      final tileY = tester.getTopLeft(find.text('New label')).dy;
      final firstChipY =
          tester.getTopLeft(find.widgetWithText(LabelChip, 'Archived')).dy;
      expect(tileY, lessThan(firstChipY));
    });

    testWidgets('offers creation from the empty state', (tester) async {
      await _pumpLobby(tester, labels: const []);
      await _openLabelsTab(tester);

      expect(find.text('No labels yet'), findsOneWidget);
      expect(find.text('New label'), findsOneWidget);
    });

    testWidgets('creates a label', (tester) async {
      final api = await _pumpLobby(tester, labels: const []);
      await _openLabelsTab(tester);

      await tester.tap(find.text('New label'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Manuals');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(api.createLabelCalls.single.name, equals('Manuals'));
      // Painted from the write response rather than a refetch.
      expect(find.widgetWithText(LabelChip, 'Manuals'), findsOneWidget);
    });

    testWidgets('reports a duplicate name inside the dialog', (tester) async {
      final api = await _pumpLobby(tester, labels: const []);
      api.nextCreateLabelError =
          const ApiException(message: 'HTTP 409', statusCode: 409);
      await _openLabelsTab(tester);

      await tester.tap(find.text('New label'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Manuals');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // The dialog stays open with the reason inline, rather than
      // closing and losing what was typed.
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('will not create a label with a blank name', (tester) async {
      final api = await _pumpLobby(tester, labels: const []);
      await _openLabelsTab(tester);

      await tester.tap(find.text('New label'));
      await tester.pumpAndSettle();

      // Nothing typed: submitting must be impossible rather than
      // producing a nameless chip.
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(api.createLabelCalls, isEmpty);
      // Still open, so nothing typed is lost.
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('renames a label', (tester) async {
      final api = await _pumpLobby(tester, labels: [_label(1, 'Manuals')]);
      await _openLabelsTab(tester);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Docs');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(api.updateLabelCalls.single.name, equals('Docs'));
      expect(find.widgetWithText(LabelChip, 'Docs'), findsOneWidget);
    });

    testWidgets('warns before deleting a label still in use', (tester) async {
      await _pumpLobby(
        tester,
        labels: [_label(1, 'Manuals', usageCount: 4)],
      );
      await _openLabelsTab(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // The row behind the dialog also shows "4 threads", so match the
      // dialog's own sentence rather than the count alone.
      expect(
        find.text('Delete "Manuals"? It is still on 4 threads.'),
        findsOneWidget,
      );
      // The count exists to warn; say plainly what survives.
      expect(
        find.text('The threads themselves are not deleted.'),
        findsOneWidget,
      );
    });

    testWidgets('deletes a label', (tester) async {
      final api = await _pumpLobby(tester, labels: [_label(1, 'Manuals')]);
      await _openLabelsTab(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(api.deleteLabelCalls, equals([1]));
      expect(find.widgetWithText(LabelChip, 'Manuals'), findsNothing);
    });

    testWidgets('explains that an older server has no labels', (tester) async {
      await _pumpLobby(
        tester,
        labels: const [],
        labelsError: const NotFoundException(message: 'no route'),
      );
      await _openLabelsTab(tester);

      expect(find.text('Labels need a newer server'), findsOneWidget);
      // No retry: it would 404 forever.
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('offers a retry when the catalogue genuinely fails',
        (tester) async {
      await _pumpLobby(
        tester,
        labels: const [],
        labelsError: Exception('boom'),
      );
      await _openLabelsTab(tester);

      expect(find.text('Could not load labels'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('hides the rooms filter on the labels tab', (tester) async {
      await _pumpLobby(tester, labels: [_label(1, 'Manuals')]);
      await _openLabelsTab(tester);

      expect(find.text('Filter rooms'), findsNothing);
    });
  });
}
