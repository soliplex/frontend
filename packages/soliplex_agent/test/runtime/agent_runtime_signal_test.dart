import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
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

const _roomId = 'room-1';
const _threadId = 'thread-1';
const _runId = 'run-abc';

ThreadInfo _threadInfo() =>
    ThreadInfo(id: _threadId, roomId: _roomId, createdAt: DateTime(2026));

RunInfo _runInfo() =>
    RunInfo(id: _runId, threadId: _threadId, createdAt: DateTime(2026));

List<BaseEvent> _happyPathEvents() => [
  const RunStartedEvent(threadId: _threadId, runId: _runId),
  const TextMessageStartEvent(messageId: 'msg-1'),
  const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
  const TextMessageEndEvent(messageId: 'msg-1'),
  const RunFinishedEvent(threadId: _threadId, runId: _runId),
];

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late MockSoliplexApi api;
  late MockAgUiStreamClient agUiStreamClient;
  late MockLogger logger;
  late AgentRuntime runtime;

  AgentRuntime createRuntime() {
    return AgentRuntime(
      connection: ServerConnection(
        serverId: 'default',
        api: api,
        agUiStreamClient: agUiStreamClient,
      ),
      llmProvider: AgUiLlmProvider(
        api: api,
        agUiStreamClient: agUiStreamClient,
      ),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      platform: const NativePlatformConstraints(),
      logger: logger,
    );
  }

  setUp(() {
    api = MockSoliplexApi();
    agUiStreamClient = MockAgUiStreamClient();
    logger = MockLogger();
    runtime = createRuntime();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  void stubCreateThread() {
    when(
      () => api.createThread(any()),
    ).thenAnswer((_) async => (_threadInfo(), <String, dynamic>{}));
  }

  void stubCreateRun() {
    when(() => api.createRun(any(), any())).thenAnswer((_) async => _runInfo());
  }

  void stubDeleteThread() {
    when(() => api.deleteThread(any(), any())).thenAnswer((_) async {});
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

  group('sessions signal', () {
    test('initial value is empty list', () {
      expect(runtime.sessions.value, isEmpty);
    });

    test('updates on spawn', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      expect(runtime.sessions.value, hasLength(1));

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await controller.close();
    });

    test('updates on session completion', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Hello',
        autoDispose: true,
      );

      expect(runtime.sessions.value, hasLength(1));

      await session.result;
      // Allow completion handler to run
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.sessions.value, isEmpty);
    });

    test('value matches activeSessions getter', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      expect(runtime.sessions.value, equals(runtime.activeSessions));

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await controller.close();
    });

    test('disposed signal retains last value', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'Hello');
      final valueBeforeDispose = runtime.sessions.value;
      expect(valueBeforeDispose, hasLength(1));

      await runtime.dispose();

      // After dispose, signal retains its last value (frozen)
      expect(runtime.sessions.value, hasLength(1));

      await controller.close();
    });

    test('signal and stream emit in same order', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final streamEmissions = <int>[];
      runtime.sessionChanges.listen((list) => streamEmissions.add(list.length));

      await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      // Signal reflects spawn immediately
      expect(runtime.sessions.value, hasLength(1));

      // Wait for stream to catch up
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Stream should have emitted at least the spawn event
      expect(streamEmissions, isNotEmpty);
      // First emission is the spawn (length 1)
      expect(streamEmissions.first, equals(1));
    });
  });
}
