import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/tools/tool_registry_resolver.dart';
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
// Test doubles
// ---------------------------------------------------------------------------

class _TestExtension implements SessionExtension {
  _TestExtension({this.toolList = const []});

  final List<ClientTool> toolList;
  int attachCount = 0;
  int disposeCount = 0;

  @override
  Future<void> onAttach(AgentSession session) async => attachCount++;

  @override
  List<ClientTool> get tools => toolList;

  @override
  void onDispose() => disposeCount++;
}

class _ThrowingExtension implements SessionExtension {
  @override
  Future<void> onAttach(AgentSession session) async =>
      throw StateError('onAttach boom');

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() {}
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _roomId = 'room-1';
const _threadId = 'thread-1';
const _runId = 'run-abc';

ThreadInfo _threadInfo() =>
    ThreadInfo(id: _threadId, roomId: _roomId, createdAt: DateTime(2026));

ThreadInfo _threadInfoWithRun() => ThreadInfo(
      id: _threadId,
      roomId: _roomId,
      initialRunId: _runId,
      createdAt: DateTime(2026),
    );

RunInfo _runInfo() =>
    RunInfo(id: _runId, threadId: _threadId, createdAt: DateTime(2026));

List<BaseEvent> _happyPathEvents() => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _toolCallEvents() => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      const ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather'),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"city":"NYC"}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _resumeTextEvents() => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-2'),
      const TextMessageContentEvent(messageId: 'msg-2', delta: 'Sunny'),
      const TextMessageEndEvent(messageId: 'msg-2'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

ToolRegistry _weatherRegistry() {
  return const ToolRegistry().register(
    ClientTool(
      definition: const Tool(name: 'weather', description: 'Weather tool'),
      executor: (_, __) async => '72°F, sunny',
    ),
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
  late AgentRuntime runtime;

  ServerConnection mockConnection({String serverId = 'default'}) =>
      ServerConnection(
        serverId: serverId,
        api: api,
        agUiStreamClient: agUiStreamClient,
      );

  AgentRuntime createRuntime({
    PlatformConstraints? platform,
    ToolRegistryResolver? resolver,
  }) {
    return AgentRuntime(
      connection: mockConnection(),
      llmProvider: AgUiLlmProvider(
        api: api,
        agUiStreamClient: agUiStreamClient,
      ),
      toolRegistryResolver: resolver ?? (_) async => const ToolRegistry(),
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

  void stubCreateThread({ThreadInfo? info}) {
    when(
      () => api.createThread(any()),
    ).thenAnswer((_) async => (info ?? _threadInfo(), <String, dynamic>{}));
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

  group('spawn', () {
    test('creates thread, starts session, returns AgentSuccess', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      expect(session.threadKey.serverId, equals('default'));
      expect(session.threadKey.roomId, equals(_roomId));
      expect(session.threadKey.threadId, equals(_threadId));

      verify(() => api.createThread(_roomId)).called(1);
    });

    test('reuses threadId when provided, skips createThread', () async {
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Hello',
        threadId: 'existing-thread',
      );
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      expect(session.threadKey.threadId, equals('existing-thread'));
      verifyNever(() => api.createThread(any()));
    });

    test('uses initialRunId from createThread', () async {
      stubCreateThread(info: _threadInfoWithRun());
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      await session.result;
      // Should NOT call createRun because initialRunId was provided
      verifyNever(() => api.createRun(any(), any()));
    });

    test('session appears in activeSessions', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      expect(runtime.activeSessions, contains(session));

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      await controller.close();
      // After stream closes, session might complete via networkLost
      await session.result;
    });
  });

  group('getSession', () {
    test('finds session by ThreadKey', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      final found = runtime.getSession(session.threadKey);
      expect(found, equals(session));

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await controller.close();
      await session.result;
    });

    test('returns null for unknown key', () {
      const unknown = (serverId: 'x', roomId: 'x', threadId: 'x');
      expect(runtime.getSession(unknown), isNull);
    });
  });

  group('sessionChanges', () {
    test('emits on spawn and completion', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final emissions = <List<AgentSession>>[];
      runtime.sessionChanges.listen(emissions.add);

      await runtime.spawn(roomId: _roomId, prompt: 'Hello', autoDispose: true);

      // Wait for session to complete and be cleaned up
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // At least one emission from spawn
      expect(emissions, isNotEmpty);
    });

    test('sessions signal stays in sync with stream', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      // Signal and getter agree after spawn
      expect(runtime.sessions.value, contains(session));
      expect(runtime.sessions.value, equals(runtime.activeSessions));

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await controller.close();
      await session.result;
    });
  });

  group('waitAll', () {
    test('collects all results', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final s1 = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final s2 = await runtime.spawn(roomId: _roomId, prompt: 'B');

      final results = await runtime.waitAll([s1, s2]);

      expect(results, hasLength(2));
      expect(results.every((r) => r is AgentSuccess), isTrue);
    });
  });

  group('waitAny', () {
    test('returns first completed result', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final s1 = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final s2 = await runtime.spawn(roomId: _roomId, prompt: 'B');

      final result = await runtime.waitAny([s1, s2]);

      expect(result, isA<AgentSuccess>());
    });
  });

  group('WASM concurrent sessions', () {
    test('allows concurrent sessions on web platform', () async {
      runtime = createRuntime(platform: const WebPlatformConstraints());

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      // Non-broadcast: events buffer until the orchestrator subscribes.
      final controllerA = StreamController<BaseEvent>();
      final controllerB = StreamController<BaseEvent>();
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount == 1 ? controllerA.stream : controllerB.stream;
      });

      final sessionA = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final sessionB = await runtime.spawn(roomId: _roomId, prompt: 'B');

      expect(runtime.activeSessions, hasLength(2));

      _happyPathEvents().forEach(controllerA.add);
      _happyPathEvents().forEach(controllerB.add);
      await controllerA.close();
      await controllerB.close();

      final resultA = await sessionA.result;
      final resultB = await sessionB.result;
      expect(resultA, isA<AgentSuccess>());
      expect(resultB, isA<AgentSuccess>());
    });

    test('queues at maxConcurrentSessions limit', () async {
      runtime = createRuntime(
        platform: const WebPlatformConstraints(maxConcurrentSessions: 1),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controllerA = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controllerA.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'A');
      expect(runtime.pendingSpawnCount, 0);

      final spawnFuture = runtime.spawn(roomId: _roomId, prompt: 'B');
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, 1);

      // Complete first → drain queue.
      _happyPathEvents().forEach(controllerA.add);
      await controllerA.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final controllerB = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controllerB.stream);

      final session = await spawnFuture;
      expect(session, isNotNull);
      expect(runtime.pendingSpawnCount, 0);

      _happyPathEvents().forEach(controllerB.add);
      await controllerB.close();
    });
  });

  group('concurrency queuing', () {
    test('queues spawn at max concurrent limit', () async {
      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'A');
      expect(runtime.pendingSpawnCount, 0);

      // Second spawn should queue, not throw.
      final spawnFuture = runtime.spawn(roomId: _roomId, prompt: 'B');
      // Let microtask run so _waitForSlot enqueues.
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, 1);

      // Complete first session to free the slot.
      _happyPathEvents().forEach(controller.add);
      await controller.close();

      // Give time for session completion + queue drain.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Queued spawn needs a fresh stream.
      final controller2 = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller2.stream);

      final session = await spawnFuture;
      expect(session, isNotNull);
      expect(runtime.pendingSpawnCount, 0);

      // Clean up
      _happyPathEvents().forEach(controller2.add);
      await controller2.close();
    });

    test('dispose unblocks queued spawns with StateError', () async {
      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'A');

      // Queue a second spawn and immediately attach an error handler
      // so the test zone doesn't see an unhandled rejection.
      Object? caught;
      final spawnFuture = runtime.spawn(roomId: _roomId, prompt: 'B');
      unawaited(
        spawnFuture.then<void>((_) {}).catchError((Object e) {
          caught = e;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, 1);

      // Complete first session and dispose runtime.
      _happyPathEvents().forEach(controller.add);
      await controller.close();
      await runtime.dispose();

      // Let microtasks settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(caught, isA<StateError>());
    });
  });

  group('spawn depth guard', () {
    test('root session has depth 0', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Root');

      expect(session.depth, 0);
    });

    test('blocks spawn when depth exceeds maxSpawnDepth', () async {
      runtime = createRuntime();
      // maxSpawnDepth defaults to 10, create a root session at depth 0
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      // Spawn a root at depth 0
      final root = await runtime.spawn(roomId: _roomId, prompt: 'Root');
      expect(root.depth, 0);

      // Now create a runtime with maxSpawnDepth=1 to test the guard
      await runtime.dispose();
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        maxSpawnDepth: 1,
      );

      final controller2 = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller2.stream);

      final parent = await runtime.spawn(roomId: _roomId, prompt: 'Parent');
      expect(parent.depth, 0);

      expect(
        () => runtime.spawn(roomId: _roomId, prompt: 'Child', parent: parent),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Spawn depth limit'),
          ),
        ),
      );

      // Clean up
      _happyPathEvents().forEach(controller2.add);
      await controller2.close();
    });

    test('allows spawn when depth is disabled (maxSpawnDepth=0)', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        maxSpawnDepth: 0,
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomId, prompt: 'Parent');

      // Should not throw even with a parent at depth 0
      final child = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Child',
        parent: parent,
      );
      expect(child.depth, 1);

      // Clean up
      _happyPathEvents().forEach(controller.add);
      await controller.close();
    });
  });

  group('root timeout', () {
    test('cancels root session after rootTimeout expires', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        rootTimeout: const Duration(milliseconds: 100),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      // Stream that never completes — session stays running until timeout
      final controller = StreamController<BaseEvent>.broadcast()
        ..add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      stubRunAgent(stream: controller.stream);

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Slow');

      final result = await session.result;

      expect(result, isA<AgentFailure>());
      expect((result as AgentFailure).reason, FailureReason.cancelled);

      await controller.close();
    });

    test('timer is cancelled on normal completion', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        rootTimeout: const Duration(seconds: 10),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Fast');

      final result = await session.result;

      // Completes normally before rootTimeout
      expect(result, isA<AgentSuccess>());
    });

    test('no timer for child sessions', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        rootTimeout: const Duration(milliseconds: 50),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast()
        ..add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      stubRunAgent(stream: controller.stream);

      final parent = await runtime.spawn(roomId: _roomId, prompt: 'Parent');
      await runtime.spawn(roomId: _roomId, prompt: 'Child', parent: parent);

      // Wait past the rootTimeout — only parent should be cancelled,
      // but since child is a child of parent, it gets cascaded
      final result = await parent.result;
      expect(result, isA<AgentFailure>());

      await controller.close();
    });
  });

  group('ephemeral', () {
    test('deletes thread on completion', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Hello',
        ephemeral: true,
        autoDispose: true,
      );

      await session.result;
      // Give time for completion handler
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => api.deleteThread(_roomId, _threadId)).called(1);
    });

    test('does not delete thread for non-ephemeral', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Hello',
        threadId: 'existing',
      );

      await session.result;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(() => api.deleteThread(any(), any()));
    });
  });

  group('cancelAll', () {
    test('cancels all active sessions', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      final s1 = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final s2 = await runtime.spawn(roomId: _roomId, prompt: 'B');

      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      await runtime.cancelAll();

      final r1 = await s1.result;
      final r2 = await s2.result;

      expect(r1, isA<AgentFailure>());
      expect(r2, isA<AgentFailure>());

      await controller.close();
    });
  });

  group('dispose', () {
    test('subsequent spawn throws', () async {
      await runtime.dispose();

      expect(
        () => runtime.spawn(roomId: _roomId, prompt: 'Hello'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('cleans up ephemeral threads', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'A', ephemeral: true);
      controller.add(const RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      await runtime.dispose();

      verify(() => api.deleteThread(_roomId, _threadId)).called(1);

      await controller.close();
    });
  });

  group('error propagation', () {
    test('createThread failure propagates', () async {
      when(
        () => api.createThread(any()),
      ).thenThrow(const AuthException(message: 'Token expired'));

      expect(
        () => runtime.spawn(roomId: _roomId, prompt: 'Hello'),
        throwsA(isA<AuthException>()),
      );
    });

    test('resolver failure propagates', () async {
      runtime = createRuntime(
        resolver: (_) async => throw StateError('No tools'),
      );
      stubCreateThread();

      expect(
        () => runtime.spawn(roomId: _roomId, prompt: 'Hello'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('spawn cleanup on start failure', () {
    test('cleans up session when extension onAttach throws', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        extensionFactory: () async => [_ThrowingExtension()],
      );

      stubCreateThread();
      stubDeleteThread();

      await expectLater(
        () => runtime.spawn(roomId: _roomId, prompt: 'Hello', ephemeral: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('onAttach boom'),
          ),
        ),
      );

      expect(runtime.activeSessions, isEmpty);
      expect(runtime.sessions.value, isEmpty);
      verify(() => api.deleteThread(_roomId, _threadId)).called(1);
    });

    test('concurrency count resets after start failure', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
        logger: logger,
        extensionFactory: () async => [_ThrowingExtension()],
      );

      stubCreateThread();
      stubDeleteThread();

      // First spawn fails
      await expectLater(
        () => runtime.spawn(roomId: _roomId, prompt: 'A'),
        throwsA(isA<StateError>()),
      );

      // Second spawn should NOT hit concurrency limit — slot was freed.
      // It will still fail from the throwing extension, but the error
      // must be the extension error, not a concurrency guard error.
      await expectLater(
        () => runtime.spawn(roomId: _roomId, prompt: 'B'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('onAttach boom'),
          ),
        ),
      );
    });
  });

  group('end-to-end', () {
    test('spawn → tool yield → auto-execute → resume → AgentSuccess', () async {
      final registry = _weatherRegistry();
      runtime = createRuntime(resolver: (_) async => registry);

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();

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

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Weather?');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      final success = result as AgentSuccess;
      expect(success.output, equals('Sunny'));
      expect(callCount, equals(2));
    });
  });

  group('extensionFactory', () {
    test('factory tools appear in session tool registry', () async {
      final tool = ClientTool(
        definition: const Tool(
          name: 'execute_python',
          description: 'Run Python',
        ),
        executor: (_, __) async => 'python result',
      );

      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        extensionFactory: () async => [
          _TestExtension(toolList: [tool]),
        ],
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();

      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        // First call: tool yield; second call: resume with text
        return callCount == 1
            ? Stream.fromIterable([
                const RunStartedEvent(threadId: _threadId, runId: _runId),
                const ToolCallStartEvent(
                  toolCallId: 'tc-py',
                  toolCallName: 'execute_python',
                ),
                const ToolCallArgsEvent(
                  toolCallId: 'tc-py',
                  delta: '{"code":"print(1)"}',
                ),
                const ToolCallEndEvent(toolCallId: 'tc-py'),
                const RunFinishedEvent(threadId: _threadId, runId: _runId),
              ])
            : Stream.fromIterable(_resumeTextEvents());
      });

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Run code');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      expect(callCount, equals(2));
    });

    test('null factory works (backward compat)', () async {
      runtime = createRuntime();

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
    });

    test('factory error propagates from spawn', () async {
      runtime = AgentRuntime(
        connection: mockConnection(),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        extensionFactory: () async => throw StateError('WASM init failed'),
      );

      stubCreateThread();

      expect(
        () => runtime.spawn(roomId: _roomId, prompt: 'Hello'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('WASM init failed'),
          ),
        ),
      );
    });

    test('constructor threads factory through', () async {
      var factoryCalled = false;
      runtime = AgentRuntime(
        connection: mockConnection(serverId: 'prod'),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
        extensionFactory: () async {
          factoryCalled = true;
          return [_TestExtension()];
        },
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      expect(factoryCalled, isTrue);
    });
  });

  group('serverId', () {
    test('defaults to "default"', () {
      expect(runtime.serverId, equals('default'));
    });

    test('custom serverId appears in ThreadKey', () async {
      runtime = AgentRuntime(
        connection: mockConnection(serverId: 'staging.soliplex.io'),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      expect(session.threadKey.serverId, equals('staging.soliplex.io'));
      await session.result;
    });
  });

  group('ServerConnection constructor', () {
    test('produces runtime with correct serverId', () {
      runtime = AgentRuntime(
        connection: mockConnection(serverId: 'prod'),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
      );

      expect(runtime.serverId, equals('prod'));
    });

    test('spawn creates session with matching ThreadKey.serverId', () async {
      runtime = AgentRuntime(
        connection: mockConnection(serverId: 'prod'),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');

      expect(session.threadKey.serverId, equals('prod'));
      await session.result;
    });
  });

  group('automatic thread history', () {
    test('second spawn on same thread includes prior conversation', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      // Turn 1.
      final s1 = await runtime.spawn(roomId: _roomId, prompt: 'Hello');
      await s1.result;

      // Stub a second run on the same thread.
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));
      stubCreateRun();

      // Turn 2 — same thread, runtime should auto-inject history.
      final s2 = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Follow up',
        threadId: s1.threadKey.threadId,
      );
      await s2.result;

      // Capture all runAgent calls.
      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured;

      // Second call should have prior messages + new user message.
      final input2 = captured[1] as SimpleRunAgentInput;
      final messages = input2.messages!;
      // Prior: user + assistant from turn 1 + new user = 3
      expect(messages.length, greaterThanOrEqualTo(3));
      expect(
        messages.last,
        isA<UserMessage>().having(
          (m) => m.content,
          'content',
          'Follow up',
        ),
      );
    });

    test('first spawn on new thread sends only user message', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'Hello');
      await session.result;

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured;

      final input = captured.first as SimpleRunAgentInput;
      final messages = input.messages!;
      expect(messages, hasLength(1));
      expect(messages.first, isA<UserMessage>());
    });

    test('ephemeral sessions do not accumulate history', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final s1 = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Ephemeral',
        ephemeral: true,
      );
      await s1.result;

      // Stub second run.
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));
      stubCreateRun();

      final s2 = await runtime.spawn(
        roomId: _roomId,
        prompt: 'Another',
        threadId: s1.threadKey.threadId,
      );
      await s2.result;

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured;

      // Second call should have only the new message (no history from
      // ephemeral session).
      final input2 = captured[1] as SimpleRunAgentInput;
      expect(input2.messages, hasLength(1));
    });
  });

  group('Phase 1 integration', () {
    test('registry → connection → runtime → session', () async {
      final prodConn = ServerConnection(
        serverId: 'prod',
        api: api,
        agUiStreamClient: agUiStreamClient,
      );
      final stagingConn = ServerConnection(
        serverId: 'staging',
        api: MockSoliplexApi(),
        agUiStreamClient: MockAgUiStreamClient(),
      );

      final reg = ServerRegistry()
        ..add(prodConn)
        ..add(stagingConn);

      runtime = AgentRuntime(
        connection: reg.require('prod'),
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: const NativePlatformConstraints(),
        logger: logger,
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime.spawn(roomId: _roomId, prompt: 'hi');

      expect(session.threadKey.serverId, equals('prod'));

      final result = await session.result;
      expect(result, isA<AgentSuccess>());
    });
  });
}
