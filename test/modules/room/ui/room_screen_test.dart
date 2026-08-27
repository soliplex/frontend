import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/unread_dot.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/document_selections.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_anchor_storage.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_classification.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_rail.dart';
import 'package:soliplex_frontend/src/modules/room/ui/upload_event_banner.dart';
import 'package:soliplex_frontend/src/shared/type_to_focus.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_sidebar.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_tile.dart';
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
  group('shouldFocusInputOnKey', () {
    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          timeStamp: Duration.zero,
        );

    bool shouldFocus(
      KeyEvent event, {
      bool meta = false,
      bool control = false,
      bool alt = false,
    }) =>
        shouldFocusInputOnKey(
          event,
          isMetaPressed: meta,
          isControlPressed: control,
          isAltPressed: alt,
        );

    test('a typed character pulls focus to the composer', () {
      expect(shouldFocus(down(LogicalKeyboardKey.keyA)), isTrue);
    });

    test('a bare shift press does not steal focus', () {
      // Shift is a modifier key, so pressing it alone is not typing — even
      // though it is not a command modifier (Shift+letter still types, covered
      // by the plain-character case above).
      expect(shouldFocus(down(LogicalKeyboardKey.shiftLeft)), isFalse);
    });

    test('a character with meta held does not steal focus', () {
      // e.g. Cmd+C / Cmd+A — must leave the transcript selection intact.
      expect(shouldFocus(down(LogicalKeyboardKey.keyC), meta: true), isFalse);
    });

    test('a character with control alone held does not steal focus', () {
      // e.g. Ctrl+C / Ctrl+A on Windows/Linux — must leave the selection.
      expect(
          shouldFocus(down(LogicalKeyboardKey.keyC), control: true), isFalse);
    });

    test('an AltGr (control+alt) character focuses the composer', () {
      // Windows synthesizes AltGr as Ctrl+Alt to compose special characters;
      // that composed keystroke must still focus-and-type, not read as a
      // shortcut.
      expect(
        shouldFocus(down(LogicalKeyboardKey.keyQ), control: true, alt: true),
        isTrue,
      );
    });

    test('a plain alt/option character focuses the composer', () {
      expect(shouldFocus(down(LogicalKeyboardKey.keyE), alt: true), isTrue);
    });

    test('a bare modifier key does not steal focus', () {
      // Pressing Cmd alone (before C) must not clear the selection.
      expect(shouldFocus(down(LogicalKeyboardKey.metaLeft)), isFalse);
    });

    test('a key-up event does not steal focus', () {
      expect(
        shouldFocus(
          KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
    });
  });

  group('shouldPasteIntoChatInputOnKey', () {
    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyV,
          logicalKey: key,
          timeStamp: Duration.zero,
        );

    KeyRepeatEvent repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.keyV,
          logicalKey: key,
          timeStamp: Duration.zero,
        );

    bool shouldPaste(
      KeyEvent event, {
      TargetPlatform platform = TargetPlatform.macOS,
      bool meta = false,
      bool control = false,
      bool alt = false,
      bool includeRepeats = false,
    }) =>
        shouldPasteIntoChatInputOnKey(
          event,
          platform: platform,
          isMetaPressed: meta,
          isControlPressed: control,
          isAltPressed: alt,
          includeRepeats: includeRepeats,
        );

    test('each platform pastes with its own command modifier', () {
      // Matching the chord Flutter binds for a focused field, so the composer
      // answers the same keystroke whether or not it has focus.
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        expect(
          shouldPaste(down(LogicalKeyboardKey.keyV),
              platform: platform, meta: true),
          isTrue,
          reason: '$platform pastes with meta',
        );
        expect(
          shouldPaste(down(LogicalKeyboardKey.keyV),
              platform: platform, control: true),
          isFalse,
          reason: '$platform reads control+V as scroll-page-down',
        );
      }
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.android,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          shouldPaste(down(LogicalKeyboardKey.keyV),
              platform: platform, control: true),
          isTrue,
          reason: '$platform pastes with control',
        );
        expect(
          shouldPaste(down(LogicalKeyboardKey.keyV),
              platform: platform, meta: true),
          isFalse,
          reason: '$platform leaves meta+V alone',
        );
      }
    });

    test('holding both command modifiers does not paste', () {
      // Neither platform's paste chord, so it belongs to whatever else answers
      // it — the composer reports a match handled, so it matches exactly.
      expect(
        shouldPaste(down(LogicalKeyboardKey.keyV), meta: true, control: true),
        isFalse,
      );
      expect(
        shouldPaste(down(LogicalKeyboardKey.keyV),
            platform: TargetPlatform.linux, meta: true, control: true),
        isFalse,
      );
    });

    test('control+alt+V does not paste', () {
      expect(
        shouldPaste(down(LogicalKeyboardKey.keyV),
            platform: TargetPlatform.linux, control: true, alt: true),
        isFalse,
      );
    });

    test('a bare V does not paste', () {
      expect(shouldPaste(down(LogicalKeyboardKey.keyV)), isFalse);
    });

    test('meta with another character does not paste', () {
      // Cmd+C and Cmd+A must stay with the transcript's selection.
      expect(shouldPaste(down(LogicalKeyboardKey.keyC), meta: true), isFalse);
      expect(shouldPaste(down(LogicalKeyboardKey.keyA), meta: true), isFalse);
    });

    test('a key-up event does not paste', () {
      expect(
        shouldPaste(
          KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyV,
            logicalKey: LogicalKeyboardKey.keyV,
            timeStamp: Duration.zero,
          ),
          meta: true,
        ),
        isFalse,
      );
    });

    test('a repeat claims no chord of its own', () {
      // Every repeat while the chord is held would otherwise start a clipboard
      // read of its own and pour the same text in again.
      expect(shouldPaste(repeat(LogicalKeyboardKey.keyV), meta: true), isFalse);
    });

    test('a repeat counts for a caller that asks for repeats', () {
      // Retiring a read in flight has to answer the same repeats the focused
      // field's own binding does, which is a broader set than this claims.
      expect(
        shouldPaste(
          repeat(LogicalKeyboardKey.keyV),
          meta: true,
          includeRepeats: true,
        ),
        isTrue,
      );
    });
  });

  group('insertPastedText', () {
    test('appends when the composer has never held a selection', () {
      // Where a TextEditingValue starts before anything places a caret in it.
      const value = TextEditingValue(
        text: 'draft',
        selection: TextSelection.collapsed(offset: -1),
      );

      final pasted = insertPastedText(value, ' pasted');

      expect(pasted.text, 'draft pasted');
      expect(pasted.selection, const TextSelection.collapsed(offset: 12));
    });

    test('appends when the selection outruns the text', () {
      // The offsets are non-negative, so the selection reads as valid, but
      // replaceRange would throw on them.
      const value = TextEditingValue(
        text: 'short',
        selection: TextSelection(baseOffset: 0, extentOffset: 99),
      );

      final pasted = insertPastedText(value, '!');

      expect(pasted.text, 'short!');
      expect(pasted.selection, const TextSelection.collapsed(offset: 6));
    });

    test('inserts at the caret', () {
      const value = TextEditingValue(
        text: 'ac',
        selection: TextSelection.collapsed(offset: 1),
      );

      final pasted = insertPastedText(value, 'b');

      expect(pasted.text, 'abc');
      expect(pasted.selection, const TextSelection.collapsed(offset: 2));
    });
  });

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
      servers: emptyServers(),
    );
    registry = RunRegistry(servers: emptyServers());
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

  group('server label in header', () {
    testWidgets('shows the server name beside the room name', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(id: 'room-1', name: 'General');
      final namedEntry = createTestServerEntry(api: api, name: 'Prod API');

      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: namedEntry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Prod API'), findsOneWidget);
    });

    testWidgets('falls back to the server address when the server is unnamed',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(id: 'room-1', name: 'General');
      // The default `entry` carries no name, so the header shows its address.

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

      // The `http(s)://` scheme is dropped in favour of a leading link glyph
      // (issue #485), so the address shows without its scheme.
      expect(find.text('test-server:8000'), findsOneWidget);
      expect(find.text('http://test-server:8000'), findsNothing);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets(
        'grows the toolbar so the title is not clipped at large '
        'text scale', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      // An OS text size past the point where the two-line title outgrows the
      // standard toolbar, which a fixed toolbar clips without warning.
      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      api.nextRoom = const Room(id: 'room-1', name: 'General');

      await tester.pumpWidget(MaterialApp(
        // The toolbar is sized from the app's own type scale; Material's
        // defaults are short enough that the title never outgrows the bar.
        theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
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

      Rect inAppBar(Finder matching) => tester.getRect(
          find.descendant(of: find.byType(AppBar), matching: matching));

      // Both ends of the title stay inside the bar. The toolbar centres an
      // oversized title, so it spills top and bottom at once.
      final appBarRect = tester.getRect(find.byType(AppBar));
      expect(inAppBar(find.text('General')).top,
          greaterThanOrEqualTo(appBarRect.top));
      expect(inAppBar(find.byIcon(Icons.link)).bottom,
          lessThanOrEqualTo(appBarRect.bottom));
      expect(inAppBar(find.text('test-server:8000')).bottom,
          lessThanOrEqualTo(appBarRect.bottom));
    });

    testWidgets(
        'narrow AppBar fits the stacked room and server title without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(id: 'room-1', name: 'General');
      final namedEntry = createTestServerEntry(api: api, name: 'Prod API');

      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: namedEntry,
          roomId: 'room-1',
          threadId: null,
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();

      // The two-line title sits in the fixed-height AppBar toolbar; both lines
      // must fit without a RenderFlex overflow.
      expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('General')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('Prod API')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('room header placement', () {
    Future<void> pumpRoom(
      WidgetTester tester, {
      required double width,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        theme: theme,
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
    }

    // The title assertions below count matches across the whole tree, which is
    // unambiguous only for a fixture like this one: the rail names its room
    // 'Test Room', and RoomWelcome prints the room name a second time for a
    // room carrying a welcome message, suggestions, or quizzes.
    testWidgets('narrow layout draws the room title once, in the AppBar',
        (tester) async {
      api.nextRoom = const Room(id: 'room-1', name: 'General');

      await pumpRoom(tester, width: 400);

      // One title in the whole tree — no in-page header repeating the AppBar's.
      expect(find.text('General'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('wide layout draws the room title once, in the in-page header',
        (tester) async {
      api.nextRoom = const Room(id: 'room-1', name: 'General');

      await pumpRoom(tester, width: 1200);

      // No AppBar on wide, so the in-page header is the sole title and the
      // info action is in the body.
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('General'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets(
        'narrow layout hoists the documents toggle into the AppBar, where it '
        'still opens the file panel', (tester) async {
      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Attachable',
        acceptsRoomUploads: true,
        acceptsThreadUploads: true,
      );
      api.nextThreads = const [];
      api.nextRoomUploads = [
        FileUpload(
          filename: 'shared.pdf',
          url: Uri.parse('https://example.com/shared.pdf'),
        ),
      ];

      // The narrowest supported width, where the two-line title and both
      // actions compete for the toolbar.
      await pumpRoom(tester, width: 320);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.folder_outlined),
        ),
        findsOneWidget,
      );

      // The toggle sits in the AppBar while the panel it opens renders in the
      // body column, so the tap has to carry across subtrees.
      await tester.tap(find.byIcon(Icons.folder_outlined));
      await tester.pumpAndSettle();

      expect(find.text('shared.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('confidentiality marking', () {
      // A deployment that configures markings; a stock build configures none,
      // which is what every other test in this file runs on.
      ThemeData markedTheme() => ThemeData(
            extensions: [
              ClassificationTheme(
                defaultId: 'restricted',
                levels: const [
                  ClassificationLevel(
                    id: 'restricted',
                    label: 'RESTRICTED',
                    background: Color(0xFFEEDDDD),
                    foreground: Color(0xFF441111),
                  ),
                ],
              ),
            ],
          );

      testWidgets(
          'narrow layout carries it under the AppBar and under the '
          'composer', (tester) async {
        api.nextRoom = const Room(id: 'room-1', name: 'General');

        await pumpRoom(tester, width: 400, theme: markedTheme());

        // Banded below the toolbar, not inside it: the marking is chrome of
        // its own, never competing with the room name for the bar's width.
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('RESTRICTED'),
          ),
          findsNothing,
        );
        expect(find.text('RESTRICTED'), findsOneWidget);
        expect(
          find.text('Information level is: RESTRICTED'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('wide layout carries it under the in-page header',
          (tester) async {
        api.nextRoom = const Room(id: 'room-1', name: 'General');

        await pumpRoom(tester, width: 1200, theme: markedTheme());

        // No AppBar on wide; the band sits under the in-page header instead.
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('RESTRICTED'), findsOneWidget);
        expect(
          find.text('Information level is: RESTRICTED'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      // The marking gets a row of its own so the header's width stays with
      // identification. Mounted in the title instead, a twelve-character
      // label starved the room name to zero width and overflowed the row at
      // both layouts' worst widths — invisible at the 400px the tests above
      // run at, which is why these two widths are pinned.
      for (final (width, layout) in [
        (320.0, 'narrowest phone'),
        (600.0, 'tablet breakpoint, where the chat pane is at its narrowest'),
      ]) {
        testWidgets(
            'a long marking leaves the room name legible at $width '
            '($layout)', (tester) async {
          const name = 'Quarterly Budget Planning';
          api.nextRoom = const Room(id: 'room-1', name: name);

          await pumpRoom(
            tester,
            width: width,
            theme: ThemeData(
              extensions: [
                ClassificationTheme(
                  defaultId: 'confidential',
                  levels: const [
                    ClassificationLevel(
                      id: 'confidential',
                      label: 'CONFIDENTIAL',
                      background: Color(0xFFEEDDDD),
                      foreground: Color(0xFF441111),
                    ),
                  ],
                ),
              ],
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('CONFIDENTIAL'), findsOneWidget);
          // Legible, not merely present: a name squeezed to a few characters
          // identifies nothing.
          expect(tester.getSize(find.text(name)).width, greaterThan(100));
        });
      }

      testWidgets('an unconfigured deployment gets neither', (tester) async {
        api.nextRoom = const Room(id: 'room-1', name: 'General');

        await pumpRoom(tester, width: 400);

        // The band is always mounted and collapses to nothing, so its size is
        // the assertion — `findsNothing` on it would pass for the wrong reason.
        expect(tester.getSize(find.byType(ChatClassificationBand)), Size.zero);
        expect(find.textContaining('Information level'), findsNothing);
      });
    });
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

    await tester.tap(find.text('New'));
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
      acceptsRoomUploads: true,
      acceptsThreadUploads: true,
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
      acceptsRoomUploads: true,
      acceptsThreadUploads: true,
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
      acceptsRoomUploads: true,
      acceptsThreadUploads: true,
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
      acceptsRoomUploads: true,
      acceptsThreadUploads: true,
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

  group('attachment detection', () {
    testWidgets(
        'the room scope renders when only threads '
        'accept uploads', (tester) async {
      // Records into the scope directly rather than through a pick: there is
      // no seam to drive the picker, so what this pins is the rendering gate,
      // not the routing into it. The routing is why the gate matters — a pick
      // made in the welcome composer is filed against the room scope, there
      // being no thread yet to route it to — and it has no coverage.
      //
      // The surface is the attached-files control and its panel, not the event
      // banner, which only reports transitions of uploads it saw start.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Plain',
        acceptsThreadUploads: true,
      );
      api.nextThreads = const [];

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

      uploadRegistry
          .trackerFor(entry: entry, roomId: 'room-1')
          .recordClientError(
            roomId: 'room-1',
            filename: 'notes.pdf',
            message: 'Could not read the file.',
          );
      await tester.pumpAndSettle();

      // The control reports the failure before it is opened, and opening it
      // names the file that failed.
      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pumpAndSettle();

      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('Could not read the file.'), findsOneWidget);
    });

    testWidgets('the attached-files panel closes with its last row',
        (tester) async {
      // The control that opens the panel is the only thing that closes it, and
      // it is withdrawn once neither scope has anything to show. Dismissing
      // the last row is the ordinary way to reach that, so a panel that
      // outlived the control would hold the viewport for the rest of the visit.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Plain',
        acceptsThreadUploads: true,
      );
      api.nextThreads = const [];

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

      uploadRegistry
          .trackerFor(entry: entry, roomId: 'room-1')
          .recordClientError(
            roomId: 'room-1',
            filename: 'notes.pdf',
            message: 'Could not read the file.',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('notes.pdf'), findsNothing);
      // The panel renders nothing of its own once both scopes are empty, so
      // its absence is only observable through its key.
      expect(find.byKey(filePanelKey), findsNothing);

      // And the ask lapsed with it. Left set, the flag would reopen the panel
      // over the conversation the moment anything landed in either scope —
      // taking 40% of the viewport with no tap behind it.
      uploadRegistry
          .trackerFor(entry: entry, roomId: 'room-1')
          .recordClientError(
            roomId: 'room-1',
            filename: 'later.pdf',
            message: 'Could not read the file.',
          );
      await tester.pumpAndSettle();

      expect(find.byKey(filePanelKey), findsNothing);
      // The control is back, so the user can still open it deliberately.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets(
        'the attached-files panel does not follow the user into '
        'another thread', (tester) async {
      // The panel is opened over one conversation, and the flag that holds it
      // open is not the panel. A scope fetched for the first time reads as
      // content while it loads, so a flag left set would pop a spinner over
      // the arriving thread and close again when the fetch landed.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Plain',
        acceptsThreadUploads: true,
      );
      api.nextThreads = const [];

      Widget screen(String? threadId) => MaterialApp(
            home: RoomScreen(
              serverEntry: entry,
              roomId: 'room-1',
              threadId: threadId,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );

      await tester.pumpWidget(screen(null));
      await tester.pumpAndSettle();

      uploadRegistry
          .trackerFor(entry: entry, roomId: 'room-1')
          .recordClientError(
            roomId: 'room-1',
            filename: 'notes.pdf',
            message: 'Could not read the file.',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pumpAndSettle();
      expect(find.byKey(filePanelKey), findsOneWidget);

      await tester.pumpWidget(screen('thread-1'));
      await tester.pump();

      expect(find.byKey(filePanelKey), findsNothing);
    });

    testWidgets('the thread view keeps the room-scope banner', (tester) async {
      // Inside a thread there is only one banner, and it subscribes to both
      // scopes. Gating it on the thread capability alone drops room-scope
      // events in a room that takes room uploads and not thread ones — the
      // shape the welcome view's banner comment reasons about, which does not
      // transfer here because that one subscribes to the room scope only.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(
        id: 'room-1',
        name: 'RoomUploadsOnly',
        acceptsRoomUploads: true,
      );
      api.nextThreads = const [];

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

      expect(find.byType(UploadEventBanner), findsOneWidget);
    });

    testWidgets('the room upload banner is wired into the welcome view',
        (tester) async {
      // Presence, deliberately: this pins that the banner is mounted at all.
      // The gate's other direction is unobservable — the banner reports only
      // transitions of uploads it saw start, and the sole producer of a
      // room-scope pending row is the room-info card, which is itself gated on
      // the room capability. So a room without it has nothing to show whether
      // the banner is mounted or not.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Plain',
        acceptsRoomUploads: true,
      );
      api.nextThreads = const [];

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

      expect(find.byType(UploadEventBanner), findsOneWidget);
    });

    testWidgets(
        'welcome composer hides attach when the room accepts no thread uploads',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Room capability on, thread capability off: the composer gate is
      // thread-scoped, so reading the room field would wrongly show attach.
      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Plain',
        acceptsRoomUploads: true,
      );
      api.nextThreads = const [];

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

      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('gives the composer a scope that changes with the thread',
        (tester) async {
      // ChatInput drops a pick that comes back after the conversation moved on
      // by comparing this value across the picker's await, and the composer
      // deliberately survives a thread change, so nothing else would catch it.
      // Supplying a constant here — or dropping the argument — puts one
      // thread's images into another with every test still green.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(id: 'room-1', name: 'Plain');
      api.nextThreads = const [];

      Future<Object?> scopeFor(String? threadId) async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: 'room-1',
            threadId: threadId,
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ));
        await tester.pumpAndSettle();
        return tester.widget<ChatInput>(find.byType(ChatInput)).composerScope;
      }

      final welcome = await scopeFor(null);
      final first = await scopeFor('thread-1');
      final second = await scopeFor('thread-2');

      expect(first, isNotNull, reason: 'a null scope never changes');
      expect(first, isNot(second));
      expect(first, isNot(welcome));
    });

    testWidgets(
        'welcome composer shows attach when the room accepts thread uploads',
        (tester) async {
      // The mirror of the hiding case above: room capability off, thread
      // capability on. The pair is what catches the two fields being swapped,
      // which either one alone would read as correct.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(
        id: 'room-1',
        name: 'Attachable',
        acceptsThreadUploads: true,
      );
      api.nextThreads = const [];

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

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
    });

    testWidgets('a room that accepts no uploads can still add an image',
        (tester) async {
      // An inline image travels in the message, not as a file uploaded to the
      // thread, so the affordance this room has no paperclip for must remain.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      api.nextRoom = const Room(id: 'room-1', name: 'Plain');
      api.nextThreads = const [];

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

      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byTooltip('Add image'), findsOneWidget);
    });
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

      final signedInEntry =
          createTestServerEntry(api: api, auth: authWithIdentity());

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: signedInEntry,
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

        final markers = await ThreadReadMarkerStorage.loadRoom(
          serverId: signedInEntry.serverId,
          userId: testUserIdentity,
          roomId: 'room-1',
        );
        expect(markers['thread-1'], leave);
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

      final signedInEntry =
          createTestServerEntry(api: api, auth: authWithIdentity());

      Widget roomScreen(String roomId) => MaterialApp(
            home: RoomScreen(
              serverEntry: signedInEntry,
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

        final markers = await ThreadReadMarkerStorage.loadRoom(
          serverId: signedInEntry.serverId,
          userId: testUserIdentity,
          roomId: 'room-1',
        );
        expect(markers['thread-1'], leave);
      });
    });

    testWidgets(
        'a server switch stamps the left server under its own user, not the '
        'incoming one', (tester) async {
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

      const serverA = 'http://server-a:8000';
      final entryAlice = createTestServerEntry(
        api: api,
        serverId: serverA,
        auth: authWithIdentity(sub: 'alice'),
      );
      final entryBob = createTestServerEntry(
        api: FakeSoliplexApi(),
        serverId: 'http://server-b:8000',
        auth: authWithIdentity(sub: 'bob'),
      );

      Widget roomScreen(ServerEntry e) => MaterialApp(
            home: RoomScreen(
              serverEntry: e,
              roomId: 'room-1',
              threadId: 'thread-1',
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(roomScreen(entryAlice));
        await tester.pumpAndSettle();

        // Switch servers (alice -> bob) in place. The left server's stamp must
        // be filed under alice, never bob — reading userId off the (advanced)
        // widget at flush time would misfile it under bob.
        now = leave;
        await tester.pumpWidget(roomScreen(entryBob));
        await tester.pumpAndSettle();

        expect(
          await ThreadReadMarkerStorage.loadRoom(
            serverId: serverA,
            userId: testIdentityFor('alice'),
            roomId: 'room-1',
          ),
          containsPair('thread-1', leave),
        );
        expect(
          await ThreadReadMarkerStorage.loadRoom(
            serverId: serverA,
            userId: testIdentityFor('bob'),
            roomId: 'room-1',
          ),
          isEmpty,
        );
      });
    });

    testWidgets(
        'an unauthenticated server persists read state to the shared bucket',
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

      // The default entry has no signed-in user (currentUserId == null) — a
      // server requiring no sign-in. Its read state must still persist, under
      // the shared unauthenticated bucket, rather than being silently dropped.
      final anonEntry = createTestServerEntry(api: api);

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: anonEntry,
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

        final markers = await ThreadReadMarkerStorage.loadRoom(
          serverId: anonEntry.serverId,
          userId: null,
          roomId: 'room-1',
        );
        expect(markers['thread-1'], leave);
      });
    });

    testWidgets(
        'a logout while in a room stamps the open thread under the logged-in '
        'user, not the unauthenticated bucket', (tester) async {
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

      final aliceEntry =
          createTestServerEntry(api: api, auth: authWithIdentity(sub: 'alice'));

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: aliceEntry,
            roomId: 'room-1',
            threadId: 'thread-1',
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ));
        await tester.pumpAndSettle();

        // Log out while the room is still mounted, then let it dispose. The
        // dispose stamp must use the userId captured at tracker creation
        // (alice), not the now-null live session — otherwise alice's read state
        // leaks into the shared unauthenticated bucket.
        now = leave;
        aliceEntry.auth.logout();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        expect(
          await ThreadReadMarkerStorage.loadRoom(
            serverId: aliceEntry.serverId,
            userId: testIdentityFor('alice'),
            roomId: 'room-1',
          ),
          containsPair('thread-1', leave),
        );
        expect(
          await ThreadReadMarkerStorage.loadRoom(
            serverId: aliceEntry.serverId,
            userId: null,
            roomId: 'room-1',
          ),
          isEmpty,
        );
      });
    });
  });

  group('thread disappearance pruning', () {
    // Opens a thread tile's overflow menu, taps Delete, and confirms the dialog.
    Future<void> deleteViaMenu(WidgetTester tester, Finder menu) async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete')); // overflow-menu item
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last); // confirm-dialog action
      await tester.pumpAndSettle();
    }

    testWidgets(
        'deleting the open thread does not re-stamp it read on the way out',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];

      // Routed, because deleting the open thread navigates off it.
      await tester.pumpWidget(_buildRouted(
        entry: entry,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        threadId: 'thread-1',
      ));
      await tester.pumpAndSettle();

      // Deleting the open thread leaves it. The exit re-stamp must skip the
      // just-deleted thread, or it writes an orphan "read" marker for a thread
      // that no longer exists.
      await deleteViaMenu(
        tester,
        find.descendant(
          of: find.byType(ThreadSidebar),
          matching: find.byIcon(Icons.more_vert),
        ),
      );

      expect(
        await ThreadReadMarkerStorage.loadRoom(
          serverId: entry.serverId,
          userId: null,
          roomId: 'room-1',
        ),
        isEmpty,
      );
    });

    testWidgets(
        'deleting a thread sweeps its stored markers and anchors, sparing '
        'the sibling', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      final signedInEntry =
          createTestServerEntry(api: api, auth: authWithIdentity());
      final seen = DateTime.utc(2026, 6, 1);
      // thread-1 (the delete target) and thread-3 (an untouched sibling) carry
      // stored read state; thread-2 is only there to stay open, so deleting
      // thread-1 does not navigate.
      await ThreadReadMarkerStorage.saveRoom(
        serverId: signedInEntry.serverId,
        userId: testUserIdentity,
        roomId: 'room-1',
        markers: {'thread-1': seen, 'thread-3': seen},
      );
      await ThreadAnchorStorage.saveRoom(
        serverId: signedInEntry.serverId,
        userId: testUserIdentity,
        roomId: 'room-1',
        anchors: {'thread-1': 'm1', 'thread-3': 'm3'},
      );

      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 3),
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Second thread',
          createdAt: DateTime(2026, 3, 2),
        ),
        ThreadInfo(
          id: 'thread-3',
          roomId: 'room-1',
          name: 'Third thread',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: signedInEntry,
          roomId: 'room-1',
          threadId: 'thread-2',
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();

      // Delete the non-open thread-1 from the sidebar (no navigation follows,
      // since thread-2 stays the active thread).
      await deleteViaMenu(
        tester,
        find.descendant(
          of: find.ancestor(
            of: find.text('First thread'),
            matching: find.byType(ThreadTile),
          ),
          matching: find.byIcon(Icons.more_vert),
        ),
      );

      final markers = await ThreadReadMarkerStorage.loadRoom(
        serverId: signedInEntry.serverId,
        userId: testUserIdentity,
        roomId: 'room-1',
      );
      expect(markers.containsKey('thread-1'), isFalse);
      expect(markers['thread-3'], seen);

      final anchors = await ThreadAnchorStorage.loadRoom(
        serverId: signedInEntry.serverId,
        userId: testUserIdentity,
        roomId: 'room-1',
      );
      expect(anchors.containsKey('thread-1'), isFalse);
      expect(anchors['thread-3'], 'm3');
    });

    testWidgets(
        'a thread absent from the first load is not pruned (no baseline)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues(const {});

      final seen = DateTime.utc(2026, 6, 1);
      // thread-9 has stored read state but is not in the room's first thread
      // list. With no prior baseline to diff against, a cold load must never
      // read its absence as a deletion and prune it.
      await ThreadReadMarkerStorage.saveRoom(
        serverId: entry.serverId,
        userId: null,
        roomId: 'room-1',
        markers: {'thread-9': seen},
      );
      await ThreadAnchorStorage.saveRoom(
        serverId: entry.serverId,
        userId: null,
        roomId: 'room-1',
        anchors: {'thread-9': 'm9'},
      );

      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First thread',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];

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

      // thread-9 survives the cold load untouched (opening thread-1 may stamp
      // its own marker, which is fine — the point is thread-9 is not pruned).
      final markers = await ThreadReadMarkerStorage.loadRoom(
          serverId: entry.serverId, userId: null, roomId: 'room-1');
      expect(markers['thread-9'], seen);
      final anchors = await ThreadAnchorStorage.loadRoom(
          serverId: entry.serverId, userId: null, roomId: 'room-1');
      expect(anchors['thread-9'], 'm9');
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

        final markers = await LobbyReadMarkerStorage.loadServer(
            serverId: entry.serverId, userId: null);
        expect(markers['room-1'], leave);
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

        final markers = await LobbyReadMarkerStorage.loadServer(
            serverId: entry.serverId, userId: null);
        expect(markers['room-1'], isNull);
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

      // Signed in: the left room's marker must persist under the user's bucket,
      // not the unauthenticated one — the room-screen captures the identity at
      // open and files the leave stamp against it.
      final authedEntry =
          createTestServerEntry(api: api, auth: authWithIdentity());

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
              serverEntry: authedEntry,
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

        final markers = await LobbyReadMarkerStorage.loadServer(
            serverId: authedEntry.serverId, userId: testUserIdentity);
        expect(markers['room-1'], leave);
      });
    });

    testWidgets(
        'a logout while in a room stamps the left room under the logged-in '
        'user, not the unauthenticated bucket', (tester) async {
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

      final aliceEntry =
          createTestServerEntry(api: api, auth: authWithIdentity(sub: 'alice'));

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(MaterialApp(
          home: RoomScreen(
            serverEntry: aliceEntry,
            roomId: 'room-1',
            threadId: 'thread-1',
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ));
        await tester.pumpAndSettle();

        // Log out while mounted, then let the screen dispose. The room-level
        // leave stamp (which the lobby reads) must file under alice, captured
        // at open, not the now-null live session.
        now = leave;
        aliceEntry.auth.logout();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        expect(
          await LobbyReadMarkerStorage.loadServer(
              serverId: aliceEntry.serverId, userId: testIdentityFor('alice')),
          containsPair('room-1', leave),
        );
        expect(
          await LobbyReadMarkerStorage.loadServer(
              serverId: aliceEntry.serverId, userId: null),
          isEmpty,
        );
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

  group('paste into the unfocused composer', () {
    /// Declares a test that presses a chord on [platform], which decides which
    /// chord the screen reads as paste. Defaults to a platform that pastes with
    /// meta, since that is the modifier [sendChord] holds.
    ///
    /// The override has to be undone inside the body — the test binding checks
    /// the foundation debug variables before any `tearDown` runs.
    void testChord(
      String description,
      Future<void> Function(WidgetTester) body, {
      TargetPlatform platform = TargetPlatform.macOS,
    }) {
      testWidgets(description, (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    /// Answers `Clipboard.getData` with whatever [respond] returns. Throwing
    /// from [respond] stands in for a platform that refuses the read.
    void mockClipboard(FutureOr<Object?> Function() respond) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return await respond();
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
    }

    void mockClipboardText(String text) =>
        mockClipboard(() => <String, Object?>{'text': text});

    /// A thread still loading its messages, and a thread streaming a run, both
    /// animate a spinner forever, so `settle: false` callers drain a couple of
    /// frames instead of waiting for quiet.
    Future<void> drainFrames(WidgetTester tester,
        {required bool settle}) async {
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    /// Holds [modifier] down over [key]. Reports whether anything claimed the
    /// [key] press, which is what decides between the composer acting on a
    /// chord and the platform keeping its own meaning for it.
    Future<bool> sendChord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey modifier = LogicalKeyboardKey.metaLeft,
    }) async {
      await tester.sendKeyDownEvent(modifier);
      final claimed = await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(modifier);
      return claimed;
    }

    Future<bool> pressChord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey modifier = LogicalKeyboardKey.metaLeft,
      bool settle = true,
    }) async {
      final claimed = await sendChord(tester, key, modifier: modifier);
      await drainFrames(tester, settle: settle);
      return claimed;
    }

    Future<TextField> pumpRoom(WidgetTester tester,
        {bool settle = true, Size? surfaceSize}) async {
      if (surfaceSize != null) {
        await tester.binding.setSurfaceSize(surfaceSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
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
      await drainFrames(tester, settle: settle);
      return tester.widget<TextField>(find.byType(TextField));
    }

    testChord('one paste chord focuses the composer and inserts the text',
        (tester) async {
      mockClipboardText('from the clipboard');
      final composer = await pumpRoom(tester);
      expect(composer.focusNode!.hasFocus, isFalse);

      final claimed = await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.focusNode!.hasFocus, isTrue);
      expect(composer.controller!.text, 'from the clipboard');
      // Claiming reports that the composer answered the chord, so nothing else
      // treats it as unhandled. On web it also suppresses the browser's own
      // paste, which would otherwise add a second copy.
      expect(claimed, isTrue);
    });

    testChord('control+V pastes on a platform that pastes with control',
        (tester) async {
      // The screen reads each modifier off the keyboard separately and hands
      // them to the predicate; only pressing the chord proves control reaches
      // it, and with it every non-Apple platform.
      mockClipboardText('from the clipboard');
      final composer = await pumpRoom(tester);

      await pressChord(tester, LogicalKeyboardKey.keyV,
          modifier: LogicalKeyboardKey.controlLeft);

      expect(composer.controller!.text, 'from the clipboard');
    }, platform: TargetPlatform.linux);

    testChord(
        'pastes over the composer selection, keeping the rest of the '
        'draft', (tester) async {
      mockClipboardText('take');
      final composer = await pumpRoom(tester);
      composer.controller!.value = const TextEditingValue(
        text: 'keep drop keep',
        selection: TextSelection(baseOffset: 5, extentOffset: 9),
      );

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, 'keep take keep');
      expect(
        composer.controller!.selection,
        const TextSelection.collapsed(offset: 9),
      );
    });

    testChord('copy leaves the composer unfocused and empty', (tester) async {
      mockClipboardText('from the clipboard');
      final composer = await pumpRoom(tester);

      await pressChord(tester, LogicalKeyboardKey.keyC);

      expect(composer.focusNode!.hasFocus, isFalse);
      expect(composer.controller!.text, isEmpty);
    });

    testChord('a dialog above the room keeps the chord', (tester) async {
      // Whatever the dialog puts in front of the user owns the keyboard. Text
      // routed into the draft behind it would land where the caret is not, and
      // the dialog's own field would come up empty.
      mockClipboardText('from the clipboard');
      final composer = await pumpRoom(tester);
      unawaited(showDialog<void>(
        context: tester.element(find.byType(RoomScreen)),
        builder: (_) => const AlertDialog(content: Text('above the room')),
      ));
      await tester.pumpAndSettle();

      final claimed = await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(claimed, isFalse);
      expect(composer.controller!.text, isEmpty);
      expect(composer.focusNode!.hasFocus, isFalse);
    });

    testChord(
        'a thread still loading its messages takes neither the text '
        'nor the chord', (tester) async {
      mockClipboardText('from the clipboard');
      final blockingApi = _BlockingThreadsApi();
      blockingApi.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'Test thread',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: createTestServerEntry(api: blockingApi),
          roomId: 'room-1',
          threadId: 'thread-1',
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pump();
      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.readOnly, isTrue);

      final claimed =
          await pressChord(tester, LogicalKeyboardKey.keyV, settle: false);

      expect(composer.controller!.text, isEmpty);
      expect(composer.focusNode!.hasFocus, isFalse);
      expect(claimed, isFalse);

      blockingApi.completeThreads(blockingApi.nextThreads!);
    });

    testChord('a run in flight takes neither the text nor the chord',
        (tester) async {
      mockClipboardText('from the clipboard');
      api.nextThreads = const [];
      final key =
          (serverId: entry.serverId, roomId: 'room-1', threadId: 'thread-1');
      final session = ManualAgentSession(key);
      registry.register(key, session);
      final composer = await pumpRoom(tester, settle: false);

      // A RunningState loads the messages and marks the run live in one step,
      // so the composer is enabled and the run alone holds it read-only —
      // otherwise this could not tell the two halves of the guard apart.
      session.emit(RunningState(
        threadKey: key,
        runId: 'run-1',
        conversation: Conversation(threadId: 'thread-1', messages: const []),
        streaming: const AwaitingText(),
      ));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

      final claimed =
          await pressChord(tester, LogicalKeyboardKey.keyV, settle: false);

      expect(composer.controller!.text, isEmpty);
      expect(composer.focusNode!.hasFocus, isFalse);
      expect(claimed, isFalse);
    });

    testChord('an image-only clipboard moves focus and inserts nothing',
        (tester) async {
      mockClipboard(() => null);
      final composer = await pumpRoom(tester);
      composer.controller!.text = 'draft';

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.focusNode!.hasFocus, isTrue);
      expect(composer.controller!.text, 'draft');
    });

    testChord('an empty clipboard leaves a selected draft in place',
        (tester) async {
      // Pasting nothing over a selection would delete it. The clipboard is the
      // one place that text could have come from, so there is nothing to
      // replace it with and the selection stands.
      mockClipboardText('');
      final composer = await pumpRoom(tester);
      composer.controller!.value = const TextEditingValue(
        text: 'keep drop keep',
        selection: TextSelection(baseOffset: 5, extentOffset: 9),
      );

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, 'keep drop keep');
    });

    testChord('a refused clipboard read leaves the draft alone',
        (tester) async {
      // A browser withholding `readText` is a steady state the user meets on
      // every keypress, so it is reported below the error level, and carries the
      // code that separates it from a genuinely broken clipboard channel.
      final sink = _RecordingSink('soliplex_frontend.room_screen');
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      mockClipboard(
        () => throw PlatformException(code: 'paste_fail'),
      );
      final composer = await pumpRoom(tester);
      composer.controller!.text = 'draft';

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, 'draft');
      final refusal = sink.records.singleWhere(
        (r) => r.message.contains('refused a clipboard read'),
      );
      expect(refusal.level, LogLevel.warning);
      expect(refusal.attributes['code'], 'paste_fail');
    });

    testChord('a thread switch during the read drops the paste',
        (tester) async {
      final read = Completer<Map<String, Object?>>();
      mockClipboard(() => read.future);
      final composer = await pumpRoom(tester);

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();

      // The clipboard answers only after the user has moved on. The draft the
      // chord measured is gone, so its text must not land in the new one.
      await tester.pumpWidget(MaterialApp(
        home: RoomScreen(
          serverEntry: entry,
          roomId: 'room-1',
          threadId: 'thread-2',
          runtimeManager: runtimeManager,
          registry: registry,
          uploadRegistry: uploadRegistry,
          documentSelections: DocumentSelections(),
        ),
      ));
      await tester.pumpAndSettle();
      read.complete(<String, Object?>{'text': 'from the clipboard'});
      await tester.pumpAndSettle();

      expect(composer.controller!.text, isEmpty);
    });

    testChord('a dialog opened during the read drops the paste',
        (tester) async {
      // The chord was legal when it was pressed; by the time the clipboard
      // answers, a dialog owns the keyboard and its field is where the user is
      // typing. The draft behind it must not collect the text.
      final read = Completer<Map<String, Object?>>();
      mockClipboard(() => read.future);
      final composer = await pumpRoom(tester);

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      unawaited(showDialog<void>(
        context: tester.element(find.byType(RoomScreen)),
        builder: (_) => const AlertDialog(content: Text('above the room')),
      ));
      await tester.pumpAndSettle();
      read.complete(<String, Object?>{'text': 'from the clipboard'});
      await tester.pumpAndSettle();

      expect(composer.controller!.text, isEmpty);
    });

    testChord('leaving the room during the read throws nothing',
        (tester) async {
      // The composer's controller is disposed with the screen, and reading the
      // clipboard can outlast a consent prompt, so the paste has to notice the
      // screen is gone rather than write into a disposed controller.
      final read = Completer<Map<String, Object?>>();
      var reads = 0;
      mockClipboard(() {
        reads++;
        return read.future;
      });
      await pumpRoom(tester);

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      read.complete(<String, Object?>{'text': 'from the clipboard'});
      await tester.pumpAndSettle();

      // Without the read there is nothing to survive, so name it rather than
      // let the test pass for having done nothing.
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    });

    testChord('a focused composer pastes once, through the platform',
        (tester) async {
      // The screen abstains once the composer has focus, and that abstention is
      // load-bearing: claiming the chord does not stop the focused field's own
      // paste, so answering it here too would insert the clipboard twice.
      mockClipboardText('from the clipboard');
      final composer = await pumpRoom(tester);
      composer.focusNode!.requestFocus();
      await tester.pumpAndSettle();

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, 'from the clipboard');
    });

    testChord('a second chord during the read pastes once, not twice',
        (tester) async {
      // The first chord moves focus and leaves a read in flight, so the second
      // reaches the focused field and pastes through the platform. The read
      // still owed an answer must not insert the same clipboard again.
      final read = Completer<Map<String, Object?>>();
      mockClipboard(() => read.future);
      final composer = await pumpRoom(tester);

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(composer.focusNode!.hasFocus, isTrue);

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      read.complete(<String, Object?>{'text': 'from the clipboard'});
      await tester.pumpAndSettle();

      expect(composer.controller!.text, 'from the clipboard');
    });

    testChord('the open drawer keeps the chord and the clipboard out',
        (tester) async {
      // The drawer covers the composer without pushing a route, so the room
      // still reads as the current one. Text routed into the composer now would
      // land where the user cannot see it.
      mockClipboardText('from the clipboard');
      final composer =
          await pumpRoom(tester, surfaceSize: const Size(400, 800));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      final claimed = await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, isEmpty);
      expect(composer.focusNode!.hasFocus, isFalse);
      expect(claimed, isFalse);
    });

    testChord('a drawer opened during the read drops the paste',
        (tester) async {
      // Same obstacle arriving mid-read as the dialog case: by the time the
      // clipboard answers, the composer is behind the scrim.
      final read = Completer<Map<String, Object?>>();
      mockClipboard(() => read.future);
      final composer =
          await pumpRoom(tester, surfaceSize: const Size(400, 800));

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();

      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      read.complete(<String, Object?>{'text': 'from the clipboard'});
      await tester.pumpAndSettle();

      expect(composer.controller!.text, isEmpty);
    });

    testChord('widening away from an open drawer keeps the chord working',
        (tester) async {
      // The drawer only exists in the narrow layout, and its removal reports no
      // close. A guard that took the Scaffold's word for it would stay shut here
      // for the life of the screen.
      mockClipboardText('from the clipboard');
      final composer =
          await pumpRoom(tester, surfaceSize: const Size(400, 800));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpAndSettle();

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, 'from the clipboard');
    });

    testChord('the open drawer keeps plain typing out of the composer too',
        (tester) async {
      // Type-to-focus shares the guard the chord uses, so a composer behind the
      // scrim must not take focus from an ordinary keystroke either.
      final composer =
          await pumpRoom(tester, surfaceSize: const Size(400, 800));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();

      expect(composer.focusNode!.hasFocus, isFalse);
    });

    testChord('a drawer dragged shut lets the chord through again',
        (tester) async {
      // A drag that carries the drawer the whole way closed settles it without
      // running the close animation, so neither the drawer's own state nor the
      // route it borrows announces the close. Only whether the drawer is on
      // screen answers for this one.
      mockClipboardText('from the clipboard');
      final composer =
          await pumpRoom(tester, surfaceSize: const Size(400, 800));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      // Slowly, and ending at rest: a flick would settle it by animation
      // instead, which is the path that does announce itself.
      final gesture = await tester.startGesture(const Offset(150, 400));
      for (var i = 0; i < 14; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.controller!.text, 'from the clipboard');
    }, platform: TargetPlatform.iOS);

    testChord('a room with no thread yet takes the paste for its first message',
        (tester) async {
      // Opening a room and pasting straight into the welcome composer, before
      // any thread exists. The composer is enabled by the absence of a thread
      // rather than by a loaded one, and reads its session state from the room.
      mockClipboardText('from the clipboard');
      api.nextThreads = const [];
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
      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.focusNode!.hasFocus, isFalse);

      await pressChord(tester, LogicalKeyboardKey.keyV);

      expect(composer.focusNode!.hasFocus, isTrue);
      expect(composer.controller!.text, 'from the clipboard');
    });

    testChord('a room switch during the read drops the paste, threads or not',
        (tester) async {
      // Neither room has a thread, so the draft changes owner by the room alone.
      // Comparing the active thread would see null on both sides and let the
      // text land in a room the user never pasted into.
      final read = Completer<Map<String, Object?>>();
      mockClipboard(() => read.future);
      api.nextThreads = const [];
      Widget room(String id) => MaterialApp(
            home: RoomScreen(
              serverEntry: entry,
              roomId: id,
              threadId: null,
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploadRegistry,
              documentSelections: DocumentSelections(),
            ),
          );
      await tester.pumpWidget(room('room-1'));
      await tester.pumpAndSettle();

      await sendChord(tester, LogicalKeyboardKey.keyV);
      await tester.pump();

      await tester.pumpWidget(room('room-2'));
      await tester.pumpAndSettle();
      read.complete(<String, Object?>{'text': 'from the clipboard'});
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testChord('a repeat while the read is pending pastes once, not twice',
        (tester) async {
      // Holding the chord repeats, and Flutter's binding for a focused field
      // answers repeats with a paste of its own. The read the first press
      // started must stand down rather than insert on top of it.
      final firstRead = Completer<Map<String, Object?>>();
      var reads = 0;
      mockClipboard(
        () => reads++ == 0 ? firstRead.future : <String, Object?>{'text': 'X'},
      );
      final composer = await pumpRoom(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(composer.controller!.text, 'X',
          reason: 'the repeat pastes through the platform');

      firstRead.complete(<String, Object?>{'text': 'X'});
      await tester.pumpAndSettle();

      expect(composer.controller!.text, 'X');
    });
  });

  group('reporting a failed run', () {
    /// A thread whose transcript carries one failed run, with the runId the
    /// resolver needs on the preceding user message.
    void seedFailedRun() {
      api.nextThreadHistory = ThreadHistory(
        messages: [
          TextMessage(
            id: 'user-1',
            user: ChatUser.user,
            createdAt: DateTime(2026, 3, 1),
            text: 'summarise the report',
          ),
          NoResponseTile.failed(
            id: 'no-response-run-9',
            createdAt: DateTime(2026, 3, 1),
            thinkingText: 'thinking',
            errorDetail: 'upstream exploded',
          ),
        ],
        messageStates: {
          'user-1': MessageState(
            userMessageId: 'user-1',
            sourceReferences: const [],
            runId: 'run-9',
          ),
        },
      );
    }

    Future<void> openRoom(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          messageExpansionsProvider.overrideWithValue(MessageExpansions()),
        ],
        child: MaterialApp(
          home: RoomScreen(
            serverEntry: entry,
            roomId: 'room-1',
            threadId: 'thread-1',
            runtimeManager: runtimeManager,
            registry: registry,
            uploadRegistry: uploadRegistry,
            documentSelections: DocumentSelections(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// The dialog's field, not the composer's — both are on screen.
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    /// The transcript sliver places the tile far below the viewport, so the
    /// affordance has to be scrolled into view before it can be tapped.
    Future<void> tapReport(WidgetTester tester) async {
      final report = find.text('View or add a note');
      await tester.ensureVisible(report);
      await tester.pumpAndSettle();
      await tester.tap(report);
      await tester.pumpAndSettle();
    }

    testWidgets('files a thumbs-down against the run the tile names',
        (tester) async {
      // The whole wire, end to end: the timeline and tile forwards, the runId
      // the resolver supplied, and the polarity room_screen hard-codes. A
      // thumbs-up here would replace the auto-filed failure and drop the run
      // out of the triage queue this feature exists to fill.
      seedFailedRun();
      await openRoom(tester);

      await tapReport(tester);

      expect(
        api.requestedRunFeedback.single,
        (roomId: 'room-1', threadId: 'thread-1', runId: 'run-9'),
      );

      await tester.enterText(dialogField, 'it lost my attachment');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      final filed = api.submittedFeedback.single;
      expect(filed.roomId, 'room-1');
      expect(filed.threadId, 'thread-1');
      expect(filed.runId, 'run-9');
      expect(filed.feedback, FeedbackType.thumbsDown);
      expect(filed.reason, 'it lost my attachment');
      expect(find.text('Tell us why'), findsNothing);
    });

    testWidgets('prefills the note already on file', (tester) async {
      seedFailedRun();
      api.nextRunFeedback =
          const RunFeedback(reason: '[auto] Run failed: server error');
      await openRoom(tester);

      await tapReport(tester);

      // Submitting untouched sends back exactly what was on file, which is
      // what stops an edit from destroying the auto-filed record.
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(
        api.submittedFeedback.single.reason,
        '[auto] Run failed: server error',
      );
    });

    testWidgets('keeps the dialog open when the write is rejected',
        (tester) async {
      seedFailedRun();
      api.nextSubmitFeedbackError = const NetworkException(message: 'offline');
      await openRoom(tester);

      await tapReport(tester);
      await tester.enterText(dialogField, 'worth keeping');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.text('Tell us why'), findsOneWidget);
      expect(find.text('worth keeping'), findsOneWidget);
    });
  });
}

class _RecordingSink implements LogSink {
  _RecordingSink(this.loggerName);

  final String loggerName;
  final List<LogRecord> records = [];

  @override
  void write(LogRecord record) {
    if (record.loggerName == loggerName) records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
