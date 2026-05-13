import 'package:soliplex_client/src/application/run_phase.dart';
import 'package:test/test.dart';

void main() {
  group('ToolCallPhase', () {
    test(
      'withToolName accumulates tool names from single-tool constructor',
      () {
        final phase = ToolCallPhase.single(toolName: 'search');

        final updated = phase.withToolName('summarize');

        expect(updated.toolNames, equals({'search', 'summarize'}));
      },
    );

    test(
      'withToolName accumulates tool names from multiple-tool constructor',
      () {
        const phase = ToolCallPhase(toolNames: {'a', 'b'});

        final updated = phase.withToolName('c');

        expect(updated.toolNames, equals({'a', 'b', 'c'}));
      },
    );

    test('withToolName is idempotent for duplicate names', () {
      final phase = ToolCallPhase.single(toolName: 'search');

      final updated = phase.withToolName('search');

      expect(updated.toolNames, equals({'search'}));
    });

    test('equality works across constructors with all fields populated', () {
      final single = ToolCallPhase.single(
        toolName: 'search',
        latestToolCallId: 'tc-1',
        timestamp: 100,
      );
      const multiple = ToolCallPhase(
        toolNames: {'search'},
        latestToolCallId: 'tc-1',
        timestamp: 100,
      );

      expect(single, equals(multiple));
      expect(single.hashCode, equals(multiple.hashCode));
    });

    test('hashCode is order-independent for tool names', () {
      const ab = ToolCallPhase(toolNames: {'a', 'b'});
      const ba = ToolCallPhase(toolNames: {'b', 'a'});

      expect(ab, equals(ba));
      expect(ab.hashCode, equals(ba.hashCode));
    });
  });
}
