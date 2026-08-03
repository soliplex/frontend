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
///
/// Bubble survives reload after a tool-yield
/// -----------------------------------------
/// On thread reload, [replayToTrackers] keys events by assistant
/// `TextMessageStart`. A run that ends with a `ToolCallStart` but no
/// follow-up bundle (errored mid-tool, cancelled, server restart) hits
/// the "trailing tool-yield" branch. If the chat-message processor
/// synthesizes a no-response tile for the same run via a different
/// code path, the replay must still produce a tracker keyed under the
/// synthesized id so the bubble keeps rendering the thinking and
/// tool-call timeline that was visible during the live run.
library;

// These fixtures construct ag_ui 0.3.0's deprecated THINKING_TEXT_MESSAGE_*
// and THINKING_CONTENT events, exercising handling that is kept because a
// producer negotiating ag-ui-protocol below 0.1.13 emits that family live.
// Removal at ag_ui 1.0.0 surfaces as a compile error at these constructors.

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/test_logger.dart';

void main() {
  group('a result snapshot advances the nested row it shares an id with', () {
    test(
      'historical replay: call snapshot + result snapshot leave one row, '
      'carrying the result',
      () {
        final runs = [
          RunEventBundle(
            runId: 'run-1',
            events: const [
              TextMessageStartEvent(messageId: 'asst-1'),
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
        ];

        final trackers = replayToTrackers(runs);
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
        final events = Signal<ExecutionEvent?>(null);
        final activities = Signal<List<ActivityRecord>>(const []);
        final tracker = ExecutionTracker(
          executionEvents: events,
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
        events.value = callSnapshot;

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
        events.value = resultSnapshot;

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

  group('bubble survives reload after a tool-yield', () {
    test(
      'a run that yielded to a tool and never produced an assistant '
      'TextMessageStart (errored / cancelled mid-tool, trailing in '
      'history) produces no tracker — the bubble vanishes on reload',
      () {
        // The chat-message side may still synthesize a no-response tile
        // for this run (id = noResponseMessageId(runId)). The replay
        // path *must* hand back a tracker keyed under the same id so the
        // bubble keeps showing the thinking + tool-call timeline that
        // was visible while the run was live.
        final runs = [
          RunEventBundle(
            runId: 'run-stuck',
            events: [
              RunStartedEvent(threadId: 't-1', runId: 'run-stuck'),
              // Deprecated upstream; exercises the pre-REASONING_* replay path.
              // ignore: deprecated_member_use
              const ThinkingTextMessageStartEvent(),
              // Deprecated upstream; exercises the pre-REASONING_* replay path.
              // ignore: deprecated_member_use
              const ThinkingTextMessageContentEvent(delta: 'reasoning'),
              // Deprecated upstream; exercises the pre-REASONING_* replay path.
              // ignore: deprecated_member_use
              const ThinkingTextMessageEndEvent(),
              const ToolCallStartEvent(
                toolCallId: 'tc-1',
                toolCallName: 'search',
              ),
              const ToolCallEndEvent(toolCallId: 'tc-1'),
              const ToolCallResultEvent(
                toolCallId: 'tc-1',
                content: 'partial',
                messageId: 'tool-1',
              ),
              // No assistant TextMessageStart, no follow-up bundle.
            ],
          ),
        ];

        final trackers = replayToTrackers(runs);
        final expectedKey = noResponseMessageId('run-stuck');

        expect(
          trackers,
          contains(expectedKey),
          reason: 'A trailing tool-yield must still produce a tracker '
              'keyed under the synthesized no-response id so the bubble '
              'keeps rendering across the reload boundary.',
        );
        expect(
          trackers[expectedKey]!.steps.value.map((s) => s.label),
          containsAll(<String>['Thinking', 'search']),
          reason: 'The recovered tracker must contain the same steps the '
              'user saw live.',
        );
      },
    );

    test(
      'multi-run thread: a normal-bundle run followed by a trailing '
      'tool-yield run — both must produce trackers',
      () {
        // The first run exercises the normal-bundle code path; the second
        // exercises the trailing tool-yield branch. Keeping both in one
        // test pins that the recovery is scoped to the trailing case
        // without disturbing the surrounding bundles.
        final runs = [
          RunEventBundle(
            runId: 'run-1',
            events: const [
              TextMessageStartEvent(messageId: 'asst-1'),
              TextMessageContentEvent(messageId: 'asst-1', delta: 'hi'),
              TextMessageEndEvent(messageId: 'asst-1'),
            ],
          ),
          RunEventBundle(
            runId: 'run-stuck',
            events: const [
              // Deprecated upstream; exercises the pre-REASONING_* replay path.
              // ignore: deprecated_member_use
              ThinkingTextMessageStartEvent(),
              // Deprecated upstream; exercises the pre-REASONING_* replay path.
              // ignore: deprecated_member_use
              ThinkingTextMessageContentEvent(delta: 'mid'),
              // Deprecated upstream; exercises the pre-REASONING_* replay path.
              // ignore: deprecated_member_use
              ThinkingTextMessageEndEvent(),
              ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'search'),
              ToolCallEndEvent(toolCallId: 'tc-1'),
              ToolCallResultEvent(
                toolCallId: 'tc-1',
                content: 'ok',
                messageId: 'tool-1',
              ),
            ],
          ),
        ];

        final trackers = replayToTrackers(runs);

        expect(trackers.keys, contains('asst-1'));
        expect(
          trackers.keys,
          contains(noResponseMessageId('run-stuck')),
          reason: 'A trailing tool-yield bundle must still produce a '
              'tracker; the second run must not lose it on reload.',
        );
      },
    );
  });
}
