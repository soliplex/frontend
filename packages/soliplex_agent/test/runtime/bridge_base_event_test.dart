// These fixtures construct ag_ui 0.3.0's deprecated THINKING_TEXT_MESSAGE_*
// events, exercising the arms kept for replaying stored threads that predate
// REASONING_*. The backend emits REASONING_* live, never THINKING_*. Removal at
// ag_ui 1.0.0 surfaces as a compile error at these constructors.

import 'package:soliplex_agent/src/orchestration/execution_event.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_client/soliplex_client.dart';
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
      // Deprecated upstream; exercises the pre-REASONING_* replay path.
      // ignore: deprecated_member_use
      const event = ThinkingTextMessageStartEvent();
      expect(bridgeBaseEvent(event), const ThinkingStarted());
    });

    test('routes ThinkingTextMessageContentEvent delta to ThinkingContent', () {
      // Deprecated upstream; exercises the pre-REASONING_* replay path.
      // ignore: deprecated_member_use
      const event = ThinkingTextMessageContentEvent(delta: 'hmm');
      expect(bridgeBaseEvent(event), const ThinkingContent(delta: 'hmm'));
    });

    test('routes all four thinking-end variants to ThinkingEnded', () {
      const events = <BaseEvent>[
        // Deprecated upstream; exercises the pre-REASONING_* replay path.
        // ignore: deprecated_member_use
        ThinkingTextMessageEndEvent(),
        ThinkingEndEvent(),
        ReasoningEndEvent(messageId: 'reas-1'),
        ReasoningMessageEndEvent(messageId: 'reas-1'),
      ];

      for (final e in events) {
        expect(bridgeBaseEvent(e), const ThinkingEnded(), reason: '$e');
      }
    });

    test('routes ToolCallArgsEvent to ServerToolCallArgs', () {
      // The arguments are the most useful thing in a tool-call row — for a
      // RAG search they are the query. Without this arm the delta reaches no
      // consumer and the row can only show the tool's name.
      const event = ToolCallArgsEvent(
        toolCallId: 'tc-1',
        delta: '{"query":"pump maintenance interval"}',
      );

      expect(
        bridgeBaseEvent(event),
        const ServerToolCallArgs(
          toolCallId: 'tc-1',
          delta: '{"query":"pump maintenance interval"}',
        ),
      );
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

    test('ActivitySnapshotEvent with non-object content returns null', () {
      // AG-UI types `content` as `Object?`; `ActivitySnapshot.content` is
      // a map, so a non-object payload does not bridge. This arm logs nothing:
      // on the live path `processEvent` throws on that shape before the event
      // reaches here, and historical replay logs it separately when it folds
      // the same event through `applyActivityEvent`.
      const event = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: 'not-a-map',
      );

      expect(bridgeBaseEvent(event), isNull);
    });

    test('ActivitySnapshotEvent with object content bridges', () {
      const event = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 7,
      );

      expect(
        bridgeBaseEvent(event),
        const ActivitySnapshot(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'ask'},
          timestamp: 7,
        ),
      );
    });
  });
}
