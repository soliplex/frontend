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

const _roomA = 'room-a';
const _roomB = 'room-b';
const _threadId = 'thread-1';
const _runId = 'run-abc';

ThreadInfo _threadInfo({String id = _threadId}) =>
    ThreadInfo(id: id, roomId: _roomA, createdAt: DateTime(2026));

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

  AgentRuntime createRuntime({PlatformConstraints? platform}) {
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
      platform: platform ?? const NativePlatformConstraints(),
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

  void stubCreateThread({String id = _threadId}) {
    when(
      () => api.createThread(any()),
    ).thenAnswer((_) async => (_threadInfo(id: id), <String, dynamic>{}));
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
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((_) => stream);
  }

  group('parent-child ownership', () {
    test('spawn with parent registers child', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      final child = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Sub-task',
        parent: parent,
      );

      expect(parent.children, contains(child));
      expect(parent.children, hasLength(1));

      // Both tracked in runtime flat index
      expect(runtime.activeSessions, contains(parent));
      expect(runtime.activeSessions, contains(child));

      _happyPathEvents().forEach(controller.add);
      await controller.close();
    });

    test('spawnChild delegates to runtime with parent', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      final child = await parent.spawnChild(roomId: _roomA, prompt: 'Sub-task');

      expect(parent.children, contains(child));

      _happyPathEvents().forEach(controller.add);
      await controller.close();
    });

    test('spawnChild without roomId defaults to parent roomId', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      // Parent on _roomB so a regression that hardcodes _roomA in
      // spawnChild's defaulting wouldn't pass.
      final parent = await runtime.spawn(roomId: _roomB, prompt: 'Hello');
      final child = await parent.spawnChild(prompt: 'Sub-task');

      expect(child.threadKey.roomId, equals(_roomB));
      expect(parent.children, contains(child));

      _happyPathEvents().forEach(controller.add);
      await controller.close();
    });

    test('parent cancel cascades to children', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      final child = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Sub-task',
        parent: parent,
      );

      // Move both to running state
      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      parent.cancel();

      final childResult = await child.result;
      final parentResult = await parent.result;

      expect(childResult, isA<AgentFailure>());
      expect(
        (childResult as AgentFailure).reason,
        equals(FailureReason.cancelled),
      );
      expect(parentResult, isA<AgentFailure>());
      expect(
        (parentResult as AgentFailure).reason,
        equals(FailureReason.cancelled),
      );

      await controller.close();
    });

    test('parent dispose cascades to children', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      final child = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Sub-task',
        parent: parent,
      );

      parent.dispose();

      final childResult = await child.result;
      expect(childResult, isA<AgentFailure>());
      expect(
        (childResult as AgentFailure).reason,
        equals(FailureReason.internalError),
      );

      expect(parent.children, isEmpty);

      await controller.close();
    });

    test('child completion does not affect parent', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();

      // Child gets happy path (completes immediately), parent stays running
      final parentController = StreamController<BaseEvent>.broadcast();
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount == 1
            ? parentController.stream
            : Stream.fromIterable(_happyPathEvents());
      });

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      final child = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Sub-task',
        parent: parent,
      );

      // Wait for child to complete
      final childResult = await child.result;
      expect(childResult, isA<AgentSuccess>());

      // Parent still running
      expect(parent.state, isNot(equals(AgentSessionState.completed)));
      expect(parent.state, isNot(equals(AgentSessionState.failed)));

      // Clean up parent
      _happyPathEvents().forEach(parentController.add);
      await parentController.close();
      await parent.result;
    });

    test('cancelAll cancels parent and child via flat index', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      await runtime.spawn(roomId: _roomA, prompt: 'Sub-task', parent: parent);

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      await runtime.cancelAll();

      // All sessions should be cancelled
      for (final session in runtime.activeSessions) {
        final result = await session.result;
        expect(result, isA<AgentFailure>());
      }

      await controller.close();
    });

    test('cross-room child spawn', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomA, prompt: 'Hello');
      final child = await runtime.spawn(
        roomId: _roomB,
        prompt: 'Cross-room task',
        parent: parent,
      );

      expect(parent.children, contains(child));
      expect(child.threadKey.roomId, equals(_roomB));
      expect(parent.threadKey.roomId, equals(_roomA));

      _happyPathEvents().forEach(controller.add);
      await controller.close();
    });

    test('deeply nested children cascade cancel', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final grandparent = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Level 0',
      );
      final parent = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Level 1',
        parent: grandparent,
      );
      final child = await runtime.spawn(
        roomId: _roomA,
        prompt: 'Level 2',
        parent: parent,
      );

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      grandparent.cancel();

      final childResult = await child.result;
      final parentResult = await parent.result;
      final grandparentResult = await grandparent.result;

      expect(childResult, isA<AgentFailure>());
      expect(parentResult, isA<AgentFailure>());
      expect(grandparentResult, isA<AgentFailure>());

      await controller.close();
    });
  });
}
