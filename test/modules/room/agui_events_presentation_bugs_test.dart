/// Invariants for the "$N events" bubble rendered above assistant
/// messages by [ExecutionTimeline].
///
/// Nested-row completion
/// ---------------------
/// Stored threads carry a logical sub-skill invocation as two
/// `ActivitySnapshotEvent`s sharing a `messageId`: a call phase
/// (`activity_type='skill_tool_call'`, carrying `args`) and a result
/// phase (`activity_type='skill_tool_result'`, carrying `result`,
/// `replace=true`). The second must land on the first's record rather
/// than beside it, so the pair renders as one row that advances — the
/// timeline places one id and resolves it against the stored record.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/live_session.dart';
import '../../helpers/test_logger.dart';

void main() {
  setUpAll(registerLiveSessionFallbacks);

  group('a result snapshot advances the nested row it shares an id with', () {
    test(
      'historical replay: call snapshot + result snapshot leave one row, '
      'carrying the result',
      () async {
        final history = await storedHistory([
          (
            runId: 'run-1',
            userMessageId: 'user-1',
            prompt: 'Q',
            events: const [
              TextMessageStartEvent(messageId: 'asst-1'),
              TextMessageContentEvent(messageId: 'asst-1', delta: 'Here.'),
              ToolCallStartEvent(
                toolCallId: 'tc-1',
                toolCallName: 'execute_skill',
              ),
              // Phase 1: call. The producer emits replace=false so the
              // initial snapshot lands as a new record.
              ActivitySnapshotEvent(
                messageId: 'rag:call_1',
                activityType: 'skill_tool_call',
                content: {
                  'tool_name': 'ask',
                  'args': '{"q":"hi"}',
                },
                replace: false,
                timestamp: 100,
              ),
              // Phase 2: result. Different activity_type, same messageId,
              // replace=true so the call record is overwritten in place.
              ActivitySnapshotEvent(
                messageId: 'rag:call_1',
                activityType: 'skill_tool_result',
                content: {
                  'tool_name': 'ask',
                  'result': 'answer text',
                },
                timestamp: 150,
              ),
              ToolCallResultEvent(
                toolCallId: 'tc-1',
                content: 'ok',
                messageId: 'result-1',
              ),
              TextMessageEndEvent(messageId: 'asst-1'),
            ],
          ),
        ]);
        final trackers = replayToTrackers(history);
        final tracker = trackers['asst-1']!;
        final step = tracker.timeline.value.single as TimelineStep;

        expect(step.activityIds, ['rag:call_1']);
        final activity = tracker.activities.value.single;
        expect(
          activity.activityType,
          'skill_tool_result',
          reason: 'The result snapshot must replace the call record at that '
              'messageId; otherwise the row never advances past the call.',
        );
        expect(activity.content['result'], 'answer text');
      },
    );

    test(
      'live tracker: call ActivitySnapshot then result ActivitySnapshot '
      'on the same messageId leave one row, carrying the result',
      () {
        final activities = Signal<List<ActivityRecord>>(const []);
        final tracker = ExecutionTracker(
          activities: activities,
          logger: testLogger(),
        );
        addTearDown(tracker.dispose);

        // Each AG-UI event goes through both production paths it takes at
        // runtime: `bridgeBaseEvent` for the tracker's ExecutionEvent, and
        // `applyActivityEvent` for the record. Folding rather than assigning
        // the record is what makes the replace assertion below a statement
        // about production code instead of about this test's own setup.
        const callEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: <String, dynamic>{'tool_name': 'ask', 'args': '{"q":"hi"}'},
          replace: false,
          timestamp: 100,
        );
        final ExecutionEvent? callSnapshot = bridgeBaseEvent(callEvent);
        expect(callSnapshot, isNotNull);
        activities.value = applyActivityEvent(
          activities.value,
          callEvent,
          logger: testLogger(),
        );
        tracker.observe(callSnapshot);

        final calls = tracker.activities.value;
        expect(calls, hasLength(1));
        expect(calls.single.activityType, 'skill_tool_call');

        const resultEvent = ActivitySnapshotEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_result',
          content: <String, dynamic>{
            'tool_name': 'ask',
            'result': 'answer text',
          },
          timestamp: 150,
        );
        final ExecutionEvent? resultSnapshot = bridgeBaseEvent(resultEvent);
        expect(resultSnapshot, isNotNull);
        activities.value = applyActivityEvent(
          activities.value,
          resultEvent,
          logger: testLogger(),
        );
        tracker.observe(resultSnapshot);

        final updated = tracker.activities.value;
        expect(
          updated,
          hasLength(1),
          reason: 'The result snapshot must replace the call record at that '
              'messageId rather than appending a second row beside it.',
        );
        expect(updated.single.activityType, 'skill_tool_result');
        expect(updated.single.content['result'], 'answer text');
        expect(
          tracker.timeline.value,
          hasLength(1),
          reason: 'Both snapshots carry one messageId, so the timeline must '
              'hold one entry — the second placement is a no-op, not a row.',
        );
      },
    );
  });
}
