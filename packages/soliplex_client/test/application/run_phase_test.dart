import 'package:soliplex_client/src/application/run_phase.dart';
import 'package:test/test.dart';

void main() {
  group('ToolCallPhase', () {
    test(
      'withToolName accumulates tool names from single-tool constructor',
      () {
        const phase = ToolCallPhase(toolName: 'search');

        final updated = phase.withToolName('summarize');

        expect(updated.allToolNames, equals({'search', 'summarize'}));
      },
    );

    test(
      'withToolName accumulates tool names from multiple-tool constructor',
      () {
        const phase = ToolCallPhase.multiple(toolNames: {'a', 'b'});

        final updated = phase.withToolName('c');

        expect(updated.allToolNames, equals({'a', 'b', 'c'}));
      },
    );

    test('withToolName is idempotent for duplicate names', () {
      const phase = ToolCallPhase(toolName: 'search');

      final updated = phase.withToolName('search');

      expect(updated.allToolNames, equals({'search'}));
    });

    test('equality works across constructor variants', () {
      const single = ToolCallPhase(toolName: 'search');
      const multiple = ToolCallPhase.multiple(toolNames: {'search'});

      expect(single, equals(multiple));
    });

    test('equality works across constructors with all fields populated', () {
      const single = ToolCallPhase(
        toolName: 'search',
        latestToolCallId: 'tc-1',
        timestamp: 100,
      );
      const multiple = ToolCallPhase.multiple(
        toolNames: {'search'},
        latestToolCallId: 'tc-1',
        timestamp: 100,
      );

      expect(single, equals(multiple));
      expect(single.hashCode, equals(multiple.hashCode));
    });

    test('hashCode is order-independent for tool names', () {
      const ab = ToolCallPhase.multiple(toolNames: {'a', 'b'});
      const ba = ToolCallPhase.multiple(toolNames: {'b', 'a'});

      expect(ab, equals(ba));
      expect(ab.hashCode, equals(ba.hashCode));
    });
  });
}
