import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:test/test.dart';

void main() {
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
