import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/replayed_bands.dart';

import '../../helpers/live_session.dart';

/// The bands a reload builds for [runs], each a turn of its own, as the
/// backend serves them back and the real client replays them.
Future<Map<String, ExecutionTracker>> _reloadedBands(
  List<({String runId, List<BaseEvent> events})> runs,
) async {
  final replay = ReplayedBands();
  await storedHistory(observer: replay, [
    for (final (:runId, :events) in runs)
      (
        runId: runId,
        userMessageId: 'user-$runId',
        prompt: 'Q',
        events: events,
      ),
  ]);
  return replay.finish();
}

// What a reload alone decides. Whatever live decides too is compared, live
// against reload, in `live_reload_parity_test.dart` and
// `replay_parity_test.dart`; live times a band by its own clock and a session
// holds one turn, so the step times and a thread of several turns are pinned
// here.
void main() {
  setUpAll(registerLiveSessionFallbacks);

  test('measures a step from the run start, not its first bridged event',
      () async {
    // Every timestamp is distinct so the anchor is observable: RUN_STARTED
    // bridges to nothing, so anchoring on the first *bridged* event, the
    // reply's text at 2000, would drop the 1s before it.
    final bands = await _reloadedBands([
      (
        runId: 'run-1',
        events: [
          RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
          const TextMessageStartEvent(messageId: 'msg-1', timestamp: 2000),
          const TextMessageContentEvent(
            messageId: 'msg-1',
            delta: 'Hi',
            timestamp: 2000,
          ),
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
    ]);

    expect(
      bands['msg-1']!.steps.value.single.timestamp,
      const Duration(milliseconds: 3200),
    );
  });

  test('a step a cut-off run left open settles at its last stored event',
      () async {
    // No terminal event: the stored events run out 5s in, with the thinking
    // step still open. Ending the turn settles it then, at the last event's
    // time, not at whatever the clock read when the history loaded.
    final bands = await _reloadedBands([
      (
        runId: 'run-1',
        events: [
          RunStartedEvent(threadId: 't-1', runId: 'run-1', timestamp: 1000),
          const ReasoningMessageStartEvent(
            messageId: 'reason-1',
            timestamp: 2500,
          ),
          const TextMessageStartEvent(messageId: 'msg-1', timestamp: 6000),
          const TextMessageContentEvent(
            messageId: 'msg-1',
            delta: 'Hi',
            timestamp: 6000,
          ),
          const TextMessageEndEvent(messageId: 'msg-1', timestamp: 6000),
        ],
      ),
    ]);

    final step = bands['msg-1']!.steps.value.single;
    expect(step.label, 'Thinking');
    expect(step.timestamp, const Duration(milliseconds: 5000));
  });

  test(
      'a turn that worked and never spoke keeps its work, rather than '
      'handing it to whatever answers next', () async {
    final bands = await _reloadedBands([
      (
        runId: 'run-quiet',
        events: [
          RunStartedEvent(threadId: 't-1', runId: 'run-quiet'),
          const ReasoningMessageStartEvent(messageId: 'r1'),
          const ReasoningMessageContentEvent(messageId: 'r1', delta: 'pre'),
          const ReasoningMessageEndEvent(messageId: 'r1'),
          const ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
            parentMessageId: 'parent-1',
          ),
          const ToolCallEndEvent(toolCallId: 'tc-1'),
          const ToolCallResultEvent(
            toolCallId: 'tc-1',
            content: 'ok',
            messageId: 'tool-msg-1',
          ),
          const RunFinishedEvent(threadId: 't-1', runId: 'run-quiet'),
        ],
      ),
      (
        runId: 'run-next',
        events: [
          RunStartedEvent(threadId: 't-1', runId: 'run-next'),
          const TextMessageStartEvent(messageId: 'asst-1'),
          const TextMessageContentEvent(messageId: 'asst-1', delta: 'Hi'),
          const TextMessageEndEvent(messageId: 'asst-1'),
          const RunFinishedEvent(threadId: 't-1', runId: 'run-next'),
        ],
      ),
    ]);

    // Two turns, two bands. Giving the quiet turn's steps to the next turn's
    // reply would file one turn's work above another turn's answer.
    final quiet = bands[noResponseMessageId('run-quiet')]!;
    expect(quiet.thinkingBlocks.value, ['pre']);
    expect(quiet.steps.value.map((s) => s.label), ['Thinking', 'search']);
    expect(bands['asst-1']!.thinkingBlocks.value, isEmpty);
    expect(bands['asst-1']!.steps.value, isEmpty);
  });

  test(
      'a run that continues the turn carries it on, though the run before it '
      'stored no end', () async {
    // Replay resumes the turn whenever the next run repeats its message, as
    // the history's messages show it: the waiting run's outcome is taken back.
    // Its work must move to the run that continues it, or it is left keyed to
    // a run with no tile to show it.
    final replay = ReplayedBands();
    Map<String, dynamic> input() => {
          'messages': [
            {'role': 'user', 'id': 'u1', 'content': 'Where am I?'},
          ],
        };
    await storedHistoryFromJson(observer: replay, [
      (
        runId: 'run-waits',
        runInput: input(),
        events: [
          RunStartedEvent(threadId: 't', runId: 'run-waits').toJson(),
          ...[
            const ReasoningMessageStartEvent(messageId: 'r1'),
            const ReasoningMessageContentEvent(
              messageId: 'r1',
              delta: 'need a location',
            ),
            const ReasoningMessageEndEvent(messageId: 'r1'),
            const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'locate'),
            const ToolCallEndEvent(toolCallId: 'c1'),
          ].map((event) => event.toJson()),
        ],
      ),
      (
        runId: 'run-continues',
        runInput: input(),
        events: [
          RunStartedEvent(threadId: 't', runId: 'run-continues').toJson(),
          ...[
            const ReasoningMessageStartEvent(messageId: 'r2'),
            const ReasoningMessageContentEvent(
              messageId: 'r2',
              delta: 'still looking',
            ),
            const ReasoningMessageEndEvent(messageId: 'r2'),
            const RunFinishedEvent(threadId: 't', runId: 'run-continues'),
          ].map((event) => event.toJson()),
        ],
      ),
    ]);
    final bands = replay.finish();

    expect(bands.keys, [noResponseMessageId('run-continues')]);
    expect(
      bands[noResponseMessageId('run-continues')]!.thinkingBlocks.value,
      ['need a location', 'still looking'],
    );
  });

  test('nothing stored after a run finished reaches its band', () async {
    // Live stops reading a run's stream once it has finished.
    final bands = await _reloadedBands([
      (
        runId: 'run-1',
        events: [
          RunStartedEvent(threadId: 't-1', runId: 'run-1'),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Done.'),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 't-1', runId: 'run-1'),
          const ToolCallStartEvent(toolCallId: 'late', toolCallName: 'stray'),
        ],
      ),
    ]);

    expect(bands['msg-1']!.timeline.value, isEmpty);
  });
}
