import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/shared/selectable_content.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_info_screen.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/test_server_entry.dart';

const _testRoom = Room(
  id: 'room-1',
  name: 'Test Room',
  description: 'A test room',
  allowMcp: true,
  acceptsRoomUploads: true,
  acceptsThreadUploads: true,
  agent: DefaultRoomAgent(
    id: 'agent-1',
    modelName: 'gpt-4o',
    providerType: 'openai',
    retries: 3,
    systemPrompt: 'You are a helpful assistant.',
  ),
  tools: {
    'search': RoomTool(
      name: 'search',
      description: 'Search the web',
      kind: 'bare',
    ),
  },
  mcpClientToolsets: {
    'stdio-tools': McpClientToolset(kind: 'stdio'),
  },
);

Widget _buildScreen({
  Room? room,
  FakeSoliplexApi? api,
  Future<ToolRegistry> Function(String)? toolRegistryResolver,
}) {
  final fakeApi = api ?? FakeSoliplexApi();
  fakeApi.nextRoom ??= room ?? _testRoom;
  final entry = createTestServerEntry(api: fakeApi);
  final uploadRegistry = UploadTrackerRegistry(
    servers: Signal<Map<String, ServerEntry>>({entry.serverId: entry}),
  );
  return MaterialApp(
    home: RoomInfoScreen(
      serverEntry: entry,
      roomId: 'room-1',
      toolRegistryResolver:
          toolRegistryResolver ?? (_) async => const ToolRegistry(),
      uploadRegistry: uploadRegistry,
      appName: 'Soliplex',
    ),
  );
}

/// Build variant that hands back the [ServerEntry] and
/// [UploadTrackerRegistry] so tests can interact with the tracker
/// (e.g., pre-populate it before the screen mounts).
({
  Widget widget,
  ServerEntry entry,
  UploadTrackerRegistry uploadRegistry,
}) _buildScreenWithRegistry({
  Room? room,
  FakeSoliplexApi? api,
  Future<ToolRegistry> Function(String)? toolRegistryResolver,
}) {
  final fakeApi = api ?? FakeSoliplexApi();
  fakeApi.nextRoom ??= room ?? _testRoom;
  final entry = createTestServerEntry(api: fakeApi);
  final registry = UploadTrackerRegistry(
    servers: Signal<Map<String, ServerEntry>>({entry.serverId: entry}),
  );
  return (
    widget: MaterialApp(
      home: RoomInfoScreen(
        serverEntry: entry,
        roomId: 'room-1',
        toolRegistryResolver:
            toolRegistryResolver ?? (_) async => const ToolRegistry(),
        uploadRegistry: registry,
        appName: 'Soliplex',
      ),
    ),
    entry: entry,
    uploadRegistry: registry,
  );
}

void main() {
  group('RoomInfoScreen', () {
    testWidgets('shows loading then room content', (tester) async {
      final api = FakeSoliplexApi()..nextRoom = _testRoom;
      await tester.pumpWidget(_buildScreen(api: api));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Room name and description are displayed in the body
      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('A test room'), findsOneWidget);
    });

    testWidgets('shows agent card with model info', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('AGENT'), findsOneWidget);
      expect(find.text('gpt-4o'), findsOneWidget);
      expect(find.text('openai'), findsOneWidget);
    });

    testWidgets('the identifiers on this screen can be selected',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // One region above every card, rather than a selectable widget per row:
      // a selection widget wins the gesture arena, so one placed inside a card
      // would leave its tap-to-expand rows dead to taps.
      expect(
        find.ancestor(
          of: find.text('gpt-4o'),
          matching: find.byType(SelectableContent),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows features card', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('FEATURES'), findsOneWidget);
    });

    group('room upload controls', () {
      // Uploading to a room needs an administrator; reading the list does not.
      Future<void> pumpAs(WidgetTester tester, FakeSoliplexApi api) async {
        await tester.pumpWidget(_buildScreen(api: api));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          // Not the exact string: the card titles itself 'UPLOADED FILES (n)'
          // once it has any, and this group scrolls to it with and without.
          find.textContaining('UPLOADED FILES'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }

      SoliplexButton buttonFor(WidgetTester tester, String label) =>
          tester.widget<SoliplexButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(SoliplexButton),
            ),
          );

      testWidgets('an administrator gets the plain empty message',
          (tester) async {
        // The other arm names who adds the files. Saying that to the person
        // who does would be wrong, and it is the only thing that tells the two
        // empty states apart.
        final api = FakeSoliplexApi()..nextIsAdminUser = true;

        await pumpAs(tester, api);

        expect(find.text('No uploaded files in this room.'), findsOneWidget);
        expect(
          find.text('An administrator adds files to this room.'),
          findsNothing,
        );
      });

      testWidgets('everyone else gets the list and an explanation',
          (tester) async {
        final api = FakeSoliplexApi()..nextIsAdminUser = false;

        await pumpAs(tester, api);

        expect(find.text('Upload files to room'), findsNothing);
        expect(find.text('Upload folder to room'), findsNothing);
        // The card itself stays: members see what the agent can cite.
        expect(find.text('UPLOADED FILES'), findsOneWidget);
        expect(find.text('No uploaded files in this room.'), findsOneWidget);
        expect(
          find.text('An administrator adds files to this room.'),
          findsOneWidget,
        );
      });

      testWidgets('the explanation does not depend on the list being empty',
          (tester) async {
        // It stands in for the controls, so it belongs wherever they were
        // withdrawn. Carried by the empty message it would be unreachable in
        // exactly the rooms that have something to show, and the controls
        // would vanish with nothing anywhere saying why.
        final api = FakeSoliplexApi()
          ..nextIsAdminUser = false
          ..nextRoomUploads = [
            FileUpload(
              filename: 'shared.pdf',
              url: Uri.parse('https://example.com/shared.pdf'),
            ),
          ];

        await pumpAs(tester, api);

        expect(find.text('shared.pdf'), findsOneWidget);
        expect(find.text('Upload files to room'), findsNothing);
        expect(
          find.text('An administrator adds files to this room.'),
          findsOneWidget,
        );
      });

      testWidgets('an unanswerable request leaves them usable', (tester) async {
        // Withholding them on a failed request would strip an administrator of
        // a capability they have; the server still refuses anyone else. The
        // answer resolves before the bound here, so `onTimeout` never fires —
        // the sibling below covers the request that outruns it. Asserts the
        // controls are live rather than merely present, since present-but-
        // loading is disabled and would read as a refusal.
        final api = FakeSoliplexApi()
          ..nextIsAdminUserThrow = NetworkException(message: 'offline');

        await pumpAs(tester, api);

        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);
        expect(buttonFor(tester, 'Upload folder to room').isLoading, isFalse);
      });

      testWidgets('a failure that lands after the bound leaves the guess alone',
          (tester) async {
        // The under-load shape: the request outruns the bound, the controls go
        // live on the guess, and the request then fails outright. Writing that
        // non-answer over the guess would put the controls back into their
        // loading state — disabled, with nothing left to resolve them.
        final gate = Completer<bool>();
        final api = FakeSoliplexApi()..isAdminUserGate = gate;

        await tester.pumpWidget(_buildScreen(api: api));
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);

        gate.completeError(NetworkException(message: 'offline'));
        // Pumped rather than settled: were the guess overwritten, the spinner
        // that replaced it would animate forever and settling would hang
        // instead of failing the assertion below.
        await tester.pump();
        await tester.pump();

        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);
        expect(buttonFor(tester, 'Upload folder to room').isLoading, isFalse);
      });

      testWidgets('they are present but not usable until the answer arrives',
          (tester) async {
        // An absent control would read as a refusal, so the wait renders as a
        // control on its way instead.
        final gate = Completer<bool>();
        final api = FakeSoliplexApi()..isAdminUserGate = gate;

        // Pumped rather than settled: the loading spinner animates forever, so
        // there is no quiet frame to settle to until the answer lands.
        await tester.pumpWidget(_buildScreen(api: api));
        await tester.pump();
        await tester.pump();

        expect(buttonFor(tester, 'Upload files to room').isLoading, isTrue);
        expect(buttonFor(tester, 'Upload folder to room').isLoading, isTrue);

        gate.complete(true);
        await tester.pumpAndSettle();

        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);
        expect(buttonFor(tester, 'Upload folder to room').isLoading, isFalse);
      });

      testWidgets(
          'they go live at the bound, and a later refusal withdraws '
          'them', (tester) async {
        // Loading is disabled, and the request's own timeout starts only once
        // it holds one of six shared connection slots — so uploads already
        // running can keep it queued well past that timeout, and waiting
        // unbounded would strip an administrator of a capability they have.
        //
        // The guess that bound produces must not then stand for the life of
        // the screen: left standing, it hands a non-administrator two controls
        // whose every use the server refuses once they have chosen a file.
        final gate = Completer<bool>();
        final api = FakeSoliplexApi()..isAdminUserGate = gate;

        await tester.pumpWidget(_buildScreen(api: api));
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        // Live, not merely present — this is the guess the answer overturns.
        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);

        gate.complete(false);
        await tester.pumpAndSettle();

        expect(find.text('Upload files to room'), findsNothing);
        expect(find.text('Upload folder to room'), findsNothing);
      });
    });

    testWidgets(
        'hides the uploaded files card when the room accepts no room '
        'uploads', (tester) async {
      // Thread capability on, room capability off: the card is room-scoped, so
      // reading the wrong field would show it and fetch a list the server has
      // no path for.
      await tester.pumpWidget(_buildScreen(
        room: _testRoom.copyWith(acceptsRoomUploads: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('UPLOADED FILES'), findsNothing);
    });

    testWidgets('shows tools section', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('TOOLS (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TOOLS (1)'), findsOneWidget);
      expect(find.text('search'), findsOneWidget);
    });

    testWidgets('shows MCP toolsets section', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('MCP CLIENT TOOLSETS (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MCP CLIENT TOOLSETS (1)'), findsOneWidget);
    });

    testWidgets('shows skills section with skills', (tester) async {
      final room = _testRoom.copyWith(
        skills: {
          'web_search': const RoomSkill(
            name: 'Web Search',
            description: 'Search the web',
            source: 'filesystem',
          ),
        },
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('SKILLS (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('SKILLS (1)'), findsOneWidget);
    });

    testWidgets('expanding skill shows detail dialog on Show more',
        (tester) async {
      final room = _testRoom.copyWith(
        skills: {
          'web_search': const RoomSkill(
            name: 'Web Search',
            description: 'Search the web',
            source: 'filesystem',
            metadata: {'author': 'test-user'},
          ),
        },
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('web_search'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('web_search'));
      await tester.pumpAndSettle();

      // Skill detail fields visible
      expect(find.text('Search the web'), findsOneWidget);
      expect(find.text('filesystem'), findsOneWidget);

      // Tap "Show more" to open dialog
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      // Dialog shows metadata
      expect(find.text('Metadata'), findsOneWidget);
      expect(find.text('author'), findsOneWidget);
      expect(find.text('test-user'), findsOneWidget);
    });

    testWidgets('shows empty skills section when no skills', (tester) async {
      final room = _testRoom.copyWith(skills: const {});
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('SKILLS (0)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('SKILLS (0)'), findsOneWidget);
    });

    testWidgets('shows empty tools section when no tools', (tester) async {
      final room = _testRoom.copyWith(tools: const {});
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('TOOLS (0)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TOOLS (0)'), findsOneWidget);
    });

    testWidgets('shows empty MCP toolsets section when none', (tester) async {
      final room = _testRoom.copyWith(mcpClientToolsets: const {});
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('MCP CLIENT TOOLSETS (0)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MCP CLIENT TOOLSETS (0)'), findsOneWidget);
    });

    testWidgets('shows client tools loading then empty', (tester) async {
      final completer = Completer<ToolRegistry>();
      await tester.pumpWidget(
        _buildScreen(
          toolRegistryResolver: (_) => completer.future,
        ),
      );
      // Use pump() — pumpAndSettle would time out on the loading spinner.
      await tester.pump();
      await tester.pump();

      // Scroll to find the CLIENT TOOLS section while loading
      await tester.scrollUntilVisible(
        find.text('CLIENT TOOLS'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CLIENT TOOLS'), findsOneWidget);

      // Complete with empty registry
      completer.complete(const ToolRegistry());
      await tester.pumpAndSettle();

      expect(find.text('CLIENT TOOLS (0)'), findsOneWidget);
    });

    testWidgets('shows factory agent with extra config', (tester) async {
      final room = _testRoom.copyWith(
        agent: const FactoryRoomAgent(
          id: 'agent-factory',
          factoryName: 'my_module.create_agent',
          extraConfig: {'temperature': 0.7, 'top_k': 50},
        ),
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      expect(find.text('Extra Config'), findsOneWidget);
      expect(find.textContaining('0.7'), findsOneWidget);
    });

    testWidgets('shows error on fetch failure', (tester) async {
      final api = FakeSoliplexApi()..nextError = Exception('network');
      await tester.pumpWidget(_buildScreen(api: api));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load room'), findsOneWidget);
    });

    testWidgets('expands tool to show details', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('search'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('search'));
      await tester.pumpAndSettle();

      expect(find.text('Search the web'), findsOneWidget);
      expect(find.text('bare'), findsOneWidget);
    });

    testWidgets('shows documents when loaded', (tester) async {
      final api = FakeSoliplexApi()
        ..nextRoom = _testRoom
        ..nextDocuments = const [
          RagDocument(id: 'd1', title: 'Report', uri: '/docs/report.pdf'),
        ];
      await tester.pumpWidget(_buildScreen(api: api));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('DOCUMENTS (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('DOCUMENTS (1)'), findsOneWidget);
    });

    testWidgets('shows retry button on documents error', (tester) async {
      final api = FakeSoliplexApi()
        ..nextRoom = _testRoom
        ..nextDocumentsError = Exception('network');
      await tester.pumpWidget(_buildScreen(api: api));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Failed to load documents'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Failed to load documents'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('uploaded files refresh dedupe', () {
    testWidgets('fetches uploads when the tracker is still Loading',
        (tester) async {
      final api = FakeSoliplexApi()..nextRoomUploads = const [];
      await tester.pumpWidget(_buildScreen(api: api));
      await tester.pumpAndSettle();

      expect(api.getRoomUploadsCount, 1);
    });

    testWidgets('skips the fetch when the tracker already has a Loaded list',
        (tester) async {
      final api = FakeSoliplexApi()..nextRoomUploads = const [];
      final built = _buildScreenWithRegistry(api: api);

      // Simulate Room → Info navigation by priming the shared tracker
      // the same way RoomState's constructor would.
      final tracker = built.uploadRegistry.trackerFor(
        entry: built.entry,
        roomId: 'room-1',
      );
      await tracker.refreshRoom('room-1');
      expect(api.getRoomUploadsCount, 1);

      await tester.pumpWidget(built.widget);
      await tester.pumpAndSettle();

      expect(
        api.getRoomUploadsCount,
        1,
        reason: 'info-screen must not refetch when tracker is already Loaded',
      );
    });
  });
}
