import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('McpClientToolset', () {
    test('creates with all fields', () {
      const toolset = McpClientToolset(
        kind: 'http',
        allowedTools: ['tool1', 'tool2'],
        toolsetParams: {'url': 'http://localhost:3000'},
      );

      expect(toolset.kind, equals('http'));
      expect(toolset.allowedTools, equals(['tool1', 'tool2']));
      expect(toolset.toolsetParams, equals({'url': 'http://localhost:3000'}));
    });

    test('creates with defaults', () {
      const toolset = McpClientToolset(kind: 'stdio');

      expect(toolset.kind, equals('stdio'));
      expect(toolset.allowedTools, isEmpty);
      expect(toolset.toolsetParams, isEmpty);
    });

    test('toString includes kind', () {
      const toolset = McpClientToolset(kind: 'http');

      expect(toolset.toString(), contains('http'));
    });
  });
}
