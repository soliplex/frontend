import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:test/test.dart';

void main() {
  group('ToolCallActivity', () {
    test(
      'withToolName accumulates tool names from single-tool constructor',
      () {
        const activity = ToolCallActivity(toolName: 'search');

        final updated = activity.withToolName('summarize');

        expect(updated.allToolNames, equals({'search', 'summarize'}));
      },
    );

    test(
      'withToolName accumulates tool names from multiple-tool constructor',
      () {
        const activity = ToolCallActivity.multiple(toolNames: {'a', 'b'});

        final updated = activity.withToolName('c');

        expect(updated.allToolNames, equals({'a', 'b', 'c'}));
      },
    );

    test('withToolName is idempotent for duplicate names', () {
      const activity = ToolCallActivity(toolName: 'search');

      final updated = activity.withToolName('search');

      expect(updated.allToolNames, equals({'search'}));
    });

    test('equality works across constructor variants', () {
      const single = ToolCallActivity(toolName: 'search');
      const multiple = ToolCallActivity.multiple(toolNames: {'search'});

      expect(single, equals(multiple));
    });

    test('equality works across constructors with all fields populated', () {
      const single = ToolCallActivity(
        toolName: 'search',
        latestToolCallId: 'tc-1',
        timestamp: 100,
      );
      const multiple = ToolCallActivity.multiple(
        toolNames: {'search'},
        latestToolCallId: 'tc-1',
        timestamp: 100,
      );

      expect(single, equals(multiple));
      expect(single.hashCode, equals(multiple.hashCode));
    });

    test('hashCode is order-independent for tool names', () {
      const ab = ToolCallActivity.multiple(toolNames: {'a', 'b'});
      const ba = ToolCallActivity.multiple(toolNames: {'b', 'a'});

      expect(ab, equals(ba));
      expect(ab.hashCode, equals(ba.hashCode));
    });
  });

  group('AwaitingText', () {
    test(
      'hasThinkingContent is true when bufferedThinkingText is non-empty',
      () {
        const state = AwaitingText(bufferedThinkingText: 'Thinking...');

        expect(state.hasThinkingContent, isTrue);
      },
    );

    test('hasThinkingContent is true when isThinkingStreaming', () {
      const state = AwaitingText(isThinkingStreaming: true);

      expect(state.hasThinkingContent, isTrue);
    });

    test('hasThinkingContent is false when no thinking content', () {
      const state = AwaitingText();

      expect(state.hasThinkingContent, isFalse);
    });
  });
}
