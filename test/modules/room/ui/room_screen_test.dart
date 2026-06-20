import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/unread_dot.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/document_selections.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_rail.dart';
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

/// A [FakeSoliplexApi] whose room-list fetch is denied with a 403, exercising
/// the rail's inline permission affordance (not a re-auth funnel or a retry).
class _RoomsPermissionDeniedApi extends FakeSoliplexApi {
  @override
  Future<List<Room>> getRooms({CancelToken? cancelToken}) async {
    throw const PermissionDeniedException(
        statusCode: 403, message: 'forbidden');
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

  testWidgets('a finished run elsewhere on the server refetches room activity',
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
    final before = api.getRoomsStatsCallCount;

    // A run finishes in another room on this server (a background reply). It
    // must refetch the activity batch so that room's rail dot lights even
    // though you've stayed in room-1.
    final key = (
      serverId: entry.serverId,
      roomId: 'room-2',
      threadId: 'thread-bg',
    );
    final session = ManualAgentSession(key);
    registry.register(key, session);
    session.completeAsCancelled();

    // The refetch is debounced; advance past the window.
    await tester.pump(const Duration(milliseconds: 350));

    expect(api.getRoomsStatsCallCount, before + 1);
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

    testWidgets('marks the session expired (Guest) on a thrown AuthException',
        (tester) async {
      // The raw decorator chain usually surfaces a 401 as a response, but a
      // thrown AuthException must funnel to the same session-expiry outcome.
      await pumpAuthedRoom(
        tester,
        FakeHttpClient()
          ..onRequest =
              (_, __) async => throw const AuthException(message: 'expired'),
      );

      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets('falls back to "Signed in" on a malformed 200 body',
        (tester) async {
      // A 200 whose body isn't a JSON object trips the decode/cast; it must be
      // caught and degrade to the generic label rather than crash the screen.
      await pumpAuthedRoom(
        tester,
        FakeHttpClient()
          ..onRequest = (_, __) async => HttpResponse(
                statusCode: 200,
                bodyBytes: Uint8List.fromList(utf8.encode('[1, 2, 3]')),
              ),
      );

      expect(find.text('Signed in'), findsOneWidget);
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

    testWidgets(
        'a permission denial surfaces inline without funneling to re-auth',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = authInActiveSession();
      final deniedEntry = createTestServerEntry(
        api: _RoomsPermissionDeniedApi()
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
          serverEntry: deniedEntry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();

      // A 403 is not an auth failure: the session stays active (no re-auth
      // funnel) and the rail shows a distinct, non-retryable affordance
      // rather than the generic "try again" error.
      expect(auth.session.value, isA<ActiveSession>());
      expect(
        find.byTooltip("You don't have permission to view rooms"),
        findsOneWidget,
      );
      expect(find.byTooltip('Failed to load rooms'), findsNothing);
    });

    testWidgets(
        'a slow rooms fetch from the previous server cannot overwrite the '
        'current server rooms', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final gateA = Completer<void>();
      final apiA = FakeSoliplexApi()
        ..nextRooms = [Room(id: 'a1', name: 'Xenon')]
        ..nextThreads = []
        ..nextThreadHistory = ThreadHistory(messages: const [])
        ..roomsGate = gateA;
      final apiB = FakeSoliplexApi()
        ..nextRooms = [Room(id: 'b1', name: 'Yttrium')]
        ..nextThreads = []
        ..nextThreadHistory = ThreadHistory(messages: const []);

      final entryA =
          createTestServerEntry(api: apiA, serverId: 'http://server-a:8000');
      final entryB =
          createTestServerEntry(api: apiB, serverId: 'http://server-b:8000');

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

      // Server A's rooms fetch is in flight, held open.
      await tester.pumpWidget(roomScreenFor(entryA));
      await tester.pump();

      // Switch to server B, whose rooms resolve immediately.
      await tester.pumpWidget(roomScreenFor(entryB));
      await tester.pumpAndSettle();

      // Server A's now-stale fetch resolves; it must not overwrite B's rooms.
      gateA.complete();
      await tester.pumpAndSettle();

      expect(find.text('Y'), findsOneWidget); // Yttrium
      expect(find.text('X'), findsNothing); // Xenon must not appear
    });
  });

  group('thread unread dot', () {
    Finder threadUnreadDots() => find.descendant(
          of: find.byType(ThreadSidebar),
          matching: find.byType(UnreadDot),
        );

    testWidgets(
        'leaving a thread clears the false unread dot for activity seen '
        'while it was open', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      final open = DateTime.utc(2026, 6, 1, 10);
      final activity = DateTime.utc(2026, 6, 1, 10, 0, 30);
      final leave = DateTime.utc(2026, 6, 1, 10, 1);
      var now = open;

      // thread-1's last activity is newer than the moment it is opened — a
      // reply that streamed in while it was the open thread.
      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: activity,
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Second thread',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(_buildRouted(
          entry: entry,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          threadId: 'thread-1',
        ));
        await tester.pumpAndSettle();

        // While thread-1 is open it is excluded from the unread set, so its
        // newer activity does not light a dot.
        expect(threadUnreadDots(), findsNothing);

        // Leave thread-1 for thread-2.
        now = leave;
        await tester.tap(find.text('Second thread'));
        await tester.pumpAndSettle();

        // thread-1 was read up to the activity that arrived while it was open,
        // so leaving it must not surface a false unread dot.
        expect(threadUnreadDots(), findsNothing);
      });
    });

    testWidgets('disposing stamps the open thread read as of now',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});

      final open = DateTime.utc(2026, 6, 1, 10);
      final leave = DateTime.utc(2026, 6, 1, 10, 1);
      var now = open;

      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 6, 1, 10, 0, 30),
        ),
      ];

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: 'room-1',
            threadId: 'thread-1',
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ));
        await tester.pumpAndSettle();

        // Leave the room entirely (back to the lobby) — the screen disposes.
        now = leave;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        final markers = await ThreadReadMarkerStorage.load();
        expect(
          markers[(
            serverId: entry.serverId,
            roomId: 'room-1',
            threadId: 'thread-1',
          )],
          leave,
        );
      });
    });

    testWidgets('switching rooms stamps the left room\'s open thread read',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      final open = DateTime.utc(2026, 6, 1, 10);
      final leave = DateTime.utc(2026, 6, 1, 10, 1);
      var now = open;

      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 6, 1, 10, 0, 30),
        ),
      ];

      Widget roomScreen(String roomId) => MaterialApp(
            home: RoomScreen(
              serverEntry: entry,
              roomId: roomId,
              threadId: roomId == 'room-1' ? 'thread-1' : null,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(roomScreen('room-1'));
        await tester.pumpAndSettle();

        // Switch to room-2 — the left room's open thread must be stamped under
        // room-1's coordinates, not the room we're entering.
        now = leave;
        await tester.pumpWidget(roomScreen('room-2'));
        await tester.pumpAndSettle();

        final markers = await ThreadReadMarkerStorage.load();
        expect(
          markers[(
            serverId: entry.serverId,
            roomId: 'room-1',
            threadId: 'thread-1',
          )],
          leave,
        );
      });
    });
  });

  group('room unread rollup', () {
    Finder railUnreadDots() => find.descendant(
          of: find.byType(RoomRail),
          matching: find.byType(UnreadDot),
        );

    testWidgets(
        'a room stays unread while a thread is unread, then clears once every '
        'thread is read', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      final activity = DateTime.utc(2026, 6, 1, 10, 0, 30);

      // thread-1 is the open thread (old, read). thread-2 has fresh activity
      // and no marker, so it is unread; the room must stay unread while it is.
      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 5, 1),
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Second thread',
          createdAt: DateTime(2026, 3, 1),
          lastActivity: activity,
        ),
      ];
      // The server's room-activity batch lights room-1's rail dot.
      api.roomsStats = {'room-1': RoomStats(lastActivity: activity)};

      // Stamp reads "now", past the activity, so opening the unread thread
      // resolves it.
      await withClock(Clock(() => DateTime.utc(2026, 6, 1, 11)), () async {
        await tester.pumpWidget(_buildRouted(
          entry: entry,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          threadId: 'thread-1',
        ));
        await tester.pumpAndSettle();

        // thread-2 is unread, so the room rolls up to unread: its rail dot lit.
        expect(railUnreadDots(), findsOneWidget);

        // Open thread-2 — the last unread thread. It reads as read, the rollup
        // recomputes, and the room is stamped read.
        await tester.tap(find.text('Second thread'));
        await tester.pumpAndSettle();

        expect(railUnreadDots(), findsNothing);
      });
    });

    testWidgets(
        'the open room does not light its own rail dot when only its own '
        'activity is newer than the marker', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      // A single open thread. The room-activity batch reports newer activity
      // than the room was stamped read from the thread list — the reply the
      // user just sent and is watching land. With no unread sibling thread,
      // the open room must not light its own rail dot.
      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 6, 1, 10),
        ),
      ];
      api.roomsStats = {
        'room-1': RoomStats(lastActivity: DateTime.utc(2026, 6, 1, 12)),
      };

      await withClock(Clock(() => DateTime.utc(2026, 6, 1, 11)), () async {
        await tester.pumpWidget(_buildRouted(
          entry: entry,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          threadId: 'thread-1',
        ));
        await tester.pumpAndSettle();

        expect(railUnreadDots(), findsNothing);
      });
    });

    testWidgets(
        'leaving the room marks it read so the lobby agrees the user caught up',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});

      final open = DateTime.utc(2026, 6, 1, 10);
      final leave = DateTime.utc(2026, 6, 1, 10, 1);
      var now = open;

      // A single thread whose activity (e.g. a message the user just sent) is
      // newer than the room was first marked read. The lobby reads the
      // room-level marker, so leaving must advance it past that activity.
      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 6, 1, 10, 0, 30),
        ),
      ];

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: 'room-1',
            threadId: 'thread-1',
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ));
        await tester.pumpAndSettle();

        // Leave to the lobby — the screen disposes.
        now = leave;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        final markers = await LobbyReadMarkerStorage.load();
        expect(markers[(serverId: entry.serverId, roomId: 'room-1')], leave);
      });
    });

    testWidgets(
        'leaving the room does not mark it read while a thread is unread',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});

      final open = DateTime.utc(2026, 6, 1, 10);
      final leave = DateTime.utc(2026, 6, 1, 10, 1);
      var now = open;

      // thread-1 is open (old, read). thread-2 has fresh activity and no
      // marker, so it is unread; leaving must not mark the room read over it.
      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 5, 1),
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Second thread',
          createdAt: DateTime(2026, 3, 1),
          lastActivity: DateTime.utc(2026, 6, 1, 10, 0, 30),
        ),
      ];

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: 'room-1',
            threadId: 'thread-1',
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ));
        await tester.pumpAndSettle();

        now = leave;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        final markers = await LobbyReadMarkerStorage.load();
        expect(markers[(serverId: entry.serverId, roomId: 'room-1')], isNull);
      });
    });

    testWidgets('switching rooms marks the left room read when caught up',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      final open = DateTime.utc(2026, 6, 1, 10);
      final leave = DateTime.utc(2026, 6, 1, 10, 1);
      var now = open;

      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 2),
          lastActivity: DateTime.utc(2026, 6, 1, 10, 0, 30),
        ),
      ];

      Widget roomScreen(String roomId) => MaterialApp(
            home: RoomScreen(
              serverEntry: entry,
              roomId: roomId,
              threadId: roomId == 'room-1' ? 'thread-1' : null,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(roomScreen('room-1'));
        await tester.pumpAndSettle();

        now = leave;
        await tester.pumpWidget(roomScreen('room-2'));
        await tester.pumpAndSettle();

        final markers = await LobbyReadMarkerStorage.load();
        expect(markers[(serverId: entry.serverId, roomId: 'room-1')], leave);
      });
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
