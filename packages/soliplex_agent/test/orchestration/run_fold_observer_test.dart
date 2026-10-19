import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

// A live run reports its fold as replay reports a stored one: the run
// starting, each event folded, and how it ended, including the endings that
// arrive with no event.

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class _MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

const ThreadKey _key = (serverId: 'srv', roomId: 'room', threadId: 'thread');

/// Writes down each call, one line per call.
class _RecordingObserver implements RunFoldObserver {
  final List<String> seen = [];

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) => seen.add(
        '${fold.runId} starts'
        '${continuesTurn ? ', continuing its turn' : ''}',
      );

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) =>
      seen.add(processed?.eventType.value ?? 'nothing');

  @override
  void runEnded(RunEnding ending) => seen.add('ends ${ending.name}');
}

/// An observer with a bug: every call throws.
class _ThrowingObserver implements RunFoldObserver {
  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) =>
      throw StateError('observer bug');

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) =>
      throw StateError('observer bug');

  @override
  void runEnded(RunEnding ending) => throw StateError('observer bug');
}

RunStartedEvent _started(String runId) =>
    RunStartedEvent(threadId: 'thread', runId: runId);

RunFinishedEvent _finished(String runId) =>
    RunFinishedEvent(threadId: 'thread', runId: runId);

/// A run that calls the client tool `weather` and finishes on the call.
List<BaseEvent> _callsWeather(String runId) => [
      _started(runId),
      const ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      _finished(runId),
    ];

final ToolRegistry _weather = const ToolRegistry().register(
  ClientTool(
    definition: const Tool(name: 'weather', description: 'Weather'),
    executor: (_, __) async => 'sunny',
  ),
);

Future<List<ToolCallInfo>> _answered(List<ToolCallInfo> pending) async => [
      for (final call in pending)
        call.copyWith(status: ToolCallStatus.completed, result: 'sunny'),
    ];

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late _MockSoliplexApi api;
  late _MockAgUiStreamClient client;
  late _RecordingObserver observer;

  setUp(() {
    api = _MockSoliplexApi();
    client = _MockAgUiStreamClient();
    observer = _RecordingObserver();
  });

  RunOrchestrator orchestratorWith({
    ToolRegistry tools = const ToolRegistry(),
  }) {
    final orchestrator = RunOrchestrator(
      llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: client),
      toolRegistry: tools,
      logger: _MockLogger(),
    );
    addTearDown(orchestrator.dispose);
    return orchestrator;
  }

  /// Each run created is the next of [runs], streaming its events.
  void serve(List<({String runId, Stream<DecodeOutcome> events})> runs) {
    final queue = [...runs];
    final streams = <Stream<DecodeOutcome>>[];
    when(() => api.createRun(any(), any())).thenAnswer((_) async {
      final run = queue.removeAt(0);
      streams.add(run.events);
      return RunInfo(
        id: run.runId,
        threadId: 'thread',
        createdAt: DateTime.utc(2026),
      );
    });
    when(
      () => client.runAgent(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((_) => streams.removeAt(0));
  }

  Stream<DecodeOutcome> decoded(Stream<BaseEvent> events) =>
      events.map<DecodeOutcome>((e) => DecodedEvent(e, const {}));

  Future<RunState> run(
    RunOrchestrator orchestrator, {
    ToolExecutorCallback toolExecutor = _answered,
  }) =>
      orchestrator.runToCompletion(
        key: _key,
        userMessage: [const TextPart('Weather?')],
        toolExecutor: toolExecutor,
        observer: observer,
      );

  /// Starts a run on [events] and lets its first events through.
  Future<Future<RunState>> started(
    RunOrchestrator orchestrator,
    StreamController<BaseEvent> events,
  ) async {
    serve([(runId: 'run-1', events: decoded(events.stream))]);
    final ended = run(orchestrator);
    await Future<void>.delayed(Duration.zero);
    events.add(_started('run-1'));
    await Future<void>.delayed(Duration.zero);
    return ended;
  }

  test('a run its RUN_FINISHED ends completed, after that event', () async {
    serve([
      (
        runId: 'run-1',
        events: decoded(
          Stream.fromIterable([
            _started('run-1'),
            const TextMessageStartEvent(messageId: 'm-1'),
            const TextMessageContentEvent(messageId: 'm-1', delta: 'Sunny'),
            const TextMessageEndEvent(messageId: 'm-1'),
            _finished('run-1'),
          ]),
        ),
      ),
    ]);

    await run(orchestratorWith());

    expect(observer.seen, [
      'run-1 starts',
      'RUN_STARTED',
      'TEXT_MESSAGE_START',
      'TEXT_MESSAGE_CONTENT',
      'TEXT_MESSAGE_END',
      'RUN_FINISHED',
      'ends completed',
    ]);
  });

  test('a run its RUN_ERROR ends failed, after that event', () async {
    serve([
      (
        runId: 'run-1',
        events: decoded(
          Stream.fromIterable([
            _started('run-1'),
            const RunErrorEvent(message: 'boom'),
          ]),
        ),
      ),
    ]);

    await run(orchestratorWith());

    expect(
      observer.seen,
      ['run-1 starts', 'RUN_STARTED', 'RUN_ERROR', 'ends failed'],
    );
  });

  test('an event that could not be read is folded as nothing', () async {
    serve([
      (
        runId: 'run-1',
        events: Stream.fromIterable([
          DecodedEvent(_started('run-1'), const {}),
          const DecodeFailed(
            FormatException('unreadable'),
            {'type': 'TEXT_MESSAGE_CONTENT'},
            StackTrace.empty,
          ),
          DecodedEvent(_finished('run-1'), const {}),
        ]),
      ),
    ]);

    await run(orchestratorWith());

    expect(observer.seen, [
      'run-1 starts',
      'RUN_STARTED',
      'nothing',
      'RUN_FINISHED',
      'ends completed',
    ]);
  });

  test('a run stopped mid-stream ends cancelled, with no event', () async {
    final orchestrator = orchestratorWith();
    final events = StreamController<BaseEvent>();
    addTearDown(events.close);
    final ended = await started(orchestrator, events);

    orchestrator.cancelRun();
    await ended;

    expect(observer.seen, ['run-1 starts', 'RUN_STARTED', 'ends cancelled']);
  });

  test('a run whose stream breaks ends failed, with no event', () async {
    final events = StreamController<BaseEvent>();
    addTearDown(events.close);
    final ended = await started(orchestratorWith(), events);

    events.addError(const NetworkException(message: 'connection reset'));
    await ended;

    expect(observer.seen, ['run-1 starts', 'RUN_STARTED', 'ends failed']);
  });

  test(
      'a run whose stream ends without a terminal event ends failed, as a '
      'followed run ended on its idle bound does', () async {
    final events = StreamController<BaseEvent>();
    final ended = await started(orchestratorWith(), events);

    await events.close();
    await ended;

    expect(observer.seen, ['run-1 starts', 'RUN_STARTED', 'ends failed']);
  });

  test('a run disposed mid-stream ends cancelled, with no event', () async {
    final orchestrator = orchestratorWith();
    final events = StreamController<BaseEvent>();
    addTearDown(events.close);
    final ended = await started(orchestrator, events);

    orchestrator.dispose();
    await ended;

    expect(observer.seen, ['run-1 starts', 'RUN_STARTED', 'ends cancelled']);
  });

  test(
      'a run that waits on a client tool says so, and the run that resumes '
      'the turn continues it', () async {
    serve([
      (
        runId: 'run-1',
        events: decoded(Stream.fromIterable(_callsWeather('run-1')))
      ),
      (
        runId: 'run-2',
        events: decoded(
          Stream.fromIterable([_started('run-2'), _finished('run-2')]),
        ),
      ),
    ]);

    await run(orchestratorWith(tools: _weather));

    expect(observer.seen, [
      'run-1 starts',
      'RUN_STARTED',
      'TOOL_CALL_START',
      'TOOL_CALL_END',
      'RUN_FINISHED',
      'ends waitingOnClientTool',
      'run-2 starts, continuing its turn',
      'RUN_STARTED',
      'RUN_FINISHED',
      'ends completed',
    ]);
  });

  test('a run whose client tool then fails ends again, failed', () async {
    serve([
      (
        runId: 'run-1',
        events: decoded(Stream.fromIterable(_callsWeather('run-1')))
      ),
    ]);

    await run(
      orchestratorWith(tools: _weather),
      toolExecutor: (_) async => throw StateError('tool broke'),
    );

    expect(observer.seen.skip(4), [
      'RUN_FINISHED',
      'ends waitingOnClientTool',
      'ends failed',
    ]);
  });

  test('an observer that throws does not stop the run it watches', () async {
    serve([
      (
        runId: 'run-1',
        events: decoded(
          Stream.fromIterable([_started('run-1'), _finished('run-1')]),
        ),
      ),
    ]);

    final state = await orchestratorWith().runToCompletion(
      key: _key,
      userMessage: [const TextPart('Weather?')],
      toolExecutor: _answered,
      observer: _ThrowingObserver(),
    );

    expect(state, isA<CompletedState>());
  });

  test('a run that could not be started reports nothing', () async {
    when(() => api.createRun(any(), any()))
        .thenThrow(const NetworkException(message: 'unreachable'));

    final state = await run(orchestratorWith());

    expect(state, isA<FailedState>());
    expect(observer.seen, isEmpty);
  });

  test('a followed run reports its fold as a run started here does', () async {
    when(
      () => client.followRun(
        any(),
        'run-1',
        cancelToken: any(named: 'cancelToken'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer(
      (_) =>
          decoded(Stream.fromIterable([_started('run-1'), _finished('run-1')])),
    );

    await orchestratorWith().followToCompletion(
      key: _key,
      run: RunInProgress(
        runId: 'run-1',
        userMessage: TextMessage.create(
          id: 'user-1',
          user: ChatUser.user,
          text: 'Weather?',
          runId: 'run-1',
        ),
      ),
      toolExecutor: _answered,
      cachedHistory: null,
      observer: observer,
    );

    expect(observer.seen, [
      'run-1 starts',
      'RUN_STARTED',
      'RUN_FINISHED',
      'ends completed',
    ]);
  });
}
