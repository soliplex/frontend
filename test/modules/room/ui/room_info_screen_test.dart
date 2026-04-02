import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info_screen.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/test_server_entry.dart';

const _testRoom = Room(
  id: 'room-1',
  name: 'Test Room',
  description: 'A test room',
  enableAttachments: true,
  allowMcp: true,
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
  return MaterialApp(
    home: RoomInfoScreen(
      serverEntry: createTestServerEntry(api: fakeApi),
      roomId: 'room-1',
      toolRegistryResolver:
          toolRegistryResolver ?? (_) async => const ToolRegistry(),
    ),
  );
}

void main() {
  group('RoomInfoScreen', () {
    testWidgets('shows loading then room content', (tester) async {
      final api = FakeSoliplexApi()..nextRoom = _testRoom;
      await tester.pumpWidget(_buildScreen(api: api));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Room description is displayed in the body
      expect(find.text('A test room'), findsOneWidget);
    });

    testWidgets('shows agent card with model info', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('AGENT'), findsOneWidget);
      expect(find.text('gpt-4o'), findsOneWidget);
      expect(find.text('openai'), findsOneWidget);
    });

    testWidgets('shows features card', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('FEATURES'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget); // attachments
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
}
