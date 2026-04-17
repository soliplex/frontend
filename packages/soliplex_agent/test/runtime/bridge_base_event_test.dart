import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_agent/src/orchestration/execution_event.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:test/test.dart';

void main() {
  group('bridgeBaseEvent', () {
    test('routes ReasoningMessageStartEvent to ThinkingStarted', () {
      const event = ReasoningMessageStartEvent(messageId: 'reas-1');
      expect(bridgeBaseEvent(event), const ThinkingStarted());
    });

    test('routes ReasoningMessageContentEvent delta to ThinkingContent', () {
      const event = ReasoningMessageContentEvent(
        messageId: 'reas-1',
        delta: 'reasoning step',
      );
      expect(
        bridgeBaseEvent(event),
        const ThinkingContent(delta: 'reasoning step'),
      );
    });

    test('routes ThinkingTextMessageStartEvent to ThinkingStarted', () {
      const event = ThinkingTextMessageStartEvent();
      expect(bridgeBaseEvent(event), const ThinkingStarted());
    });

    test('routes ThinkingTextMessageContentEvent delta to ThinkingContent', () {
      const event = ThinkingTextMessageContentEvent(delta: 'hmm');
      expect(bridgeBaseEvent(event), const ThinkingContent(delta: 'hmm'));
    });
  });
}
