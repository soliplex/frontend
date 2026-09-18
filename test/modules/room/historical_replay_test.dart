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

/// Returns a bridger that throws on one specific [TextMessageContentEvent]
/// `messageId`. Used to verify the per-event try/catch in
/// `replayToTrackers`.
ExecutionEvent? Function(BaseEvent) _bridgerThrowingOn(String poisonId) {
  return (event) {
    if (event is TextMessageContentEvent && event.messageId == poisonId) {
      throw StateError('bridge simulated failure on $poisonId');
    }
    return bridgeBaseEvent(event);
  };
}

void main() {
  group('unclaimedBands', () {
    ExecutionTracker holdingAStep() => ExecutionTracker.historical(
          events: const [
            (
              event: ServerToolCallStarted(
                toolName: 'search',
                toolCallId: 'tc-1',
              ),
              timestamp: null,
            ),
          ],
          origin: null,
          activities: const [],
          logger: testLogger(),
        );

    test('names a band whose key no shown message carries', () {
      // The band was bucketed for a tile the chat-message side did not
      // synthesize, so nothing will ever render it.
      final trackers = {'no-response-run-1': holdingAStep()};

      expect(unclaimedBands(trackers, const {'msg-1'}), ['no-response-run-1']);
    });

    test('passes over a band a shown message will render', () {
      final trackers = {'msg-1': holdingAStep()};

      expect(unclaimedBands(trackers, const {'msg-1'}), isEmpty);
    });

    test('passes over an empty band, which renders nothing either way', () {
      // Every run ends holding one; they are not a loss to report.
      final trackers = {
        'no-response-run-1': ExecutionTracker.historical(
          events: const [],
          origin: null,
          activities: const [],
          logger: testLogger(),
        ),
      };

      expect(unclaimedBands(trackers, const {'msg-1'}), isEmpty);
    });
  });

  group('replayToTrackers', () {
    test('returns empty map for empty runs', () {
      expect(replayToTrackers(const []), isEmpty);
    });

    test('builds one tracker per assistant message', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-1'),
            const TextMessageStartEvent(messageId: 'msg-1'),
            const TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            const TextMessageEndEvent(messageId: 'msg-1'),
            const RunFinishedEvent(threadId: 't-1', runId: 'run-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      // The reply's band, plus the gap opened after it — which holds only the
      // run's own terminal event and renders nothing, mirroring the empty
      // awaiting tracker the live path leaves behind.
      expect(trackers.keys, ['msg-1', 'no-response-run-1']);
      expect(trackers['msg-1']!.isFrozen, isTrue);
      expect(trackers['no-response-run-1']!.timeline.value, isEmpty);
    });

    test('measures a step from the run start, not its first bridged event', () {
      // Every timestamp is distinct so the anchor is observable: RUN_STARTED
      // bridges to nothing, so anchoring on the first *bridged* event would
      // start the clock at the tool call and drop the 2.5s before it.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
            const TextMessageStartEvent(messageId: 'msg-1', timestamp: 2000),
            const TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            const ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              timestamp: 3500,
            ),
            const ToolCallResultEvent(
              messageId: 'res-1',
              toolCallId: 'tc-1',
              content: 'ok',
              timestamp: 4200,
            ),
            const RunFinishedEvent(
              threadId: 't-1',
              runId: 'run-1',
              timestamp: 4300,
            ),
          ],
        ),
      ];

      final tracker = replayToTrackers(runs)['msg-1']!;

      expect(
        tracker.steps.value.single.timestamp,
        const Duration(milliseconds: 3200),
      );
    });

    test('a thinking step flushed from pending keeps its own emission time',
        () {
      // Events before TEXT_MESSAGE_START are hoisted through `pending` and
      // drained into the reply's bucket. The thinking step opens 1.5s after
      // the run started, and `freeze` settles it there because no later
      // bridged event carries a time; dropping the time on the pending path
      // would leave it with no offset at all.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
            const ReasoningMessageStartEvent(
              messageId: 'reason-1',
              timestamp: 2500,
            ),
            const TextMessageStartEvent(messageId: 'msg-1', timestamp: 6000),
            const TextMessageEndEvent(messageId: 'msg-1', timestamp: 6000),
          ],
        ),
      ];

      // The message never carries text, so it opens no bucket and the run
      // buckets as a no-response.
      final tracker = replayToTrackers(runs)['no-response-run-1']!;

      expect(tracker.steps.value.single.label, 'Thinking');
      expect(
        tracker.steps.value.single.timestamp,
        const Duration(milliseconds: 1500),
      );
    });

    test('a later run is anchored on its own start, not an earlier run\'s', () {
      // The hoisted raw events are cleared once drained. Left in place they
      // prepend to every later bucket, anchoring a reply on a run that ended
      // a minute earlier and folding that run's activities into its tracker.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
            const ActivitySnapshotEvent(
              messageId: 'bwrap:call_1',
              activityType: 'skill_tool_call',
              content: {'tool_name': 'execute_script', 'args': '{}'},
              timestamp: 1050,
            ),
            const TextMessageStartEvent(messageId: 'msg-1', timestamp: 1100),
            const TextMessageEndEvent(messageId: 'msg-1', timestamp: 1200),
          ],
        ),
        RunEventBundle(
          runId: 'run-2',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-2', timestamp: 60000),
            const ReasoningMessageStartEvent(
              messageId: 'reason-2',
              timestamp: 60500,
            ),
            const TextMessageStartEvent(messageId: 'msg-2', timestamp: 61000),
            const TextMessageEndEvent(messageId: 'msg-2', timestamp: 61000),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      // Neither message carries text, so each run buckets under its own
      // no-response key; the anchor arithmetic is what this pins.
      expect(
        trackers['no-response-run-2']!.steps.value.single.timestamp,
        const Duration(milliseconds: 500),
      );
      expect(trackers['no-response-run-1']!.activities.value, hasLength(1));
      expect(trackers['no-response-run-2']!.activities.value, isEmpty);
    });

    test('thinking events before TEXT_MESSAGE_START attach to that message',
        () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            ReasoningMessageStartEvent(messageId: 'reason-1'),
            ReasoningMessageContentEvent(
              messageId: 'reason-1',
              delta: 'thinking...',
            ),
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            TextMessageEndEvent(messageId: 'msg-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);
      final tracker = trackers['msg-1']!;

      expect(tracker.steps.value, hasLength(1));
      expect(tracker.steps.value.first.label, 'Thinking');
      expect(tracker.thinkingBlocks.value, ['thinking...']);
    });

    test('tool calls between two assistant messages attach to the second', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            TextMessageEndEvent(messageId: 'msg-1'),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
            ),
            ToolCallArgsEvent(
              toolCallId: 'tc-1',
              delta: '{"query":"pumps"}',
            ),
            ToolCallResultEvent(
              messageId: 'result-1',
              toolCallId: 'tc-1',
              content: 'ok',
            ),
            TextMessageStartEvent(messageId: 'msg-2'),
            TextMessageContentEvent(messageId: 'msg-2', delta: 'hi'),
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, containsAll(['msg-1', 'msg-2']));
      // The work happened after the first reply and before the second, so it
      // belongs to the band above the second — the order it is read in.
      expect(trackers['msg-1']!.steps.value, isEmpty);
      final second = trackers['msg-2']!;
      expect(second.steps.value.map((s) => s.label), ['search']);
      // A reloaded thread must carry the call's detail, not just its name. The
      // args and the start have to land in the same bucket for that to work, so
      // this also pins the bucketing against a row that reloads with a result
      // and no arguments.
      final step = second.timeline.value.single as TimelineStep;
      expect(step.toolCallId, 'tc-1');
      expect(step.args, '{"query":"pumps"}');
      expect(step.result, 'ok');
    });

    test('a message that never speaks yields no bucket of its own', () {
      // A response beginning with a tool call opens and closes a message with
      // no content, purely to name that call's parent. Its stretch belongs to
      // the reply that follows.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'decl-1'),
            TextMessageEndEvent(messageId: 'decl-1'),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'decl-1',
            ),
            ToolCallEndEvent(toolCallId: 'tc-1'),
            TextMessageStartEvent(messageId: 'msg-2'),
            TextMessageContentEvent(messageId: 'msg-2', delta: 'the answer'),
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, ['msg-2']);
      expect(trackers['msg-2']!.steps.value.map((s) => s.label), ['search']);
    });

    // A bundle that never spoke keeps what it collected under its own run's
    // no-response key, whatever ended it. Replay has no signal for "the turn
    // continued in the next run" — a continuation declares `parent_run_id`
    // and this client neither sets nor reads it — so deciding from the shape
    // of the events was a guess, and every way it guessed wrong put one
    // question's work above the answer to the question asked after it. That
    // lands on a message the thread shows, so nothing reported it. The live
    // path carries no band across a run either, which is what keeps the two
    // implementations agreeing.
    for (final (ended, tail) in <(String, List<BaseEvent>)>[
      ('errored', [const RunErrorEvent(message: 'upstream timed out')]),
      ('cut off before any terminal', []),
      (
        'finished with the call still open',
        [const RunFinishedEvent(threadId: 't', runId: 'run-1')],
      ),
    ]) {
      test('a run that only declares and $ended keeps its own work', () {
        final runs = [
          RunEventBundle(
            runId: 'run-1',
            events: <BaseEvent>[
              const TextMessageStartEvent(messageId: 'decl-1'),
              const TextMessageEndEvent(messageId: 'decl-1'),
              const ToolCallStartEvent(
                toolCallId: 'tc-1',
                toolCallName: 'search',
                parentMessageId: 'decl-1',
              ),
              const ToolCallEndEvent(toolCallId: 'tc-1'),
              ...tail,
            ],
          ),
          RunEventBundle(
            runId: 'run-2',
            events: const [
              TextMessageStartEvent(messageId: 'msg-2'),
              TextMessageContentEvent(
                messageId: 'msg-2',
                delta: 'an answer to a different question',
              ),
              TextMessageEndEvent(messageId: 'msg-2'),
            ],
          ),
        ];

        final trackers = replayToTrackers(runs);

        expect(
          trackers['msg-2']?.steps.value.map((s) => s.label) ?? const [],
          isEmpty,
          reason: 'the abandoned run\'s search must not appear above an '
              'unrelated answer',
        );
        expect(
          trackers[noResponseMessageId('run-1')]
              ?.steps
              .value
              .map((s) => s.label),
          ['search'],
          reason: 'it belongs to the run that did the work, which is where '
              'the live path puts it',
        );
      });
    }

    test('a whitespace delta does not count as speaking', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'decl-1'),
            TextMessageContentEvent(messageId: 'decl-1', delta: ' '),
            TextMessageEndEvent(messageId: 'decl-1'),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'decl-1',
            ),
            ToolCallEndEvent(toolCallId: 'tc-1'),
            TextMessageStartEvent(messageId: 'msg-2'),
            TextMessageContentEvent(messageId: 'msg-2', delta: 'the answer'),
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      // No bucket of its own: the band belongs to the reply that follows.
      expect(trackers.keys, equals(['msg-2']));
      expect(trackers['msg-2']!.steps.value.map((s) => s.label), ['search']);
    });

    test('an empty delta does not count as speaking', () {
      // START → CONTENT("") → END leaves the message empty, so it classifies
      // as a declaration exactly as START → END does.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'decl-1'),
            TextMessageContentEvent(messageId: 'decl-1', delta: ''),
            TextMessageEndEvent(messageId: 'decl-1'),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'decl-1',
            ),
            ToolCallEndEvent(toolCallId: 'tc-1'),
            TextMessageStartEvent(messageId: 'msg-2'),
            TextMessageContentEvent(messageId: 'msg-2', delta: 'the answer'),
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, ['msg-2']);
    });

    test('work after the last reply buckets under the run, not dropped', () {
      // Nothing speaks for it, so it routes to the run's no-response key —
      // where the synthesized tile is, when there is one.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'on it'),
            TextMessageEndEvent(messageId: 'msg-1'),
            ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'search'),
            ToolCallEndEvent(toolCallId: 'tc-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(
        trackers['no-response-run-1']!.steps.value.map((s) => s.label),
        ['search'],
      );
    });

    test('a run anchors on its own start when an earlier run also spoke', () {
      // A reply's stretch ends when it speaks, so what follows it belongs to
      // its own run. Carrying it into the next run would anchor that run's
      // band on the previous one's finish, inflating every offset in it by
      // however long the user took to ask again.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
            const TextMessageStartEvent(messageId: 'msg-1', timestamp: 1100),
            const TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            const TextMessageEndEvent(messageId: 'msg-1', timestamp: 1200),
            const RunFinishedEvent(
                threadId: 't-1', runId: 'run-1', timestamp: 1300),
          ],
        ),
        RunEventBundle(
          runId: 'run-2',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-2', timestamp: 60000),
            const ReasoningMessageStartEvent(
              messageId: 'reason-2',
              timestamp: 60500,
            ),
            const TextMessageStartEvent(messageId: 'msg-2', timestamp: 61000),
            const TextMessageContentEvent(
              messageId: 'msg-2',
              delta: 'answer',
              timestamp: 61050,
            ),
            const TextMessageEndEvent(messageId: 'msg-2', timestamp: 61100),
            const RunFinishedEvent(
                threadId: 't-1', runId: 'run-2', timestamp: 61200),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(
        trackers['msg-2']!.steps.value.single.timestamp,
        const Duration(milliseconds: 1050),
      );
    });

    test('activity nests under its surrounding tool-call step', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'execute_skill',
            ),
            ActivitySnapshotEvent(
              messageId: 'bwrap:call_1',
              activityType: 'skill_tool_call',
              content: {
                'tool_name': 'execute_script',
                'args': '{"script":"print(1)"}',
              },
              timestamp: 100,
            ),
            ToolCallResultEvent(
              messageId: 'result-1',
              toolCallId: 'tc-1',
              content: 'ok',
            ),
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            TextMessageEndEvent(messageId: 'msg-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);
      final tracker = trackers['msg-1']!;
      final entries = tracker.timeline.value;

      expect(entries, hasLength(1));
      final step = entries.single as TimelineStep;
      expect(step.step.label, 'execute_skill');
      expect(step.activityIds, hasLength(1));
      expect(
        tracker.activities.value.single.content['tool_name'],
        'execute_script',
      );
    });

    test(
        'no-response bundle (no assistant text, no tool call) produces a '
        'tracker keyed under the no-response id so its thinking attaches '
        'to the synthesized tile', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(
              messageId: 'user-1',
              role: TextMessageRole.user,
              timestamp: 1000,
            ),
            TextMessageEndEvent(messageId: 'user-1', timestamp: 1000),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageStartEvent(timestamp: 2000),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageContentEvent(
                delta: 'reasoning', timestamp: 2100),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageEndEvent(timestamp: 2200),
            RunFinishedEvent(threadId: 't', runId: 'run-1', timestamp: 4000),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, contains('no-response-run-1'));
      expect(trackers['no-response-run-1']!.thinkingBlocks.value, [
        'reasoning',
      ]);
      // Anchored on the bundle's first stored event, so this branch's
      // timestamp forward is observable: the thinking step opens 1s in and
      // RUN_FINISHED settles it at 3s.
      expect(
        trackers['no-response-run-1']!.steps.value.single.timestamp,
        const Duration(milliseconds: 3000),
      );
    });

    test('a bundle that yielded to a tool keeps its work under its own run',
        () {
      // A turn that continues in a second run is the one case the old
      // cross-bundle hoist served, and it cost more than it bought: replay
      // cannot tell a continuation from the next question the user typed,
      // because a continuation declares `parent_run_id` and this client
      // neither sets nor reads it. Guessing from the event shape put an
      // abandoned run's work above an unrelated answer. So the band stays
      // with the run that did it; if no tile is synthesized there,
      // `unclaimedBands` reports it rather than attaching it to a stranger.
      final runs = [
        RunEventBundle(
          runId: 'run-yield',
          events: const [
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageStartEvent(timestamp: 1000),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageContentEvent(delta: 'pre-tool', timestamp: 1100),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageEndEvent(timestamp: 1200),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'parent-1',
              timestamp: 3500,
            ),
            ToolCallEndEvent(toolCallId: 'tc-1', timestamp: 3600),
            ToolCallResultEvent(
              toolCallId: 'tc-1',
              content: 'ok',
              messageId: 'tool-msg-1',
            ),
          ],
        ),
        RunEventBundle(
          runId: 'run-resume',
          events: const [
            TextMessageStartEvent(messageId: 'asst-1'),
            TextMessageContentEvent(messageId: 'asst-1', delta: 'hi'),
            TextMessageEndEvent(messageId: 'asst-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(
        trackers['no-response-run-yield']!.thinkingBlocks.value,
        ['pre-tool'],
      );
      expect(
        trackers['no-response-run-yield']!.steps.value.map((s) => s.label),
        ['Thinking', 'search'],
      );
      expect(trackers['asst-1']!.thinkingBlocks.value, isEmpty);
      expect(trackers['asst-1']!.steps.value, isEmpty);
    });

    test(
        'trailing tool-yield bundle with no follow-up routes its hoisted '
        'events under the synthesized no-response id for the same run', () {
      // A tool-yield bundle with no normal-bundle follow-up still needs
      // a tracker on reload: the chat-message side synthesizes a
      // no-response tile under `noResponseMessageId(runId)` for the
      // same run, and the bubble disappears if no tracker is keyed
      // under that id.
      final runs = [
        RunEventBundle(
          runId: 'run-yield-only',
          events: const [
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageStartEvent(timestamp: 1000),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageContentEvent(delta: 'pre-tool', timestamp: 1100),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageEndEvent(timestamp: 1200),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'parent-1',
              timestamp: 3500,
            ),
            ToolCallEndEvent(toolCallId: 'tc-1', timestamp: 3600),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, ['no-response-run-yield-only']);
      expect(
        trackers['no-response-run-yield-only']!.steps.value.map((s) => s.label),
        ['Thinking', 'search'],
      );
      // Offsets are measured from the bundle's first stored event, so the
      // hoisted branch's timestamp forward is observable here. Both settle at
      // the tool call's own start: TOOL_CALL_END carries no execution step, so
      // it never moves the offset, and `freeze` settles `search` where the
      // last event that did left it.
      expect(
        trackers['no-response-run-yield-only']!
            .steps
            .value
            .map((s) => s.timestamp),
        const [Duration(milliseconds: 2500), Duration(milliseconds: 2500)],
      );
      expect(
        trackers['no-response-run-yield-only']!.thinkingBlocks.value,
        ['pre-tool'],
      );
    });

    test(
        'tool-yield -> no-response -> normal sequence: hoisted pre-tool '
        'events attach to the no-response tracker, not to the next normal '
        "bundle's assistant tracker", () {
      // Three runs in a row where only the last one speaks. Each keeps the
      // thinking it produced, so none of it reaches the reply at the end —
      // mis-attributing one run's reasoning to a later run's answer is
      // invisible on screen, because the band lands on a message the thread
      // shows and the invariant check sees nothing wrong.
      final runs = [
        RunEventBundle(
          runId: 'run-yield',
          events: const [
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageStartEvent(),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageContentEvent(delta: 'pre-tool'),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageEndEvent(),
            ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'search'),
            ToolCallEndEvent(toolCallId: 'tc-1'),
            ToolCallResultEvent(
              toolCallId: 'tc-1',
              content: 'ok',
              messageId: 'tool-msg-1',
            ),
          ],
        ),
        RunEventBundle(
          runId: 'run-no-response',
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
            RunFinishedEvent(threadId: 't', runId: 'run-no-response'),
          ],
        ),
        RunEventBundle(
          runId: 'run-resume',
          events: const [
            TextMessageStartEvent(messageId: 'asst-1'),
            TextMessageContentEvent(messageId: 'asst-1', delta: 'hi'),
            TextMessageEndEvent(messageId: 'asst-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(
        trackers.keys,
        containsAll([
          'no-response-run-yield',
          'no-response-run-no-response',
          'asst-1',
        ]),
      );
      expect(
        trackers['no-response-run-yield']!.thinkingBlocks.value,
        ['pre-tool'],
      );
      expect(
        trackers['no-response-run-no-response']!.thinkingBlocks.value,
        ['mid'],
      );
      expect(trackers['asst-1']!.thinkingBlocks.value, isEmpty);
      expect(trackers['asst-1']!.steps.value, isEmpty);
    });

    test('multi-run thread yields one tracker per assistant message', () {
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
          runId: 'run-2',
          events: const [
            ReasoningMessageStartEvent(messageId: 'r-1'),
            ReasoningMessageContentEvent(messageId: 'r-1', delta: 'go'),
            TextMessageStartEvent(messageId: 'asst-2'),
            TextMessageContentEvent(messageId: 'asst-2', delta: 'hi'),
            TextMessageEndEvent(messageId: 'asst-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, ['asst-1', 'asst-2']);
      expect(trackers['asst-1']!.steps.value, isEmpty);
      expect(trackers['asst-2']!.steps.value, hasLength(1));
    });

    test(
      'a throw inside the bridger drops only that event; surrounding '
      'events still bridge',
      () {
        final runs = [
          RunEventBundle(
            runId: 'run-1',
            events: [
              RunStartedEvent(threadId: 't-1', runId: 'run-1'),
              const ReasoningMessageStartEvent(messageId: 'think-1'),
              const ReasoningMessageContentEvent(
                messageId: 'think-1',
                delta: 'reasoning…',
              ),
              const ReasoningMessageEndEvent(messageId: 'think-1'),
              const TextMessageStartEvent(messageId: 'asst-1'),
              const TextMessageContentEvent(messageId: 'asst-1', delta: 'hi'),
              // The bridger throws on this delta.
              const TextMessageContentEvent(
                messageId: 'asst-1',
                delta: 'poison',
              ),
              // Subsequent events must still bridge.
              const TextMessageContentEvent(
                messageId: 'asst-1',
                delta: 'survives',
              ),
              const TextMessageEndEvent(messageId: 'asst-1'),
              const RunFinishedEvent(threadId: 't-1', runId: 'run-1'),
            ],
          ),
        ];

        final trackers = replayToTrackers(
          runs,
          bridge: _bridgerThrowingOn('asst-1'),
        );

        expect(trackers.keys, ['asst-1', 'no-response-run-1']);
        final tracker = trackers['asst-1']!;
        // The thinking step bridged before the poison event.
        expect(tracker.steps.value, hasLength(1));
        expect(tracker.steps.value.first.label, 'Thinking');
        // The thinking content survived.
        expect(tracker.thinkingBlocks.value, ['reasoning…']);
      },
    );
  });
}
