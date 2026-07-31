// These fixtures construct ag_ui 0.3.0's deprecated THINKING_TEXT_MESSAGE_*
// and THINKING_CONTENT events, exercising handling that is kept because a
// producer negotiating ag-ui-protocol below 0.1.13 emits that family live.
// Removal at ag_ui 1.0.0 surfaces as a compile error at these constructors.

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

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

      expect(trackers.keys, ['msg-1']);
      expect(trackers['msg-1']!.isFrozen, isTrue);
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

    test('tool calls between two assistant messages attach to the first', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'msg-1'),
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
            TextMessageEndEvent(messageId: 'msg-2'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

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

    test('activity nests under its surrounding tool-call step', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageEndEvent(messageId: 'msg-1'),
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
      expect(tracker.skillToolCalls.value.single.toolName, 'execute_script');
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
            ),
            TextMessageEndEvent(messageId: 'user-1'),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageStartEvent(),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageContentEvent(delta: 'reasoning'),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageEndEvent(),
            RunFinishedEvent(threadId: 't', runId: 'run-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, contains('no-response-run-1'));
      expect(trackers['no-response-run-1']!.thinkingBlocks.value, [
        'reasoning',
      ]);
    });

    test(
        "tool-yield bundle's events forward into the next normal "
        "bundle's first assistant tracker", () {
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
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'parent-1',
            ),
            ToolCallEndEvent(toolCallId: 'tc-1'),
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
            TextMessageEndEvent(messageId: 'asst-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, ['asst-1']);
      expect(trackers['asst-1']!.thinkingBlocks.value, ['pre-tool']);
      expect(
        trackers['asst-1']!.steps.value.map((s) => s.label),
        ['Thinking', 'search'],
      );
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
            ThinkingTextMessageStartEvent(),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageContentEvent(delta: 'pre-tool'),
            // Deprecated upstream; exercises the pre-REASONING_* replay path.
            // ignore: deprecated_member_use
            ThinkingTextMessageEndEvent(),
            ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'search',
              parentMessageId: 'parent-1',
            ),
            ToolCallEndEvent(toolCallId: 'tc-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(trackers.keys, ['no-response-run-yield-only']);
      expect(
        trackers['no-response-run-yield-only']!.steps.value.map((s) => s.label),
        ['Thinking', 'search'],
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
      // Without `pending.clear()` in the no-response branch, pre-tool
      // events from the tool-yield bundle would leak through the
      // no-response bundle into the next normal bundle's assistant
      // tracker — silently mis-attributing thinking from one run's
      // tool-yield to a later run's reply.
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
            TextMessageEndEvent(messageId: 'asst-1'),
          ],
        ),
      ];

      final trackers = replayToTrackers(runs);

      expect(
        trackers.keys,
        containsAll(['no-response-run-no-response', 'asst-1']),
      );
      // The no-response tracker absorbs the hoisted pre-tool events plus
      // its own mid thinking — so the next normal bundle starts clean.
      expect(
        trackers['no-response-run-no-response']!.thinkingBlocks.value,
        ['pre-tool', 'mid'],
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
            TextMessageEndEvent(messageId: 'asst-1'),
          ],
        ),
        RunEventBundle(
          runId: 'run-2',
          events: const [
            ReasoningMessageStartEvent(messageId: 'r-1'),
            ReasoningMessageContentEvent(messageId: 'r-1', delta: 'go'),
            TextMessageStartEvent(messageId: 'asst-2'),
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
