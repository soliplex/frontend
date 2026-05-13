/// Regression harness for two known bugs in the "$N events" bubble
/// rendered above assistant messages by [ExecutionTimeline].
///
/// Bug 1 — Nested rows never get a checkmark
/// -----------------------------------------
/// haiku.skills emits one logical sub-skill invocation as two
/// `ActivitySnapshotEvent`s sharing a `messageId`: a call phase
/// (`activity_type='skill_tool_call'`, carrying `args`) and a result
/// phase (`activity_type='skill_tool_result'`, carrying `result`,
/// `replace=true`). The original frontend decoder bailed on any
/// activityType other than `skill_tool_call`, so the result snapshot
/// was logged and dropped; the nested row stayed at its in-progress
/// spinner for the rest of the run. The decoder now dispatches on
/// activityType and routes `skill_tool_result` through a result-phase
/// decoder that synthesizes `status='done'` and exposes the
/// `content['result']` text.
///
/// Bug 2 — Bubble disappears after reload
/// --------------------------------------
/// On thread reload, [replayToTrackers] keys events by assistant
/// `TextMessageStart`. A run that ends with a `ToolCallStart` but no
/// follow-up bundle (errored mid-tool, cancelled, server restart) hits
/// the "trailing tool-yield" branch and silently drops its events; no
/// tracker is produced for the run. If the chat-message processor
/// synthesized a no-response tile for the same run via a different code
/// path, that tile is rendered without a tracker — the "events bubble"
/// vanishes on reload even though it was visible during the live run.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/test_logger.dart';

void main() {
  group('Bug 1: skill_tool_result snapshot completes the nested row', () {
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
              // Phase 1: call. haiku.skills emits replace=false so the
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
          'done',
          reason: 'Result snapshot must flip the row to done; otherwise '
              'the nested icon stays at the in-progress spinner.',
        );
        expect(activity.result, 'answer text');
        expect(
          activity.args,
          isEmpty,
          reason: 'replace=true means the result snapshot overwrites the '
              "call record; args are not present in the result phase's "
              'content per AG-UI spec.',
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
          'in_progress',
          reason: 'The call phase carries no explicit status; the decoder '
              'must synthesize in_progress so the spinner renders.',
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
          'done',
          reason: 'The result snapshot must replace the call record so '
              'the trailing icon flips to the checkmark.',
        );
        expect(updated.single.result, 'answer text');
      },
    );
  });

  group('Bug 2: bubble disappears after thread reload', () {
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
          reason: 'Bug 2: trailing tool-yield drops its hoisted events; no '
              'tracker is created for run-stuck so the bubble disappears '
              'after a reload even though it was visible live.',
        );
        expect(
          trackers[expectedKey]!.steps.value.map((s) => s.label),
          containsAll(<String>['Thinking', 'search']),
          reason: 'Bug 2: the recovered tracker must contain the same '
              'steps the user saw live.',
        );
      },
    );

    test(
      'multi-run thread where the LAST run is a trailing tool-yield: the '
      'preceding assistant bubble is fine, but the last run loses its '
      'tracker — confirms the bug is isolated to the trailing case',
      () {
        // Useful baseline: the bug-free preceding run rules out a regression
        // in the normal-bundle code path so we can attribute the missing
        // tracker entirely to the trailing tool-yield.
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
          reason: 'Bug 2: trailing tool-yield bundle silently drops its '
              'events; the run loses its tracker on reload.',
        );
      },
    );
  });
}
