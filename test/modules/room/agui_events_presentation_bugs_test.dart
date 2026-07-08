/// Invariants for the "$N events" bubble rendered above assistant
/// messages by [ExecutionTimeline].
///
/// Nested-row completion
/// ---------------------
/// A logical sub-skill invocation arrives as two `ActivitySnapshotEvent`s
/// sharing a `messageId`: a call phase
/// (`activity_type='skill_tool_call'`, carrying `args`) and a result
/// phase (`activity_type='skill_tool_result'`, carrying `result`,
/// `replace=true`). The decoder dispatches on activityType so the
/// result phase synthesizes `status='done'` and exposes
/// `content['result']`, flipping the nested row out of its
/// in-progress spinner.
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

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/test_logger.dart';

void main() {
  group('skill_tool_result snapshot completes the nested row', () {
    test(
      'historical replay: call snapshot + result snapshot leaves the '
      'nested activity at status=done with the result text exposed',
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
        final activity = tracker.skillToolCalls.value.single;
        expect(
          activity.status,
          SkillToolCallStatus.done,
          reason: 'Result snapshot must flip the row to done; otherwise '
              'the nested row stays in its in-progress (shimmering) state.',
        );
        expect(activity.result, 'answer text');
        expect(
          activity.args,
          {'q': 'hi'},
          reason: 'The application layer carries args from the call phase '
              'onto the result-phase record so the unified row keeps '
              'rendering the inputs across AG-UI replace-in-place.',
        );
      },
    );

    test(
      'live tracker: call ActivitySnapshot then result ActivitySnapshot '
      'on the same messageId advances the activity to done',
      () {
        final events = Signal<ExecutionEvent?>(null);
        final activities = Signal<List<ActivityRecord>>(const []);
        final tracker = ExecutionTracker(
          executionEvents: events,
          activities: activities,
          logger: testLogger(),
        );
        addTearDown(tracker.dispose);

        // Bridge each AG-UI event through the production bridge, mirroring
        // what AgentSession does at runtime. Push the same content into
        // the activities signal so the tracker's computed skillToolCalls
        // sees the decoded view, matching what _processActivitySnapshot
        // does in production.
        const callContent = {
          'tool_name': 'ask',
          'args': '{"q":"hi"}',
        };
        final ExecutionEvent? callSnapshot = bridgeBaseEvent(
          const ActivitySnapshotEvent(
            messageId: 'rag:call_1',
            activityType: 'skill_tool_call',
            content: callContent,
            replace: false,
            timestamp: 100,
          ),
        );
        expect(callSnapshot, isNotNull);
        activities.value = const [
          ActivityRecord(
            messageId: 'rag:call_1',
            activityType: 'skill_tool_call',
            content: callContent,
            timestamp: 100,
          ),
        ];
        events.value = callSnapshot;

        final calls = tracker.skillToolCalls.value;
        expect(calls, hasLength(1));
        expect(
          calls.single.status,
          SkillToolCallStatus.inProgress,
          reason: 'The call phase carries no explicit status; the decoder '
              'must synthesize inProgress so the row shimmers as running.',
        );

        const resultContent = {
          'tool_name': 'ask',
          'result': 'answer text',
        };
        final ExecutionEvent? resultSnapshot = bridgeBaseEvent(
          const ActivitySnapshotEvent(
            messageId: 'rag:call_1',
            activityType: 'skill_tool_result',
            content: resultContent,
            timestamp: 150,
          ),
        );
        expect(resultSnapshot, isNotNull);
        activities.value = const [
          ActivityRecord(
            messageId: 'rag:call_1',
            activityType: 'skill_tool_result',
            content: resultContent,
            timestamp: 150,
          ),
        ];
        events.value = resultSnapshot;

        final updated = tracker.skillToolCalls.value;
        expect(updated, hasLength(1));
        expect(
          updated.single.status,
          SkillToolCallStatus.done,
          reason: 'The result snapshot must replace the call record so '
              'the trailing icon flips to the checkmark.',
        );
        expect(updated.single.result, 'answer text');
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
            events: const [
              RunStartedEvent(threadId: 't-1', runId: 'run-stuck'),
              ThinkingTextMessageStartEvent(),
              ThinkingTextMessageContentEvent(delta: 'reasoning'),
              ThinkingTextMessageEndEvent(),
              ToolCallStartEvent(
                toolCallId: 'tc-1',
                toolCallName: 'search',
              ),
              ToolCallEndEvent(toolCallId: 'tc-1'),
              ToolCallResultEvent(
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
              ThinkingTextMessageStartEvent(),
              ThinkingTextMessageContentEvent(delta: 'mid'),
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
