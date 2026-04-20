import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const ThreadKey _key = (
  serverId: 'srv-1',
  roomId: 'room-1',
  threadId: 'thread-1',
);

const _runId = 'run-abc';

RunInfo _runInfo() =>
    RunInfo(id: _runId, threadId: _key.threadId, createdAt: DateTime(2026));

List<BaseEvent> _happyPathEvents() => [
  const RunStartedEvent(threadId: 'thread-1', runId: _runId),
  const TextMessageStartEvent(messageId: 'msg-1'),
  const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
  const TextMessageEndEvent(messageId: 'msg-1'),
  const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
];

List<BaseEvent> _toolCallEvents({String toolName = 'weather'}) => [
  const RunStartedEvent(threadId: 'thread-1', runId: _runId),
  ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: toolName),
  const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"city":"NYC"}'),
  const ToolCallEndEvent(toolCallId: 'tc-1'),
  const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
];

List<BaseEvent> _resumeTextEvents() => [
  const RunStartedEvent(threadId: 'thread-1', runId: _runId),
  const TextMessageStartEvent(messageId: 'msg-2'),
  const TextMessageContentEvent(messageId: 'msg-2', delta: 'Sunny'),
  const TextMessageEndEvent(messageId: 'msg-2'),
  const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
];

ToolRegistry _registryWith({String toolName = 'weather'}) {
  return const ToolRegistry().register(
    ClientTool(
      definition: Tool(name: toolName, description: 'A test tool'),
      executor: (_, __) async => 'result',
    ),
  );
}

List<ToolCallInfo> _executedTools() => [
  const ToolCallInfo(
    id: 'tc-1',
    name: 'weather',
    arguments: '{"city":"NYC"}',
    status: ToolCallStatus.completed,
    result: '72°F, sunny',
  ),
];

Future<List<ToolCallInfo>> _defaultToolExecutor(
  List<ToolCallInfo> pending,
) async {
  return pending
      .map(
        (tc) => tc.copyWith(
          status: ToolCallStatus.completed,
          result: '72°F, sunny',
        ),
      )
      .toList();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late MockSoliplexApi api;
  late MockAgUiStreamClient agUiStreamClient;
  late MockLogger logger;
  late RunOrchestrator orchestrator;

  setUp(() {
    api = MockSoliplexApi();
    agUiStreamClient = MockAgUiStreamClient();
    logger = MockLogger();
  });

  tearDown(() {
    orchestrator.dispose();
  });

  void stubCreateRun() {
    when(() => api.createRun(any(), any())).thenAnswer((_) async => _runInfo());
  }

  void stubRunAgent({required Stream<BaseEvent> stream}) {
    when(
      () => agUiStreamClient.runAgent(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => stream);
  }

  group('runToCompletion', () {
    test('happy path: SSE → CompletedState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      expect(completed.threadKey, equals(_key));
      expect(completed.runId, equals(_runId));
    });

    test('stream error after RunFinished does not change result', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();

      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final resultFuture = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      controller
        ..add(const RunStartedEvent(threadId: 'thread-1', runId: _runId))
        ..add(const TextMessageStartEvent(messageId: 'msg-1'))
        ..add(const TextMessageContentEvent(messageId: 'msg-1', delta: 'Done'))
        ..add(const TextMessageEndEvent(messageId: 'msg-1'))
        ..add(const RunFinishedEvent(threadId: 'thread-1', runId: _runId))
        // TCP close error arrives after terminal event.
        ..addError(const NetworkException(message: 'Connection closed'));
      await controller.close();

      final result = await resultFuture;
      expect(result, isA<CompletedState>());
    });

    test('tool yield: SSE → ToolYielding → resume → Completed', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount == 1
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<CompletedState>());
    });

    test('multiple tool cycles (depth 3)', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        // First 3 calls yield tools, 4th completes with text.
        if (callCount <= 3) {
          return Stream.fromIterable(_toolCallEvents());
        }
        return Stream.fromIterable(_resumeTextEvents());
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<CompletedState>());
      expect(callCount, equals(4));
    });

    test('tool depth exceeded → FailedState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      // Always yield tools — will hit depth limit.
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => Stream.fromIterable(_toolCallEvents()));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<FailedState>());
      final failed = result as FailedState;
      expect(failed.reason, equals(FailureReason.toolExecutionFailed));
      expect(failed.error, contains('depth limit'));
    });

    test('cancel during SSE → CancelledState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final future = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      // Emit RunStarted so we're in RunningState.
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      // Cancel while SSE stream is active.
      orchestrator.cancelRun();

      final result = await future;
      expect(result, isA<CancelledState>());

      await controller.close();
    });

    test('cancel during tool execution → CancelledState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_toolCallEvents()));

      final toolCompleter = Completer<List<ToolCallInfo>>();

      final future = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) => toolCompleter.future,
      );

      // Wait for the tool executor to be called.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Cancel while tool is executing.
      orchestrator.cancelRun();

      // Complete the tool executor — should be ignored.
      toolCompleter.complete(_executedTools());

      final result = await future;
      expect(result, isA<CancelledState>());
    });

    test('dispose during tool execution → CancelledState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_toolCallEvents()));

      final toolCompleter = Completer<List<ToolCallInfo>>();

      final future = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) => toolCompleter.future,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Dispose while tool is executing.
      orchestrator.dispose();

      // Complete the tool executor after dispose.
      toolCompleter.complete(_executedTools());

      final result = await future;
      expect(result, isA<CancelledState>());
    });

    test('tool executor throws → FailedState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_toolCallEvents()));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) async => throw Exception('tool crash'),
      );

      expect(result, isA<FailedState>());
      final failed = result as FailedState;
      expect(failed.reason, equals(FailureReason.toolExecutionFailed));
      expect(failed.error, contains('tool crash'));
    });

    test('resume API throws → FailedState (R4)', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      var callCount = 0;
      when(() => api.createRun(any(), any())).thenAnswer((_) async {
        callCount++;
        if (callCount > 1) throw Exception('resume API error');
        return _runInfo();
      });
      stubRunAgent(stream: Stream.fromIterable(_toolCallEvents()));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<FailedState>());
      final failed = result as FailedState;
      expect(failed.error, contains('resume API error'));
    });
  });

  group('runToCompletion mutual exclusion (R3)', () {
    test('startRun throws during active runToCompletion', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final future = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        () => orchestrator.startRun(key: _key, userMessage: 'Again'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('runToCompletion'),
          ),
        ),
      );

      // Clean up.
      orchestrator.cancelRun();
      await future;
      await controller.close();
    });

    test('submitToolOutputs throws during active runToCompletion', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final future = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        () => orchestrator.submitToolOutputs(_executedTools()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('runToCompletion'),
          ),
        ),
      );

      orchestrator.cancelRun();
      await future;
      await controller.close();
    });
  });

  group('runToCompletion epoch guard', () {
    test('stale onDone from old subscription ignored', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();

      // First stream: yields tools, then closes.
      // Second stream: happy path text.
      var callCount = 0;
      final firstController = StreamController<BaseEvent>();
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        if (callCount == 1) return firstController.stream;
        return Stream.fromIterable(_resumeTextEvents());
      });

      final future = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: _defaultToolExecutor,
      );

      // Emit tool call events on first stream.
      _toolCallEvents().forEach(firstController.add);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // The tool executor runs and resume subscribes to second stream.
      // Now close the first stream (stale onDone).
      await firstController.close();
      await Future<void>.delayed(Duration.zero);

      final result = await future;
      // Should complete successfully — stale onDone was ignored.
      expect(result, isA<CompletedState>());
    });
  });

  group('runToCompletion completer resolution (R1)', () {
    test('completer resolves for CompletedState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<CompletedState>());
    });

    test('completer resolves for FailedState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const RunErrorEvent(message: 'backend error'),
        ]),
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<FailedState>());
    });

    test('completer resolves for CancelledState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.error(const CancellationError('cancelled')));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<CancelledState>());
    });

    test('completer resolves for ToolYieldingState (loop continues)', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount == 1
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      // Verify the intermediate ToolYieldingState was emitted.
      final states = <RunState>[];
      orchestrator.stateChanges.listen(states.add);

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: _defaultToolExecutor,
      );

      expect(result, isA<CompletedState>());
      expect(states.whereType<ToolYieldingState>(), hasLength(1));
    });
  });

  group('runToCompletion cancelToken', () {
    test('cancelToken getter returns active token during run', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_toolCallEvents()));

      CancelToken? captured;
      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (pending) async {
          captured = orchestrator.cancelToken;
          return _defaultToolExecutor(pending);
        },
      );

      // Tool executor captured a non-cancelled token.
      expect(captured, isNotNull);
      expect(captured!.isCancelled, isFalse);
      // After completion, ignore the result type — just ensure no crash.
      expect(result, isA<RunState>());
    });
  });
}
