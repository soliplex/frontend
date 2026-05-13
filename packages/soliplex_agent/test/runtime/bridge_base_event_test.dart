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

    test('routes all four thinking-end variants to ThinkingEnded', () {
      const events = <BaseEvent>[
        ThinkingTextMessageEndEvent(),
        ThinkingEndEvent(),
        ReasoningEndEvent(messageId: 'reas-1'),
        ReasoningMessageEndEvent(messageId: 'reas-1'),
      ];

      for (final e in events) {
        expect(bridgeBaseEvent(e), const ThinkingEnded(), reason: '$e');
      }
    });

    test('ActivityDeltaEvent returns null', () {
      // The bridge intentionally drops ActivityDeltaEvent: the domain
      // layer applies the patch to Conversation.activities, and the
      // tracker observes activities reactively. Bridging the delta into
      // an ExecutionEvent would duplicate that work.
      const event = ActivityDeltaEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        patch: [
          {'op': 'replace', 'path': '/status', 'value': 'done'},
        ],
      );

      expect(bridgeBaseEvent(event), isNull);
    });
  });
}
