import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../helpers/live_session.dart';

// Bands are built from the steps of each run's fold: live from the stream, on
// reload from the stored events. Each case here feeds the same events, as the
// JSON the backend sends and stores, to both, and expects the band builder to
// be told the same calls in the same order.

const ThreadKey _key = (serverId: 'srv', roomId: 'r', threadId: 't');

/// Writes down each call, with what the band builder reads from it.
class _RecordingObserver implements RunFoldObserver {
  final List<String> seen = [];

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) => seen.add(
        '${fold.runId} starts${continuesTurn ? ', continuing its turn' : ''}, '
        '${_streaming(fold)}',
      );

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) => seen.add(
        '${processed?.eventType.value ?? 'nothing'}, ${_streaming(fold)}',
      );

  @override
  void runEnded(RunEnding ending) => seen.add('ends ${ending.name}');

  static String _streaming(RunFold fold) => '${switch (fold.streaming) {
        AwaitingText() => 'awaiting',
        TextStreaming(:final text) => 'streaming "$text"',
      }}, ${fold.conversation.activities.length} activities';
}

Map<String, dynamic> _runStarted(String runId) =>
    RunStartedEvent(threadId: 't', runId: runId).toJson();

Map<String, dynamic> _runFinished(String runId) =>
    RunFinishedEvent(threadId: 't', runId: runId).toJson();

List<Map<String, dynamic>> _reply(String messageId, String text) => [
      TextMessageStartEvent(messageId: messageId).toJson(),
      TextMessageContentEvent(messageId: messageId, delta: text).toJson(),
      TextMessageEndEvent(messageId: messageId).toJson(),
    ];

List<Map<String, dynamic>> _call(String toolCallId, String name) => [
      ToolCallStartEvent(toolCallId: toolCallId, toolCallName: name).toJson(),
      ToolCallArgsEvent(toolCallId: toolCallId, delta: '{}').toJson(),
      ToolCallEndEvent(toolCallId: toolCallId).toJson(),
    ];

void main() {
  setUpAll(registerLiveSessionFallbacks);

  /// Runs [runs] live, one backend run per entry, then reloads them as the
  /// backend stored them, and expects the fold steps of both to be the same.
  Future<void> expectSameSteps(
    Map<String, List<Map<String, dynamic>>> runs, {
    ToolRegistry toolRegistry = const ToolRegistry(),
  }) async {
    final [MapEntry(key: runId, value: events), ...later] =
        runs.entries.toList();
    final live = startLiveSession(
      key: _key,
      runId: runId,
      toolRegistry: toolRegistry,
      laterRuns: [
        for (final MapEntry(key: runId, value: events) in later)
          (runId: runId, events: events),
      ],
    );
    addTearDown(live.session.dispose);
    final liveSteps = _RecordingObserver();
    live.session.observeRunFold(liveSteps);
    await Future<void>.delayed(Duration.zero);
    events.forEach(live.events.add);
    await live.events.close();
    await live.session.result;

    final reloadSteps = _RecordingObserver();
    await storedHistoryFromJson(observer: reloadSteps, [
      for (final (index, MapEntry(key: runId, value: events))
          in runs.entries.indexed)
        (runId: runId, runInput: live.sent[index].toJson(), events: events),
    ]);

    expect(liveSteps.seen, isNotEmpty);
    expect(reloadSteps.seen, liveSteps.seen);
  }

  test('a run that replies, calls a server tool, and finishes', () async {
    await expectSameSteps({
      'run-1': [
        _runStarted('run-1'),
        ..._reply('m-1', 'Let me look.'),
        ..._call('c-1', 'search'),
        ToolCallResultEvent(
          messageId: 'tr-1',
          toolCallId: 'c-1',
          content: 'found',
        ).toJson(),
        ActivitySnapshotEvent(
          messageId: 'act-1',
          activityType: 'progress',
          content: const {'tool_call_id': 'c-1', 'step': 1},
        ).toJson(),
        ..._reply('m-2', 'Found it.'),
        _runFinished('run-1'),
      ],
    });
  });

  test('a run its RUN_ERROR ends mid-reply', () async {
    await expectSameSteps({
      'run-1': [
        _runStarted('run-1'),
        TextMessageStartEvent(messageId: 'm-1').toJson(),
        TextMessageContentEvent(messageId: 'm-1', delta: 'Half').toJson(),
        RunErrorEvent(message: 'boom').toJson(),
      ],
    });
  });

  test('a run cut off mid-reply', () async {
    await expectSameSteps({
      'run-1': [
        _runStarted('run-1'),
        TextMessageStartEvent(messageId: 'm-1').toJson(),
        TextMessageContentEvent(messageId: 'm-1', delta: 'Half').toJson(),
      ],
    });
  });

  test('a run with an event that could not be read', () async {
    await expectSameSteps({
      'run-1': [
        _runStarted('run-1'),
        {'type': 'TEXT_MESSAGE_CONTENT'},
        ..._reply('m-1', 'Done.'),
        _runFinished('run-1'),
      ],
    });
  });

  test('a turn that waits on a client tool and is resumed', () async {
    await expectSameSteps(
      {
        'run-1': [
          _runStarted('run-1'),
          ..._call('c-1', 'weather'),
          _runFinished('run-1'),
        ],
        'run-2': [
          _runStarted('run-2'),
          ..._reply('m-1', 'Sunny.'),
          _runFinished('run-2'),
        ],
      },
      toolRegistry: const ToolRegistry().register(
        ClientTool(
          definition: const Tool(name: 'weather', description: 'Weather'),
          executor: (_, __) async => 'sunny',
        ),
      ),
    );
  });
}
