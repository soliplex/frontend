import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/document_selections.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/test_server_entry.dart';

class _BlockingThreadsApi extends FakeSoliplexApi {
  final _completer = Completer<List<ThreadInfo>>();

  void completeThreads(List<ThreadInfo> threads) {
    if (!_completer.isCompleted) _completer.complete(threads);
  }

  @override
  Future<List<ThreadInfo>> getThreads(
    String roomId, {
    CancelToken? cancelToken,
  }) => _completer.future;
}

Widget _buildRouted({
  required ServerEntry entry,
  required AgentRuntimeManager runtimeManager,
  required RunRegistry registry,
  String roomId = 'room-1',
  String? threadId,
}) {
  final router = GoRouter(
    initialLocation:
        threadId != null
            ? '/room/${entry.alias}/$roomId/thread/$threadId'
            : '/room/${entry.alias}/$roomId',
    routes: [
      GoRoute(
        path: '/room/:alias/:roomId',
        builder:
            (ctx, state) => RoomScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              threadId: null,
              runtimeManager: runtimeManager,
              registry: registry,
              documentSelections: DocumentSelections(),
            ),
        routes: [
          GoRoute(
            path: 'thread/:threadId',
            builder:
                (ctx, state) => RoomScreen(
                  serverEntry: entry,
                  roomId: state.pathParameters['roomId']!,
                  threadId: state.pathParameters['threadId'],
                  runtimeManager: runtimeManager,
                  registry: registry,
                  documentSelections: DocumentSelections(),
                ),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  late FakeSoliplexApi api;
  late ServerEntry entry;
  late AgentRuntimeManager runtimeManager;
  late RunRegistry registry;

  setUp(() {
    api = FakeSoliplexApi();
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];
    api.nextThreadHistory = ThreadHistory(messages: const []);
    entry = createTestServerEntry(api: api);
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
    );
    registry = RunRegistry();
  });

  tearDown(() async {
    await runtimeManager.dispose();
    registry.dispose();
  });

  testWidgets('wide layout shows thread sidebar', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: RoomScreen(
          serverEntry: entry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          documentSelections: DocumentSelections(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test thread'), findsOneWidget);
  });

  testWidgets('narrow layout shows AppBar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: RoomScreen(
          serverEntry: entry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          documentSelections: DocumentSelections(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets(
    'narrow layout: tapping drawer icon opens drawer with thread list',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: 'room-1',
            threadId: null,
            runtimeManager: runtimeManager,
            registry: registry,
            documentSelections: DocumentSelections(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Test thread'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows RoomWelcome fallback when no thread selected', (
    tester,
  ) async {
    // No threads → auto-select never fires → no-thread content shown
    api.nextThreads = const [];
    api.nextRoom = Room(id: 'room-1', name: 'My Room');

    await tester.pumpWidget(
      MaterialApp(
        home: RoomScreen(
          serverEntry: entry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          documentSelections: DocumentSelections(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a thread'), findsOneWidget);
  });

  testWidgets('shows error banner after create thread failure', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.nextThreads = const [];
    api.nextCreateThreadError = Exception('network error');

    await tester.pumpWidget(
      MaterialApp(
        home: RoomScreen(
          serverEntry: entry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          documentSelections: DocumentSelections(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Thread'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('auto-selects first thread when threadId is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildRouted(
        entry: entry,
        runtimeManager: runtimeManager,
        registry: registry,
      ),
    );
    await tester.pumpAndSettle();

    // After auto-select, the thread name should be visible (loaded in sidebar
    // or message area)
    expect(find.text('Test thread'), findsWidgets);
  });

  testWidgets('shows loading indicator while threads are loading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final blockingApi = _BlockingThreadsApi();
    blockingApi.nextRoom = Room(id: 'room-1', name: 'My Room');
    blockingApi.nextThreadHistory = ThreadHistory(messages: const []);
    final blockingEntry = createTestServerEntry(api: blockingApi);

    await tester.pumpWidget(
      MaterialApp(
        home: RoomScreen(
          serverEntry: blockingEntry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          documentSelections: DocumentSelections(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    blockingApi.completeThreads(const []);
  });

  testWidgets('ChatInput is disabled during MessagesLoading', (tester) async {
    // Use a blocking API to keep thread history in loading state
    final blockingApi = _BlockingThreadsApi();
    blockingApi.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];
    final blockingEntry = createTestServerEntry(api: blockingApi);

    await tester.pumpWidget(
      MaterialApp(
        home: RoomScreen(
          serverEntry: blockingEntry,
          roomId: 'room-1',
          threadId: 'thread-1',
          runtimeManager: runtimeManager,
          registry: registry,
          documentSelections: DocumentSelections(),
        ),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);

    blockingApi.completeThreads(blockingApi.nextThreads!);
  });
}
