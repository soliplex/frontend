/// End-to-end pipeline canary for the activity-persistence feature.
///
/// Drives realistic `ActivitySnapshotEvent` sequences through the
/// production `processEvent` function and reads the result back through
/// the typed `Conversation.skillToolCalls` accessor, the same surface a
/// future StatePanel / ActivityLog UI will consume.
///
/// If this test ever fails, the UI cannot trust `conversation.activities`
/// to reflect what the backend emitted — the contract is broken
/// somewhere between the AG-UI processor and the typed view.
library;

import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('activity pipeline canary', () {
    late Conversation conversation;
    late StreamingState streaming;

    setUp(() {
      conversation = Conversation.empty(threadId: 'thread-1');
      streaming = const AwaitingText();
    });

    test(
      'single skill_tool_call snapshot → typed view exposes toolName, '
      'decoded args, and status',
      () {
        const event = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"what is AG-UI?","top_k":3}',
            'status': 'in_progress',
          },
          timestamp: 100,
        );

        final result = processEvent(conversation, streaming, event);
        final calls = result.conversation.skillToolCalls;

        expect(calls, hasLength(1));
        expect(calls.single.messageId, 'rag:call_1');
        expect(calls.single.toolName, 'ask');
        expect(calls.single.args, {'q': 'what is AG-UI?', 'top_k': 3});
        expect(calls.single.status, 'in_progress');
        expect(calls.single.timestamp, 100);
      },
    );

    test(
      'replace:true upgrade from in_progress → done is visible through the '
      'typed accessor (status flips, messageId stable)',
      () {
        const start = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"hi"}',
            'status': 'in_progress',
          },
          timestamp: 1,
        );
        const finish = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"hi"}',
            'status': 'done',
          },
          timestamp: 2,
        );

        final afterStart = processEvent(conversation, streaming, start);
        final afterFinish = processEvent(
          afterStart.conversation,
          afterStart.streaming,
          finish,
        );

        final calls = afterFinish.conversation.skillToolCalls;
        expect(calls, hasLength(1));
        expect(calls.single.messageId, 'rag:call_1');
        expect(calls.single.status, 'done');
        expect(calls.single.timestamp, 2);
      },
    );

    test(
      'two concurrent skill_tool_call message IDs stay independent in the '
      'typed view',
      () {
        const askEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_ask',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"what"}',
            'status': 'in_progress',
          },
          timestamp: 1,
        );
        const searchEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_search',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'search',
            'args': '{"q":"where"}',
            'status': 'in_progress',
          },
          timestamp: 2,
        );

        final afterAsk = processEvent(conversation, streaming, askEvent);
        final afterSearch = processEvent(
          afterAsk.conversation,
          afterAsk.streaming,
          searchEvent,
        );

        final calls = afterSearch.conversation.skillToolCalls;
        expect(calls, hasLength(2));
        final byId = {for (final c in calls) c.messageId: c};
        expect(byId['rag:call_ask']!.toolName, 'ask');
        expect(byId['rag:call_search']!.toolName, 'search');
      },
    );

    test(
      'non-skill_tool_call activities are persisted but filtered out of '
      'the typed accessor',
      () {
        const planEvent = ActivitySnapshotEvent(
          messageId: 'plan:1',
          activityType: 'plan',
          content: {'steps': 3},
          timestamp: 1,
        );
        const toolEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"hi"}',
            'status': 'in_progress',
          },
          timestamp: 2,
        );

        final afterPlan = processEvent(conversation, streaming, planEvent);
        final afterTool = processEvent(
          afterPlan.conversation,
          afterPlan.streaming,
          toolEvent,
        );

        expect(afterTool.conversation.activities, hasLength(2));
        final calls = afterTool.conversation.skillToolCalls;
        expect(calls, hasLength(1));
        expect(calls.single.messageId, 'rag:call_1');
      },
    );

    test(
      'replace:false on an existing messageId is ignored — typed view still '
      'reflects the first snapshot',
      () {
        const first = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"first"}',
            'status': 'in_progress',
          },
          timestamp: 1,
        );
        const shadow = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'search',
            'args': '{"q":"second"}',
            'status': 'done',
          },
          replace: false,
          timestamp: 2,
        );

        final afterFirst = processEvent(conversation, streaming, first);
        final afterShadow = processEvent(
          afterFirst.conversation,
          afterFirst.streaming,
          shadow,
        );

        final calls = afterShadow.conversation.skillToolCalls;
        expect(calls, hasLength(1));
        expect(calls.single.toolName, 'ask');
        expect(calls.single.status, 'in_progress');
        expect(calls.single.args, {'q': 'first'});
      },
    );

    test(
      'malformed skill_tool_call is persisted raw but dropped from the '
      'typed accessor — keeps the list usable for UI consumers',
      () {
        const goodEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'ask',
            'args': '{"q":"ok"}',
            'status': 'done',
          },
          timestamp: 1,
        );
        const badEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_2',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search', 'args': 'not json {'},
          timestamp: 2,
        );

        final afterGood = processEvent(conversation, streaming, goodEvent);
        final afterBad = processEvent(
          afterGood.conversation,
          afterGood.streaming,
          badEvent,
        );

        expect(afterBad.conversation.activities, hasLength(2));
        final calls = afterBad.conversation.skillToolCalls;
        expect(calls, hasLength(1));
        expect(calls.single.messageId, 'rag:call_1');
      },
    );
  });
}
