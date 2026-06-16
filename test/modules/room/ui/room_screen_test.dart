import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/document_selections.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_sidebar.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
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
  }) =>
      _completer.future;
}

/// Holds `room-1`'s document fetch open until [firstRoomDocuments] is
/// completed, while every other room resolves immediately to an empty corpus.
class _StaleDocumentsApi extends FakeSoliplexApi {
  final firstRoomDocuments = Completer<List<RagDocument>>();

  @override
  Future<List<RagDocument>> getDocuments(
    String roomId, {
    CancelToken? cancelToken,
  }) =>
      roomId == 'room-1' ? firstRoomDocuments.future : Future.value(const []);
}

/// A [FakeSoliplexApi] whose room-list fetch fails with an [AuthException],
/// exercising the rail's session-expiry funnel.
class _RoomsAuthErrorApi extends FakeSoliplexApi {
  @override
  Future<List<Room>> getRooms({CancelToken? cancelToken}) async {
    throw const AuthException(message: 'expired');
  }
}

Widget _buildRouted({
  required ServerEntry entry,
  required AgentRuntimeManager runtimeManager,
  required RunRegistry registry,
  required UploadTrackerRegistry uploadRegistry,
  String roomId = 'room-1',
  String? threadId,
}) {
  final router = GoRouter(
    initialLocation: threadId != null
        ? '/room/${entry.alias}/$roomId/thread/$threadId'
        : '/room/${entry.alias}/$roomId',
    routes: [
      GoRoute(
        path: '/room/:alias/:roomId',
        builder: (ctx, state) => RoomScreen(
          serverEntry: entry,
          roomId: state.pathParameters['roomId']!,
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
        routes: [
          GoRoute(
            path: 'thread/:threadId',
            builder: (ctx, state) => RoomScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              threadId: state.pathParameters['threadId'],
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          ),
          GoRoute(
            path: 'info',
            builder: (ctx, state) =>
                const Scaffold(body: Text('room info page')),
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
  late Signal<Map<String, ServerEntry>> servers;
  late UploadTrackerRegistry uploadRegistry;

  setUp(() {
    api = FakeSoliplexApi();
    // The room rail lists the server's rooms; give it something to load so it
    // doesn't sit in its error state during room-screen tests.
    api.nextRooms = [
      Room(id: 'room-1', name: 'Test Room'),
    ];
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
    servers = Signal({entry.serverId: entry});
    uploadRegistry = UploadTrackerRegistry(servers: servers);
  });

  tearDown(() async {
    await runtimeManager.dispose();
    registry.dispose();
    uploadRegistry.dispose();
    servers.dispose();
  });

  testWidgets('wide layout shows thread sidebar', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test thread'), findsOneWidget);
  });

  testWidgets('narrow layout shows AppBar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
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

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
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
  });

  testWidgets('narrow layout: drawer thread tile spinner appears and clears',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final key = (
      serverId: entry.serverId,
      roomId: 'room-1',
      threadId: 'thread-1',
    );
    final session = ManualAgentSession(key);
    registry.register(key, session);
    await tester.pump();

    final spinnerInDrawer = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinnerInDrawer, findsOneWidget);

    session.completeAsCancelled();
    await tester.pump();
    await tester.pump();

    expect(spinnerInDrawer, findsNothing);
  });

  testWidgets('wide layout: sidebar thread tile spinner appears and clears',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    final key = (
      serverId: entry.serverId,
      roomId: 'room-1',
      threadId: 'thread-1',
    );
    final session = ManualAgentSession(key);
    registry.register(key, session);
    await tester.pump();

    final spinnerInSidebar = find.descendant(
      of: find.byType(ThreadSidebar),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinnerInSidebar, findsOneWidget);

    session.completeAsCancelled();
    await tester.pump();
    await tester.pump();

    expect(spinnerInSidebar, findsNothing);
  });

  testWidgets('shows RoomWelcome fallback when no thread selected',
      (tester) async {
    // No threads → auto-select never fires → no-thread content shown
    api.nextThreads = const [];
    api.nextRoom = Room(id: 'room-1', name: 'My Room');

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Select a thread'), findsOneWidget);
  });

  testWidgets('shows error banner after create thread failure', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.nextThreads = const [];
    api.nextCreateThreadError = Exception('network error');

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Thread'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('auto-selects first thread when threadId is null',
      (tester) async {
    await tester.pumpWidget(_buildRouted(
      entry: entry,
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    ));
    await tester.pumpAndSettle();

    // After auto-select, the thread name should be visible (loaded in sidebar
    // or message area)
    expect(find.text('Test thread'), findsWidgets);
  });

  testWidgets('shows loading indicator while threads are loading',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final blockingApi = _BlockingThreadsApi();
    blockingApi.nextRoom = Room(id: 'room-1', name: 'My Room');
    blockingApi.nextThreadHistory = ThreadHistory(messages: const []);
    final blockingEntry = createTestServerEntry(api: blockingApi);

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: blockingEntry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    blockingApi.completeThreads(const []);
  });

  testWidgets('hides file chip when both room and thread scopes are empty',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.nextRoom = const Room(
      id: 'room-1',
      name: 'Attachable',
      enableAttachments: true,
    );
    api.nextThreads = const [];
    // nextRoomUploads / nextThreadUploads default to empty → the chip
    // must not render when both scopes are Loaded([]).

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    // The documents toggle only appears when a scope has files; its
    // absence confirms the empty-scope case hides it.
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
  });

  testWidgets(
      'expanded file panel omits the Thread section when thread scope is empty',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.nextRoom = const Room(
      id: 'room-1',
      name: 'Attachable',
      enableAttachments: true,
    );
    api.nextThreads = const [];
    api.nextRoomUploads = [
      FileUpload(
        filename: 'shared.pdf',
        url: Uri.parse('https://example.com/shared.pdf'),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the documents button to expand the file panel.
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();

    expect(find.text('ROOM'), findsOneWidget);
    expect(find.text('THREAD'), findsNothing,
        reason: 'empty thread scope should not render a Thread label');
    expect(find.text('shared.pdf'), findsOneWidget);
  });

  testWidgets('shows file chip when room has uploads', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.nextRoom = const Room(
      id: 'room-1',
      name: 'Attachable',
      enableAttachments: true,
    );
    api.nextThreads = const [];
    api.nextRoomUploads = [
      FileUpload(
        filename: 'shared.pdf',
        url: Uri.parse('https://example.com/shared.pdf'),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    // The count moved from a chip label to the button's tooltip.
    expect(find.byTooltip('1 room'), findsOneWidget);
  });

  testWidgets('chip shows error_outline when room uploads refresh fails',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    api.nextRoom = const Room(
      id: 'room-1',
      name: 'Attachable',
      enableAttachments: true,
    );
    api.nextThreads = const [];
    api.nextRoomUploadsError =
        const ApiException(statusCode: 500, message: 'boom');

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pumpAndSettle();

    // The chip leading icon should be error_outline (not the attach
    // icon) when the scope is UploadsFailed.
    expect(find.byIcon(Icons.error_outline), findsWidgets);
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

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: blockingEntry,
        roomId: 'room-1',
        threadId: 'thread-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        documentSelections: DocumentSelections(),
      ),
    ));
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);

    blockingApi.completeThreads(blockingApi.nextThreads!);
  });

  group('document filter button visibility', () {
    Future<void> pumpRoom(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: entry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          enableDocumentFilter: true,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('hidden when the room has no filterable documents',
        (tester) async {
      api.nextDocuments = const [];

      await pumpRoom(tester);

      expect(find.byTooltip('Filter documents'), findsNothing);
    });

    testWidgets('shown when the room has filterable documents', (tester) async {
      api.nextDocuments = const [RagDocument(id: '1', title: 'Report.pdf')];

      await pumpRoom(tester);

      expect(find.byTooltip('Filter documents'), findsOneWidget);
    });

    testWidgets(
        'shown when the document fetch fails so the affordance '
        'is not lost on a transient error', (tester) async {
      api.nextDocumentsError = Exception('network down');

      await pumpRoom(tester);

      expect(find.byTooltip('Filter documents'), findsOneWidget);
    });

    testWidgets(
        'a slow fetch from the previous room cannot reveal the button '
        'after switching to an empty room', (tester) async {
      final staleApi = _StaleDocumentsApi()
        ..nextThreads = const []
        ..nextThreadHistory = ThreadHistory(messages: const []);
      final staleEntry = createTestServerEntry(api: staleApi);

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Widget roomScreen(String roomId) => MaterialApp(
            home: RoomScreen(
              serverEntry: staleEntry,
              roomId: roomId,
              threadId: null,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              enableDocumentFilter: true,
              documentSelections: DocumentSelections(),
            ),
          );

      // room-1's fetch is in flight and held open by the completer.
      await tester.pumpWidget(roomScreen('room-1'));
      await tester.pumpAndSettle();

      // Switch to room-2, which resolves to an empty corpus.
      await tester.pumpWidget(roomScreen('room-2'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filter documents'), findsNothing);

      // room-1's now-stale fetch resolves with documents; it must not
      // resurrect the button for the empty room-2.
      staleApi.firstRoomDocuments
          .complete(const [RagDocument(id: '1', title: 'Report.pdf')]);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Filter documents'), findsNothing);
    });
  });

  group('rail account menu', () {
    FakeHttpClient profileClient(
      Map<String, dynamic> profile, {
      int statusCode = 200,
    }) =>
        FakeHttpClient()
          ..onRequest = (method, uri) async => HttpResponse(
                statusCode: statusCode,
                bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(profile))),
              );

    Future<void> pumpAuthedRoom(
      WidgetTester tester,
      FakeHttpClient httpClient,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authedEntry = createTestServerEntry(
        api: api,
        requiresAuth: true,
        auth: authInActiveSession(),
        httpClient: httpClient,
      );
      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: authedEntry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account & more'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the resolved name and email for a signed-in user',
        (tester) async {
      await pumpAuthedRoom(
        tester,
        profileClient({
          'given_name': 'Ada',
          'family_name': 'Lovelace',
          'email': 'ada@example.com',
        }),
      );

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
    });

    testWidgets('falls back to "Signed in" when the profile fetch errors',
        (tester) async {
      await pumpAuthedRoom(tester, profileClient(const {}, statusCode: 500));

      expect(find.text('Signed in'), findsOneWidget);
    });

    testWidgets('marks the session expired (Guest) on a 401', (tester) async {
      await pumpAuthedRoom(tester, profileClient(const {}, statusCode: 401));

      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets(
        'a slow identity fetch from the previous server cannot overwrite '
        'the current server identity', (tester) async {
      HttpResponse profileResponse(Map<String, dynamic> profile) =>
          HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(profile))),
          );

      final heldA = Completer<HttpResponse>();
      final entryA = createTestServerEntry(
        api: api,
        serverId: 'http://server-a:8000',
        requiresAuth: true,
        auth: authInActiveSession(),
        httpClient: FakeHttpClient()..onRequest = (_, __) => heldA.future,
      );
      final entryB = createTestServerEntry(
        api: api,
        serverId: 'http://server-b:8000',
        requiresAuth: true,
        auth: authInActiveSession(),
        httpClient: FakeHttpClient()
          ..onRequest = (_, __) async =>
              profileResponse({'given_name': 'Bob', 'family_name': 'Beta'}),
      );

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Widget roomScreen(ServerEntry e) => MaterialApp(
            home: RoomScreen(
              serverEntry: e,
              roomId: 'room-1',
              threadId: null,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );

      // Server A's identity fetch is in flight, held open.
      await tester.pumpWidget(roomScreen(entryA));
      await tester.pumpAndSettle();

      // Switch to server B, whose identity resolves immediately.
      await tester.pumpWidget(roomScreen(entryB));
      await tester.pumpAndSettle();

      // Server A's now-stale fetch resolves; it must not overwrite B's
      // identity.
      heldA.complete(
          profileResponse({'given_name': 'Alice', 'family_name': 'Alpha'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account & more'));
      await tester.pumpAndSettle();
      expect(find.text('Bob Beta'), findsOneWidget);
      expect(find.text('Alice Alpha'), findsNothing);
    });
  });

  group('rail rooms', () {
    Widget roomScreen(String roomId) => MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: roomId,
            threadId: null,
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        );

    testWidgets('are not refetched on an in-server room switch',
        (tester) async {
      await tester.pumpWidget(roomScreen('room-1'));
      await tester.pumpAndSettle();
      expect(api.getRoomsCallCount, 1);

      await tester.pumpWidget(roomScreen('room-2'));
      await tester.pumpAndSettle();
      expect(api.getRoomsCallCount, 1);
    });

    testWidgets('are refetched when the server changes', (tester) async {
      Widget roomScreenFor(ServerEntry e) => MaterialApp(
            home: RoomScreen(
              serverEntry: e,
              roomId: 'room-1',
              threadId: null,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );

      await tester.pumpWidget(roomScreenFor(
          createTestServerEntry(api: api, serverId: 'http://server-a:8000')));
      await tester.pumpAndSettle();
      expect(api.getRoomsCallCount, 1);

      await tester.pumpWidget(roomScreenFor(
          createTestServerEntry(api: api, serverId: 'http://server-b:8000')));
      await tester.pumpAndSettle();
      expect(api.getRoomsCallCount, 2);
    });

    testWidgets(
        'an auth failure funnels to the session without an error affordance',
        (tester) async {
      final auth = authInActiveSession();
      final authedEntry = createTestServerEntry(
        api: _RoomsAuthErrorApi()
          ..nextThreads = []
          ..nextThreadHistory = ThreadHistory(messages: const []),
        requiresAuth: true,
        auth: auth,
        httpClient: FakeHttpClient()
          ..onRequest = (_, __) async => HttpResponse(
                statusCode: 200,
                bodyBytes: Uint8List.fromList(utf8.encode('{}')),
              ),
      );

      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: authedEntry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      // Not pumpAndSettle: the rail's loading spinner never stops, since the
      // auth funnel deliberately leaves the rooms fetch in its loading state.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(auth.session.value, isA<ExpiredSession>());
      // The rail leaves the loading state in place rather than surfacing its
      // own retry affordance, so the route guard's redirect isn't pre-empted.
      expect(find.byTooltip('Failed to load rooms'), findsNothing);
    });
  });

  testWidgets('the room-info button navigates to the room info route',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_buildRouted(
      entry: entry,
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Room info'));
    await tester.pumpAndSettle();

    expect(find.text('room info page'), findsOneWidget);
  });
}
