/// Concurrency experiments for agent runtime across WASM and FFI platforms.
///
/// These tests document **current behavior** and serve as hypotheses for
/// validating the concurrent session design. Each hypothesis (H1–H14) is
/// tagged with the platform and expected outcome.
///
/// After the Phase 2 fix (adding `maxConcurrentSessions` and removing
/// `_guardWasmReentrancy`), some tests will flip expectations — those are
/// marked with `// POST-FIX:` comments.
library;

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

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class _MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

// ---------------------------------------------------------------------------
// Bridge simulation — models the Monty interpreter lock
// ---------------------------------------------------------------------------

/// Simulates a non-reentrant interpreter (Monty bridge).
///
/// WASM: all sessions share one instance (single interpreter).
/// FFI/Native: each session gets its own instance (Isolate-backed).
class _FakeBridge {
  bool _held = false;
  final _waiters = <Completer<void>>[];

  /// Number of times [acquire] blocked (bridge was already held).
  int contentionCount = 0;

  /// Execution log: `'start'` / `'end'` entries for ordering assertions.
  final log = <String>[];

  Future<void> acquire() async {
    if (!_held) {
      _held = true;
      return;
    }
    contentionCount++;
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _held = false;
    }
  }
}

/// [ScriptEnvironment] backed by a [_FakeBridge].
///
/// Provides an `execute_python` tool that acquires the bridge lock,
/// simulates work, and releases. This models what a real Monty bridge
/// environment would do.
class _FakeBridgeScriptEnvironment implements ScriptEnvironment {
  _FakeBridgeScriptEnvironment(this._bridge, {this.workDuration});

  final _FakeBridge _bridge;
  final Duration? workDuration;

  @override
  List<ClientTool> get tools => [
        ClientTool(
          definition: const Tool(
            name: 'execute_python',
            description: 'Simulated Python execution via bridge',
          ),
          executor: (_, __) async {
            await _bridge.acquire();
            try {
              _bridge.log.add('start');
              if (workDuration != null) {
                await Future<void>.delayed(workDuration!);
              }
              _bridge.log.add('end');
              return 'ok';
            } finally {
              _bridge.release();
            }
          },
        ),
      ];

  @override
  void dispose() {}
}

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

List<BaseEvent> _toolCallEvents({String toolName = 'execute_python'}) => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: toolName),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _resumeTextEvents() => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-2'),
      const TextMessageContentEvent(messageId: 'msg-2', delta: 'Done'),
      const TextMessageEndEvent(messageId: 'msg-2'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late _MockSoliplexApi api;
  late _MockAgUiStreamClient agUiStreamClient;
  late _MockLogger logger;
  late AgentRuntime runtime;

  ServerConnection mockConnection() => ServerConnection(
        serverId: 'default',
        api: api,
        agUiStreamClient: agUiStreamClient,
      );

  AgentRuntime createRuntime({
    PlatformConstraints? platform,
    ToolRegistryResolver? resolver,
    SessionExtensionFactory? extensionFactory,
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
      extensionFactory: extensionFactory,
    );
  }

  setUp(() {
    api = _MockSoliplexApi();
    agUiStreamClient = _MockAgUiStreamClient();
    logger = _MockLogger();
    runtime = createRuntime();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  void stubCreateThread() {
    when(() => api.createThread(any()))
        .thenAnswer((_) async => (_threadInfo(), <String, dynamic>{}));
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

  // =========================================================================
  // Group A: Session/Spawn Layer (no bridge)
  // =========================================================================

  group('H1: WASM allows concurrent HTTP-only sessions', () {
    test('two sessions run concurrently on WebPlatformConstraints', () async {
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
  });

  group('H2: Native allows concurrent HTTP-only sessions', () {
    test('two sessions run concurrently under bridge limit', () async {
      runtime = createRuntime(
        platform: const NativePlatformConstraints(),
      );

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
  });

  group('H3: Native queues at bridge limit', () {
    test('second spawn queues when maxConcurrentBridges=1', () async {
      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
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

      final sessionB = await spawnFuture;
      expect(sessionB, isNotNull);
      expect(runtime.pendingSpawnCount, 0);

      _happyPathEvents().forEach(controllerB.add);
      await controllerB.close();
    });
  });

  group('H4: WASM allows sequential sessions (slot freed)', () {
    test('second spawn succeeds after first completes', () async {
      runtime = createRuntime(platform: const WebPlatformConstraints());

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final sessionA = await runtime.spawn(roomId: _roomId, prompt: 'A');
      await sessionA.result;

      // Fresh stubs for second spawn.
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final sessionB = await runtime.spawn(roomId: _roomId, prompt: 'B');
      final resultB = await sessionB.result;
      expect(resultB, isA<AgentSuccess>());
    });
  });

  group('H5: High-pressure N=10 spawns on Native(2)', () {
    test('all sessions eventually complete via queue drain', () async {
      const n = 10;
      const limit = 2;
      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: limit),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();

      final controllers =
          List.generate(n, (_) => StreamController<BaseEvent>.broadcast());
      var callIdx = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => controllers[callIdx++].stream);

      // Await first `limit` to ensure they're tracked before queuing.
      final sessions = <AgentSession>[];
      for (var i = 0; i < limit; i++) {
        sessions.add(
          await runtime.spawn(roomId: _roomId, prompt: 'Task $i'),
        );
      }

      // Fire remaining — they queue.
      final queuedFutures = <Future<AgentSession>>[];
      for (var i = limit; i < n; i++) {
        queuedFutures.add(runtime.spawn(roomId: _roomId, prompt: 'Task $i'));
      }
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, n - limit);

      // Complete sessions as their controllers become active.
      for (var i = 0; i < n; i++) {
        while (callIdx <= i) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        _happyPathEvents().forEach(controllers[i].add);
        await controllers[i].close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final queuedSessions = await Future.wait(queuedFutures);
      sessions.addAll(queuedSessions);

      final results = await Future.wait(
        sessions.map(
          (s) => s.awaitResult(timeout: const Duration(seconds: 5)),
        ),
      );

      expect(results, everyElement(isA<AgentSuccess>()));
      expect(runtime.pendingSpawnCount, 0);
    });
  });

  // =========================================================================
  // Group B: Parent-Child & Lifecycle
  // =========================================================================

  group('H6: Parent-child delegation deadlocks under single slot', () {
    test('parent times out when child cannot acquire slot', () async {
      final delegateTool = ClientTool(
        definition: const Tool(
          name: 'delegate',
          description: 'Delegates to a child agent',
        ),
        executor: (_, context) => context.delegateTask(
          prompt: 'subtask',
          timeout: const Duration(milliseconds: 200),
        ),
      );

      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
        resolver: (_) async => const ToolRegistry().register(delegateTool),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(
        stream: Stream.fromIterable(_toolCallEvents(toolName: 'delegate')),
      );

      final parent = await runtime.spawn(roomId: _roomId, prompt: 'Delegate');

      // Deadlock: parent holds slot → tool calls delegateTask → spawnChild
      // → _waitForSlot queues → parent waits for child → child waits for
      // slot → neither progresses.
      final result = await parent.awaitResult(
        timeout: const Duration(milliseconds: 500),
      );

      expect(result, isA<AgentTimedOut>());
    });
  });

  group('H7: Dispose unblocks queued spawns', () {
    test('queued spawn on Native receives StateError on dispose', () async {
      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'A');

      Object? caught;
      final spawnFuture = runtime.spawn(roomId: _roomId, prompt: 'B');
      unawaited(
        spawnFuture.then<void>((_) {}).catchError((Object e) {
          caught = e;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, 1);

      _happyPathEvents().forEach(controller.add);
      await controller.close();
      await runtime.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(caught, isA<StateError>());
    });

    test('WASM: queued spawn on Web receives StateError on dispose', () async {
      runtime = createRuntime(
        platform: const WebPlatformConstraints(maxConcurrentSessions: 1),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>.broadcast();
      stubRunAgent(stream: controller.stream);

      await runtime.spawn(roomId: _roomId, prompt: 'A');

      Object? caught;
      final spawnFuture = runtime.spawn(roomId: _roomId, prompt: 'B');
      unawaited(
        spawnFuture.then<void>((_) {}).catchError((Object e) {
          caught = e;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, 1);

      _happyPathEvents().forEach(controller.add);
      await controller.close();
      await runtime.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(caught, isA<StateError>());
    });
  });

  group('H8: Mixed fast/slow sessions drain correctly', () {
    test('queued fast sessions complete after slow sessions free slots',
        () async {
      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 2),
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();

      final slowA = StreamController<BaseEvent>.broadcast();
      final slowB = StreamController<BaseEvent>.broadcast();
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        switch (callCount) {
          case 1:
            return slowA.stream;
          case 2:
            return slowB.stream;
          default:
            return Stream.fromIterable(_happyPathEvents());
        }
      });

      // Fill slots with slow sessions.
      await runtime.spawn(roomId: _roomId, prompt: 'Slow A');
      await runtime.spawn(roomId: _roomId, prompt: 'Slow B');

      // Queue fast sessions.
      final futureC = runtime.spawn(roomId: _roomId, prompt: 'Fast C');
      final futureD = runtime.spawn(roomId: _roomId, prompt: 'Fast D');
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingSpawnCount, 2);

      // Complete slow → fast drain.
      _happyPathEvents().forEach(slowA.add);
      await slowA.close();
      _happyPathEvents().forEach(slowB.add);
      await slowB.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final sessionC = await futureC;
      final sessionD = await futureD;

      final resultC = await sessionC.result;
      final resultD = await sessionD.result;
      expect(resultC, isA<AgentSuccess>());
      expect(resultD, isA<AgentSuccess>());
      expect(runtime.pendingSpawnCount, 0);
    });
  });

  // =========================================================================
  // Group C: ScriptEnvironment / Bridge Contention
  // =========================================================================

  group('H9: WASM — shared bridge contention serializes tools', () {
    test('two sessions with shared bridge serialize tool execution', () async {
      final sharedBridge = _FakeBridge();

      runtime = createRuntime(
        platform: const WebPlatformConstraints(),
        extensionFactory: () async => [
          ScriptEnvironmentExtension(
            _FakeBridgeScriptEnvironment(
              sharedBridge,
              workDuration: const Duration(milliseconds: 100),
            ),
          ),
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
        // Calls 1–2: tool events; calls 3–4: resume events.
        return callCount <= 2
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      final sessionA = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final sessionB = await runtime.spawn(roomId: _roomId, prompt: 'B');

      final resultA = await sessionA.result;
      final resultB = await sessionB.result;

      expect(resultA, isA<AgentSuccess>());
      expect(resultB, isA<AgentSuccess>());

      // Shared bridge — second tool waited for first.
      expect(sharedBridge.contentionCount, greaterThan(0));

      // Tools serialized: [start, end, start, end].
      expect(
        sharedBridge.log,
        equals(['start', 'end', 'start', 'end']),
      );
    });
  });

  group('H10: Native — independent bridges, tools overlap', () {
    test('two sessions with per-session bridges execute concurrently',
        () async {
      // Each session gets its own bridge (simulates Isolate-backed FFI).
      final bridges = <_FakeBridge>[];

      runtime = createRuntime(
        platform: const NativePlatformConstraints(),
        extensionFactory: () async {
          final bridge = _FakeBridge();
          bridges.add(bridge);
          return [
            ScriptEnvironmentExtension(
              _FakeBridgeScriptEnvironment(
                bridge,
                workDuration: const Duration(milliseconds: 200),
              ),
            ),
          ];
        },
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
        // Calls 1–2: tool events; calls 3–4: resume events.
        return callCount <= 2
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      final sw = Stopwatch()..start();
      final sessionA = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final sessionB = await runtime.spawn(roomId: _roomId, prompt: 'B');

      final resultA = await sessionA.result;
      final resultB = await sessionB.result;
      sw.stop();

      expect(resultA, isA<AgentSuccess>());
      expect(resultB, isA<AgentSuccess>());
      expect(bridges, hasLength(2));

      // Independent bridges — no contention.
      for (final bridge in bridges) {
        expect(bridge.contentionCount, 0);
      }

      // Wall-clock: concurrent ≈ 200ms, serialized ≈ 400ms.
      // Use generous threshold to avoid flaky tests.
      expect(sw.elapsedMilliseconds, lessThan(350));
    });
  });

  group('H11: WASM allows mixed bridge/bridgeless sessions', () {
    test('both sessions succeed regardless of tool usage', () async {
      final sharedBridge = _FakeBridge();

      runtime = createRuntime(
        platform: const WebPlatformConstraints(),
        extensionFactory: () async => [
          ScriptEnvironmentExtension(
            _FakeBridgeScriptEnvironment(sharedBridge),
          ),
        ],
      );

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

      await runtime.spawn(roomId: _roomId, prompt: 'With bridge');
      final sessionB =
          await runtime.spawn(roomId: _roomId, prompt: 'HTTP only');

      _happyPathEvents().forEach(controllerA.add);
      _happyPathEvents().forEach(controllerB.add);
      await controllerA.close();
      await controllerB.close();

      final resultB = await sessionB.result;
      expect(resultB, isA<AgentSuccess>());
    });
  });

  group('H12: Native(1) with shared bridge — sessions serialize', () {
    test('bridge never contended because sessions queue at spawn level',
        () async {
      final sharedBridge = _FakeBridge();

      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: 1),
        extensionFactory: () async => [
          ScriptEnvironmentExtension(
            _FakeBridgeScriptEnvironment(
              sharedBridge,
              workDuration: const Duration(milliseconds: 50),
            ),
          ),
        ],
      );

      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();

      // Each session: odd call → tool events, even call → resume.
      var callCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount.isOdd
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      // Await first spawn to ensure tracking before queuing.
      final sessionA = await runtime.spawn(roomId: _roomId, prompt: 'A');
      final futureB = runtime.spawn(roomId: _roomId, prompt: 'B');

      final sessionB = await futureB;

      final resultA =
          await sessionA.awaitResult(timeout: const Duration(seconds: 5));
      final resultB =
          await sessionB.awaitResult(timeout: const Duration(seconds: 5));

      expect(resultA, isA<AgentSuccess>());
      expect(resultB, isA<AgentSuccess>());

      // Sessions serialized by queue → bridge never contended.
      expect(sharedBridge.contentionCount, 0);

      // Tools executed sequentially.
      expect(
        sharedBridge.log,
        equals(['start', 'end', 'start', 'end']),
      );
    });
  });

  group('H13: WASM — shared bridge wall-clock serialization', () {
    test('N=3 sessions serialize through shared bridge', () async {
      const n = 3;
      const toolDuration = Duration(milliseconds: 100);
      final sharedBridge = _FakeBridge();

      runtime = createRuntime(
        platform: const WebPlatformConstraints(),
        extensionFactory: () async => [
          ScriptEnvironmentExtension(
            _FakeBridgeScriptEnvironment(
              sharedBridge,
              workDuration: toolDuration,
            ),
          ),
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
        return callCount <= n
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      final sw = Stopwatch()..start();
      final sessions = <AgentSession>[];
      for (var i = 0; i < n; i++) {
        sessions.add(
          await runtime.spawn(roomId: _roomId, prompt: 'Task $i'),
        );
      }

      final results = await Future.wait(
        sessions.map(
          (s) => s.awaitResult(timeout: const Duration(seconds: 10)),
        ),
      );
      sw.stop();

      expect(results, everyElement(isA<AgentSuccess>()));

      // Shared bridge serialized: wall-clock ≈ 300ms (3×100ms).
      expect(sw.elapsedMilliseconds, greaterThan(200));

      // Bridge was contended.
      expect(sharedBridge.contentionCount, greaterThan(0));

      // All tools serialized.
      expect(
        sharedBridge.log,
        equals(['start', 'end', 'start', 'end', 'start', 'end']),
      );
    });
  });

  group('H14: Native — independent bridges, wall-clock overlap', () {
    test('N=5 with per-session bridges complete in ~tool_duration', () async {
      const n = 5;
      const toolDuration = Duration(milliseconds: 150);

      runtime = createRuntime(
        platform: const NativePlatformConstraints(maxConcurrentBridges: n),
        extensionFactory: () async {
          final bridge = _FakeBridge();
          return [
            ScriptEnvironmentExtension(
              _FakeBridgeScriptEnvironment(bridge, workDuration: toolDuration),
            ),
          ];
        },
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
        return callCount <= n
            ? Stream.fromIterable(_toolCallEvents())
            : Stream.fromIterable(_resumeTextEvents());
      });

      final sw = Stopwatch()..start();

      // Await each spawn sequentially so they're tracked for queue checks.
      final sessions = <AgentSession>[];
      for (var i = 0; i < n; i++) {
        sessions.add(
          await runtime.spawn(roomId: _roomId, prompt: 'Task $i'),
        );
      }

      final results = await Future.wait(
        sessions.map(
          (s) => s.awaitResult(timeout: const Duration(seconds: 10)),
        ),
      );
      sw.stop();

      expect(results, everyElement(isA<AgentSuccess>()));

      // Concurrent: wall-clock ≈ 150ms. Serialized would be ≈ 750ms.
      // Generous threshold to avoid flaky tests.
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });
}
