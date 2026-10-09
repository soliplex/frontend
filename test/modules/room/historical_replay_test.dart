import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/live_session.dart';

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

/// [runs] as the backend serves them back, replayed by the real client.
Future<ThreadHistory> _stored(List<RunEventBundle> runs) => storedHistory([
      for (final run in runs)
        (
          runId: run.runId,
          userMessageId: 'user-${run.runId}',
          prompt: 'Q',
          events: run.events,
        ),
    ]);

void main() {
  setUpAll(registerLiveSessionFallbacks);

  group('replayToTrackers', () {
    test('a reply the history does not show takes no band, though it spoke',
        () async {
      // msg-2 opens while msg-1 is still streaming, so the history shows only
      // msg-2; msg-1's text and end arrive for a stream no longer open. A band
      // keyed to msg-1 would name a tile that is never shown.
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
            TextMessageStartEvent(messageId: 'msg-2'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'Hi'),
            TextMessageEndEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-2', delta: 'Yo'),
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(await _stored(runs));

      expect(trackers.keys, ['msg-2']);
      expect(trackers['msg-2']!.thinkingBlocks.value, ['thinking...']);
    });

    test('measures a step from the run start, not its first bridged event',
        () async {
      // Every timestamp is distinct so the anchor is observable: RUN_STARTED
      // bridges to nothing, so anchoring on the first *bridged* event would
      // start the clock at the tool call and drop the 2.5s before it.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: [
            RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
            const TextMessageStartEvent(messageId: 'msg-1', timestamp: 2000),
            const TextMessageContentEvent(
                messageId: 'msg-1', delta: 'Hi', timestamp: 2000),
            const TextMessageEndEvent(messageId: 'msg-1', timestamp: 2000),
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

      final tracker = replayToTrackers(await _stored(runs))['msg-1']!;

      expect(
        tracker.steps.value.single.timestamp,
        const Duration(milliseconds: 3200),
      );
    });

    test('work a reply inherits keeps the times it was recorded with',
        () async {
      // The run collects what it does before any message speaks, and the reply
      // takes it. The thinking step opens 1.5s after the run started and
      // settles when the reply's first delta lands 5s in; losing the times on
      // the way across would leave it with no offset at all.
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
            const TextMessageContentEvent(
                messageId: 'msg-1', delta: 'Hi', timestamp: 6000),
            const TextMessageEndEvent(messageId: 'msg-1', timestamp: 6000),
          ],
        ),
      ];

      final tracker = replayToTrackers(await _stored(runs))['msg-1']!;

      expect(tracker.steps.value.single.label, 'Thinking');
      expect(
        tracker.steps.value.single.timestamp,
        const Duration(milliseconds: 5000),
      );
    });

    test('tool calls between two assistant messages attach to the first',
        () async {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'Hi'),
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
            TextMessageContentEvent(messageId: 'msg-2', delta: 'Hi'),
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(await _stored(runs));

      expect(trackers.keys, containsAll(['msg-1', 'msg-2']));
      final first = trackers['msg-1']!;
      expect(first.steps.value.map((s) => s.label), ['search']);
      // A reloaded thread must carry the call's detail, not just its name. The
      // args and the start have to land in the same bucket for that to work, so
      // this also pins the bucketing against a row that reloads with a result
      // and no arguments.
      final step = first.timeline.value.single as TimelineStep;
      expect(step.toolCallId, 'tc-1');
      expect(step.args, '{"query":"pumps"}');
      expect(step.result, 'ok');
      final second = trackers['msg-2']!;
      expect(second.steps.value, isEmpty);
    });

    test('a call left open when the stored events run out is failed', () async {
      // No result and no terminal event: the stream broke off. Nothing settled
      // the call, so it must not reload as one that completed.
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'Looking.'),
            TextMessageEndEvent(messageId: 'msg-1'),
            ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'search'),
            ToolCallEndEvent(toolCallId: 'tc-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(await _stored(runs));

      expect(
        trackers['msg-1']!.steps.value.single.status,
        StepStatus.failed,
      );
    });

    test(
        "a run that worked and never spoke keeps its work, rather than "
        "handing it to whatever answers next", () async {
      final runs = [
        RunEventBundle(
          runId: 'run-yield',
          events: const [
            ReasoningMessageStartEvent(messageId: 'r1', timestamp: 1000),
            ReasoningMessageContentEvent(
                messageId: 'r1', delta: 'pre-tool', timestamp: 1100),
            ReasoningMessageEndEvent(messageId: 'r1', timestamp: 1200),
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
            TextMessageContentEvent(messageId: 'asst-1', delta: 'Hi'),
            TextMessageEndEvent(messageId: 'asst-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(await _stored(runs));

      // Two runs, two bands. Giving run-yield's steps to run-resume's reply
      // would file one turn's work above another turn's answer.
      expect(
        trackers.keys,
        containsAll([noResponseMessageId('run-yield'), 'asst-1']),
      );
      expect(
        trackers[noResponseMessageId('run-yield')]!.thinkingBlocks.value,
        ['pre-tool'],
      );
      expect(trackers['asst-1']!.thinkingBlocks.value, isEmpty);
      expect(
        trackers[noResponseMessageId('run-yield')]!
            .steps
            .value
            .map((s) => s.label),
        ['Thinking', 'search'],
      );
      expect(trackers['asst-1']!.steps.value, isEmpty);
    });

    test(
      'a throw inside the bridger drops only that event; surrounding '
      'events still bridge',
      () async {
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
              const TextMessageContentEvent(messageId: 'asst-1', delta: 'Hi'),
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
          await _stored(runs),
          bridge: _bridgerThrowingOn('asst-1'),
        );

        expect(trackers.keys, ['asst-1']);
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
