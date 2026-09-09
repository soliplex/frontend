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

      testWidgets('an unanswerable check says so and offers a retry',
          (tester) async {
        // The upload POST authorizes through the same installation-side check
        // this answer comes from, so a check that cannot answer cannot
        // authorize either. Offering the controls would offer an action whose
        // every use fails.
        final api = FakeSoliplexApi()
          ..nextIsAdminUserThrow = NetworkException(message: 'offline');

        await pumpAs(tester, api);

        expect(find.text('Upload files to room'), findsNothing);
        expect(
          find.text("Couldn't check whether you can add files here."),
          findsOneWidget,
        );
        // Not the refusal copy: it names who does add the files, which is a
        // claim about the user that nothing here established.
        expect(
          find.text('An administrator adds files to this room.'),
          findsNothing,
        );
      });

      testWidgets('the retry asks again', (tester) async {
        // An unanswered check is never kept, so this is a real second request
        // rather than a replayed non-answer.
        final api = FakeSoliplexApi()
          ..nextIsAdminUserThrow = NetworkException(message: 'offline');

        await pumpAs(tester, api);
        expect(api.getIsAdminUserCallCount, 1);

        api
          ..nextIsAdminUserThrow = null
          ..nextIsAdminUser = true;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(api.getIsAdminUserCallCount, 2);
        // The answer that arrives replaces the unknown, so the controls appear.
        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);
      });

      testWidgets('a check still queued at the bound withholds the controls',
          (tester) async {
        // The under-load shape: the request's own timeout starts only once it
        // holds one of six shared connection slots, so an upload already
        // running can keep it queued far past that timeout.
        final gate = Completer<bool>();
        final api = FakeSoliplexApi()..isAdminUserGate = gate;

        await tester.pumpWidget(_buildScreen(api: api));
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));

        expect(find.text('Upload files to room'), findsNothing);
        expect(
          find.text("Couldn't check whether you can add files here."),
          findsOneWidget,
        );

        // The bound does not end the request: an answer arriving later still
        // replaces what the bound wrote, in either direction.
        gate.complete(true);
        await tester.pumpAndSettle();

        expect(buttonFor(tester, 'Upload files to room').isLoading, isFalse);
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

      testWidgets('a refusal after the bound replaces the unknown',
          (tester) async {
        // The other polarity of the late answer: the check outruns the bound,
        // then the installation says no. The client may name who adds the
        // files only once it has been told.
        final gate = Completer<bool>();
        final api = FakeSoliplexApi()..isAdminUserGate = gate;

        await tester.pumpWidget(_buildScreen(api: api));
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));

        gate.complete(false);
        await tester.pumpAndSettle();

        expect(find.text('Upload files to room'), findsNothing);
        expect(
          find.text('An administrator adds files to this room.'),
          findsOneWidget,
        );
        expect(
          find.text("Couldn't check whether you can add files here."),
          findsNothing,
        );
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

    testWidgets('tool with extra parameters offers Show more', (tester) async {
      final room = _testRoom.copyWith(
        tools: {
          'search': const RoomTool(
            name: 'search',
            description: 'Search the web',
            kind: 'bare',
            extraParameters: {'timeout_s': 30},
          ),
        },
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('search'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('search'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Extra Parameters'), findsOneWidget);
      expect(find.text('timeout_s'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('tool without extra parameters has no Show more',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('search'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('search'));
      await tester.pumpAndSettle();

      // Assert the card actually opened first, so the negative below cannot
      // pass on a card that never expanded.
      expect(find.text('Search the web'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('never renders an MCP toolset\'s transport config',
        (tester) async {
      final room = _testRoom.copyWith(
        mcpClientToolsets: {
          'stdio-tools': const McpClientToolset(
            kind: 'stdio',
            toolsetParams: {
              'command': 'uvx',
              'env': {'API_KEY': 'secret:PROD_KEY'},
              'headers': {'Authorization': 'Bearer tok-abc123'},
            },
          ),
        },
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('stdio-tools'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('stdio-tools'));
      await tester.pumpAndSettle();

      // The card opened — the negatives below are about what it withholds.
      expect(find.text('stdio'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
      expect(find.textContaining('secret:PROD_KEY'), findsNothing);
      expect(find.textContaining('tok-abc123'), findsNothing);
      expect(find.textContaining('uvx'), findsNothing);
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
            extraParameters: {'max_results': 5},
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

      // Dialog shows the skill's extra parameters
      expect(find.text('Extra Parameters'), findsOneWidget);
      expect(find.text('max_results'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
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

    testWidgets('a factory agent without extra config omits the block',
        (tester) async {
      final room = _testRoom.copyWith(
        agent: const FactoryRoomAgent(
          id: 'agent-factory',
          factoryName: 'my_module.create_agent',
        ),
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      // The `FactoryRoomAgent` arm is unguarded, so the Extra Config block is
      // withheld by the condition inside it. This fails if that is dropped.
      expect(find.text('Factory'), findsOneWidget);
      expect(find.text('my_module.create_agent'), findsOneWidget);
      expect(find.text('Extra Config'), findsNothing);
    });

    testWidgets('an unknown agent kind shows a Kind row, not a Model row',
        (tester) async {
      final room = _testRoom.copyWith(
        agent: const OtherRoomAgent(id: 'agent-x', kind: 'swarm'),
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      expect(find.text('Kind'), findsOneWidget);
      expect(find.text('swarm'), findsOneWidget);
      expect(find.text('Model'), findsNothing);
    });

    testWidgets('a default agent with no model name omits the Model row',
        (tester) async {
      final room = _testRoom.copyWith(
        agent: const DefaultRoomAgent(
          id: 'agent-1',
          retries: 3,
          providerType: 'openai',
        ),
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      // The row is withheld, not drawn with a blank value beside its label.
      expect(find.text('Model'), findsNothing);
      expect(find.text('Provider'), findsOneWidget);
      expect(find.text('openai'), findsOneWidget);
    });

    testWidgets('a toolset allow-list renders when the backend sends one',
        (tester) async {
      final room = _testRoom.copyWith(
        mcpClientToolsets: {
          'restricted': const McpClientToolset(
            kind: 'http',
            allowedTools: ['read_file', 'write_file'],
          ),
        },
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('restricted'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('restricted'));
      await tester.pumpAndSettle();

      expect(find.text('Allowed Tools'), findsOneWidget);
      expect(find.text('read_file, write_file'), findsOneWidget);
    });

    testWidgets(
        'an empty allow-list shows no row, since it means no restriction',
        (tester) async {
      // A single toolset, so nothing else on screen can supply the row and
      // make the negative below pass for the wrong reason.
      final room = _testRoom.copyWith(
        mcpClientToolsets: {
          'unrestricted': const McpClientToolset(kind: 'stdio'),
        },
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('unrestricted'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('unrestricted'));
      await tester.pumpAndSettle();

      // The card opened, so the absent row below is a decision, not a no-show.
      expect(find.text('stdio'), findsOneWidget);
      expect(find.text('Allowed Tools'), findsNothing);
    });

    testWidgets('an agent of no recognisable shape says so', (tester) async {
      final room = _testRoom.copyWith(
        agent: const OtherRoomAgent(id: 'agent-x', kind: ''),
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      // Not a card with a heading over blank space.
      expect(find.text('AGENT'), findsOneWidget);
      expect(
        find.text('No agent configuration this app reads in this room.'),
        findsOneWidget,
      );
    });

    testWidgets('an agent whose fields all came back empty draws no rows',
        (tester) async {
      // Every value here is what a degraded read produces, so each guard on
      // the card has to withhold its row rather than draw a blank one.
      final room = _testRoom.copyWith(
        agent: const DefaultRoomAgent(
          id: 'agent-1',
          modelName: '',
          providerType: '',
        ),
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      expect(find.text('AGENT'), findsOneWidget);
      expect(find.text('Model'), findsNothing);
      expect(find.text('Provider'), findsNothing);
      expect(find.text('Retries'), findsNothing);
    });

    testWidgets('an unreadable agent block does not claim the room has none',
        (tester) async {
      // Built directly: `copyWith` cannot clear `agent`.
      const room = Room(
        id: 'room-1',
        name: 'Test Room',
        agentUnreadable: true,
      );
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      expect(
        find.text('No readable agent configuration in this room.'),
        findsOneWidget,
      );
      expect(find.text('No agent in this room.'), findsNothing);
    });

    testWidgets('a room configured without an agent still says so',
        (tester) async {
      const room = Room(id: 'room-1', name: 'Test Room');
      await tester.pumpWidget(_buildScreen(room: room));
      await tester.pumpAndSettle();

      expect(find.text('No agent in this room.'), findsOneWidget);
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
