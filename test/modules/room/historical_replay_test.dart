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
          events: const [
            RunStartedEvent(threadId: 't-1', runId: 'run-1'),
            TextMessageStartEvent(messageId: 'msg-1'),
            TextMessageContentEvent(messageId: 'msg-1', delta: 'hi'),
            TextMessageEndEvent(messageId: 'msg-1'),
            RunFinishedEvent(threadId: 't-1', runId: 'run-1'),
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
      expect(step.activities, hasLength(1));
      expect(step.activities.single.toolName, 'execute_script');
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
            ThinkingTextMessageStartEvent(),
            ThinkingTextMessageContentEvent(delta: 'reasoning'),
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
            ThinkingTextMessageStartEvent(),
            ThinkingTextMessageContentEvent(delta: 'pre-tool'),
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
        'trailing tool-yield bundle with no follow-up drops its hoisted '
        'events without crashing or attaching them to a synthesized id', () {
      // A tool-yield bundle with no normal-bundle follow-up has nowhere
      // to attach its hoisted events. The replay must log the drop and
      // return without crashing.
      final runs = [
        RunEventBundle(
          runId: 'run-yield-only',
          events: const [
            ThinkingTextMessageStartEvent(),
            ThinkingTextMessageContentEvent(delta: 'pre-tool'),
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

      expect(trackers, isEmpty);
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
            ThinkingTextMessageStartEvent(),
            ThinkingTextMessageContentEvent(delta: 'pre-tool'),
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
            ThinkingTextMessageStartEvent(),
            ThinkingTextMessageContentEvent(delta: 'mid'),
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
            events: const [
              RunStartedEvent(threadId: 't-1', runId: 'run-1'),
              ReasoningMessageStartEvent(messageId: 'think-1'),
              ReasoningMessageContentEvent(
                messageId: 'think-1',
                delta: 'reasoning…',
              ),
              ReasoningMessageEndEvent(messageId: 'think-1'),
              TextMessageStartEvent(messageId: 'asst-1'),
              // The bridger throws on this delta.
              TextMessageContentEvent(messageId: 'asst-1', delta: 'poison'),
              // Subsequent events must still bridge.
              TextMessageContentEvent(messageId: 'asst-1', delta: 'survives'),
              TextMessageEndEvent(messageId: 'asst-1'),
              RunFinishedEvent(threadId: 't-1', runId: 'run-1'),
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
