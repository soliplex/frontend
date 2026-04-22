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

class MockAgentRuntime extends Mock implements AgentRuntime {}

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
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello world'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
    ];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AgentSession createSession({
  required MockSoliplexApi api,
  required MockAgUiStreamClient agUiStreamClient,
  required MockLogger logger,
  AgentRuntime? runtime,
  ToolRegistry? toolRegistry,
}) {
  final registry = toolRegistry ?? const ToolRegistry();
  final orchestrator = RunOrchestrator(
    llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: agUiStreamClient),
    toolRegistry: registry,
    logger: logger,
  );
  return AgentSession(
    threadKey: _key,
    ephemeral: false,
    depth: 0,
    runtime: runtime ?? MockAgentRuntime(),
    orchestrator: orchestrator,
    toolRegistry: registry,
    coordinator: SessionCoordinator(const []),
    logger: logger,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late MockSoliplexApi api;
  late MockAgUiStreamClient agUiStreamClient;
  late MockLogger logger;

  setUp(() {
    api = MockSoliplexApi();
    agUiStreamClient = MockAgUiStreamClient();
    logger = MockLogger();
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

  group('runState signal', () {
    test('initial value is IdleState', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.runState.value, isA<IdleState>());
    });

    test('tracks RunningState -> CompletedState on happy path', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(session.runState.value, isA<CompletedState>());
    });

    test('tracks FailedState on error', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const RunErrorEvent(message: 'backend error'),
        ]),
      );

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(session.runState.value, isA<FailedState>());
    });

    test('tracks CancelledState on cancel', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      session.cancel();
      await session.result;

      expect(session.runState.value, isA<CancelledState>());

      await controller.close();
    });
  });

  group('sessionState signal', () {
    test('initial value is spawning', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.sessionState.value, equals(AgentSessionState.spawning));
    });

    test('tracks spawning -> running -> completed', () async {
      stubCreateRun();

      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.sessionState.value, equals(AgentSessionState.spawning));

      await session.start(userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.sessionState.value, equals(AgentSessionState.running));

      _happyPathEvents().skip(1).forEach(controller.add);
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      expect(session.sessionState.value, equals(AgentSessionState.completed));
    });

    test('tracks failed on error', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const RunErrorEvent(message: 'backend error'),
        ]),
      );

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(session.sessionState.value, equals(AgentSessionState.failed));
    });

    test('tracks cancelled on cancel', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      session.cancel();
      await session.result;

      expect(session.sessionState.value, equals(AgentSessionState.cancelled));

      await controller.close();
    });
  });

  group('signal disposal', () {
    test('both signals disposed when session disposes', () {
      // After dispose, signals retain their last value (frozen).
      // Verified by this not throwing.
      createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      ).dispose();
    });

    test('double dispose is safe', () {
      createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      )
        ..dispose()
        ..dispose(); // Should not throw
    });
  });
}
