/// Reproduction harness for two known bugs in the "$N events" bubble
/// rendered above assistant messages by [ExecutionTimeline].
///
/// Each `test` documents the failure mode it reproduces and asserts the
/// *correct* behavior. With the bugs present these assertions fail; once
/// the underlying drops are fixed the assertions pass without other test
/// changes.
///
/// Bug 1 — Nested rows never get a checkmark
/// -----------------------------------------
/// Backend sends an ACTIVITY_SNAPSHOT for `skill_tool_call` with status
/// `in_progress`, then an ACTIVITY_DELTA jsonpatch (`replace /status →
/// done`) when the sub-skill completes. The frontend drops every
/// `ActivityDeltaEvent` at two layers:
///
/// * [bridgeBaseEvent] returns `null` for the variant
///   (agent_session.dart:656).
/// * [_processActivityDelta] in agui_event_processor.dart is a logged
///   no-op (line 807).
///
/// Net effect: the nested row keeps the in-progress status it had on
/// first paint, so its trailing icon never flips to a checkmark.
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
  group('Bug 1: ACTIVITY_DELTA status update is dropped', () {
    test(
      'bridgeBaseEvent drops ActivityDeltaEvent — nested rows never '
      'receive the status change that drives the checkmark',
      () {
        final delta = ActivityDeltaEvent(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          patch: const [
            {'op': 'replace', 'path': '/status', 'value': 'done'},
          ],
          timestamp: 200,
        );

        // Correct behavior: produce an ExecutionEvent the tracker can act
        // on so the activity's status moves to "done". Currently null.
        expect(
          bridgeBaseEvent(delta),
          isNotNull,
          reason: 'Bug 1: ActivityDeltaEvent is dropped at the bridge; '
              'the timeline never sees the status change.',
        );
      },
    );

    test(
      'historical replay: snapshot(in_progress) + delta(status→done) '
      'leaves the nested activity stuck at in_progress',
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
              ActivitySnapshotEvent(
                messageId: 'rag:call_1',
                activityType: 'skill_tool_call',
                content: {
                  'tool_name': 'ask',
                  'args': '{"q":"hi"}',
                  'status': 'in_progress',
                },
                timestamp: 100,
              ),
              ActivityDeltaEvent(
                messageId: 'rag:call_1',
                activityType: 'skill_tool_call',
                patch: [
                  {'op': 'replace', 'path': '/status', 'value': 'done'},
                ],
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
        final step = trackers['asst-1']!.timeline.value.single as TimelineStep;

        expect(step.activities, hasLength(1));
        expect(
          step.activities.single.status,
          'done',
          reason: 'Bug 1: ACTIVITY_DELTA patches are dropped during replay; '
              'the nested activity stays at its initial in_progress status.',
        );
      },
    );

    test(
      'live tracker: ActivitySnapshot then ActivityDelta on the same '
      'messageId does not advance the activity to done',
      () {
        final events = Signal<ExecutionEvent?>(null);
        final tracker = ExecutionTracker(
          executionEvents: events,
          logger: testLogger(),
        );
        addTearDown(tracker.dispose);

        // Bridge each AG-UI event through the production bridge, mirroring
        // what AgentSession does at runtime. Anything the bridge drops
        // never reaches the tracker — exactly the bug we're reproducing.
        final ExecutionEvent? snapshot = bridgeBaseEvent(
          const ActivitySnapshotEvent(
            messageId: 'rag:call_1',
            activityType: 'skill_tool_call',
            content: {
              'tool_name': 'ask',
              'args': '{"q":"hi"}',
              'status': 'in_progress',
            },
            timestamp: 100,
          ),
        );
        expect(snapshot, isNotNull);
        events.value = snapshot;

        final ExecutionEvent? delta = bridgeBaseEvent(
          ActivityDeltaEvent(
            messageId: 'rag:call_1',
            activityType: 'skill_tool_call',
            patch: const [
              {'op': 'replace', 'path': '/status', 'value': 'done'},
            ],
            timestamp: 200,
          ),
        );

        expect(
          delta,
          isNotNull,
          reason: 'Bug 1: the bridge drops the delta before it can reach '
              'the live tracker.',
        );
        if (delta != null) events.value = delta;

        final calls = tracker.skillToolCalls.value;
        expect(calls, hasLength(1));
        expect(
          calls.single.status,
          'done',
          reason: 'Bug 1: live tracker never sees the delta-driven '
              'status change; the trailing icon stays as a spinner.',
        );
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
