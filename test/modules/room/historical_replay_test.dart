import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

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

    test('runs with no assistant message produce no tracker', () {
      final runs = [
        RunEventBundle(
          runId: 'run-1',
          events: const [
            TextMessageStartEvent(
                messageId: 'user-1', role: TextMessageRole.user),
            TextMessageEndEvent(messageId: 'user-1'),
          ],
        ),
      ];

      expect(replayToTrackers(runs), isEmpty);
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
  });
}
