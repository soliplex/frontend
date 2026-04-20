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

ToolRegistry _registryWith({
  String toolName = 'weather',
  ToolExecutor? executor,
}) {
  return const ToolRegistry().register(
    ClientTool(
      definition: Tool(name: toolName, description: 'A test tool'),
      executor: executor ?? (_, __) async => '72°F, sunny',
    ),
  );
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _TestScriptEnvironment implements ScriptEnvironment {
  int disposeCount = 0;

  @override
  List<ClientTool> get tools => const [];

  @override
  void dispose() => disposeCount++;
}

class _TestExtension implements SessionExtension {
  int attachCount = 0;
  int disposeCount = 0;
  AgentSession? attachedSession;

  @override
  Future<void> onAttach(AgentSession session) async {
    attachCount++;
    attachedSession = session;
  }

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() => disposeCount++;
}

class _TestExtensionWithTool implements SessionExtension {
  _TestExtensionWithTool(this._tool);

  final ClientTool _tool;
  int attachCount = 0;
  int disposeCount = 0;

  @override
  Future<void> onAttach(AgentSession session) async => attachCount++;

  @override
  List<ClientTool> get tools => [_tool];

  @override
  void onDispose() => disposeCount++;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a session wired to real RunOrchestrator with given deps.
AgentSession createSession({
  required MockSoliplexApi api,
  required MockAgUiStreamClient agUiStreamClient,
  required MockLogger logger,
  AgentRuntime? runtime,
  ToolRegistry? toolRegistry,
  List<SessionExtension> extensions = const [],
  bool ephemeral = false,
}) {
  final registry = toolRegistry ?? const ToolRegistry();
  final orchestrator = RunOrchestrator(
    llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: agUiStreamClient),
    toolRegistry: registry,
    logger: logger,
  );
  return AgentSession(
    threadKey: _key,
    ephemeral: ephemeral,
    depth: 0,
    runtime: runtime ?? MockAgentRuntime(),
    orchestrator: orchestrator,
    toolRegistry: registry,
    extensions: extensions,
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

  group('happy path', () {
    test('completes with AgentSuccess', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      final success = result as AgentSuccess;
      expect(success.output, equals('Hello world'));
      expect(success.runId, equals(_runId));
      expect(success.threadKey, equals(_key));
    });

    test('state transitions spawning → running → completed', () async {
      stubCreateRun();

      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.state, equals(AgentSessionState.spawning));
      expect(session.sessionState.value, equals(AgentSessionState.spawning));
      expect(session.runState.value, isA<IdleState>());

      await session.start(userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.state, equals(AgentSessionState.running));
      expect(session.sessionState.value, equals(AgentSessionState.running));
      expect(session.runState.value, isA<RunningState>());

      _happyPathEvents().skip(1).forEach(controller.add);
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      expect(session.state, equals(AgentSessionState.completed));
      expect(session.sessionState.value, equals(AgentSessionState.completed));
      expect(session.runState.value, isA<CompletedState>());
    });
  });

  group('auto-execute', () {
    test('yield → execute → resume → AgentSuccess', () async {
      final registry = _registryWith();
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

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        toolRegistry: registry,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Weather?');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      final success = result as AgentSuccess;
      expect(success.output, equals('Sunny'));
    });

    test('double yield: 2 rounds of tool execution', () async {
      final registry = _registryWith();
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
        if (callCount <= 2) {
          return Stream.fromIterable(_toolCallEvents());
        }
        return Stream.fromIterable(_resumeTextEvents());
      });

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        toolRegistry: registry,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Weather?');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      expect(callCount, equals(3));
    });

    test('tool error → ToolCallStatus.failed, session continues', () async {
      final registry = _registryWith(
        executor: (_, __) async => throw Exception('API down'),
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

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        toolRegistry: registry,
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Weather?');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
    });
  });

  group('cancel', () {
    test('cancel during running → AgentFailure(cancelled)', () async {
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
      final result = await session.result;

      expect(result, isA<AgentFailure>());
      final failure = result as AgentFailure;
      expect(failure.reason, equals(FailureReason.cancelled));
      expect(session.state, equals(AgentSessionState.cancelled));

      await controller.close();
    });

    test('cancel on already-terminal session is no-op', () async {
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

      expect(session.state, equals(AgentSessionState.completed));
      session.cancel(); // should not throw
      expect(session.state, equals(AgentSessionState.completed));
    });
  });

  group('failure', () {
    test('stream error → AgentFailure', () async {
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
      final result = await session.result;

      expect(result, isA<AgentFailure>());
      final failure = result as AgentFailure;
      expect(failure.reason, equals(FailureReason.serverError));
      expect(session.state, equals(AgentSessionState.failed));
    });
  });

  group('timeout', () {
    test('awaitResult with short timeout → AgentTimedOut', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(() async {
        session.dispose();
        await controller.close();
      });

      await session.start(userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await session.awaitResult(
        timeout: const Duration(milliseconds: 10),
      );

      expect(result, isA<AgentTimedOut>());
    });
  });

  group('dispose', () {
    test('dispose before completion completes with internalError', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );

      await session.start(userMessage: 'Hi');
      session.dispose();

      final result = await session.result;
      expect(result, isA<AgentFailure>());
      final failure = result as AgentFailure;
      expect(failure.reason, equals(FailureReason.internalError));

      // Controller may never be subscribed to (runToCompletion is
      // unawaited and dispose fires before the SSE stream subscribes),
      // so close without awaiting to avoid hanging.
      unawaited(controller.close());
    });
  });

  group('id', () {
    test('id contains threadId', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.id, contains(_key.threadId));
    });
  });

  group('ephemeral', () {
    test('ephemeral flag is preserved', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        ephemeral: true,
      );
      addTearDown(session.dispose);

      expect(session.ephemeral, isTrue);
    });
  });

  group('stateChanges', () {
    test('emits RunningState during active run', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      final states = <RunState>[];
      session.stateChanges.listen(states.add);

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(states, isNotEmpty);
      expect(states.first, isA<RunningState>());
      expect(states.last, isA<CompletedState>());
    });

    test('supports multiple listeners (broadcast)', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      final states1 = <RunState>[];
      final states2 = <RunState>[];
      session.stateChanges.listen(states1.add);
      session.stateChanges.listen(states2.add);

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(states1, isNotEmpty);
      expect(states2, isNotEmpty);
      expect(states1.length, equals(states2.length));
    });

    test('emits TextStreaming with content', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      final streamingTexts = <String>[];
      session.stateChanges.listen((state) {
        if (state case RunningState(:final streaming)) {
          if (streaming case TextStreaming(:final text)) {
            streamingTexts.add(text);
          }
        }
      });

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(streamingTexts, contains('Hello world'));
    });
  });

  group('extensions', () {
    test('onAttach called before run starts', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final ext = _TestExtension();
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        extensions: [ext],
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Hi');
      await session.result;

      expect(ext.attachCount, equals(1));
      expect(ext.attachedSession, same(session));
    });

    test('extension tools merged into registry', () async {
      final tool = ClientTool(
        definition: const Tool(name: 'ext_tool', description: 'Extension tool'),
        executor: (_, __) async => 'ext result',
      );
      final ext = _TestExtensionWithTool(tool);

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
            ? Stream.fromIterable([
              const RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const ToolCallStartEvent(
                toolCallId: 'tc-ext',
                toolCallName: 'ext_tool',
              ),
              const ToolCallArgsEvent(toolCallId: 'tc-ext', delta: '{}'),
              const ToolCallEndEvent(toolCallId: 'tc-ext'),
              const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
            ])
            : Stream.fromIterable(_resumeTextEvents());
      });

      // Build session with extension tool merged into registry.
      final baseRegistry = const ToolRegistry().register(tool);
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        toolRegistry: baseRegistry,
        extensions: [ext],
      );
      addTearDown(session.dispose);

      await session.start(userMessage: 'Run ext tool');
      final result = await session.result;

      expect(result, isA<AgentSuccess>());
      expect(callCount, equals(2));
    });

    test('onDispose called on session dispose', () {
      final ext = _TestExtension();
      createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        extensions: [ext],
      ).dispose();

      expect(ext.disposeCount, equals(1));
    });

    test('dispose order: children before extensions', () {
      final parentExt = _TestExtension();
      final childExt = _TestExtension();
      createSession(
          api: api,
          agUiStreamClient: agUiStreamClient,
          logger: logger,
          extensions: [parentExt],
        )
        ..addChild(
          createSession(
            api: api,
            agUiStreamClient: agUiStreamClient,
            logger: logger,
            extensions: [childExt],
          ),
        )
        ..dispose();

      expect(childExt.disposeCount, equals(1));
      expect(parentExt.disposeCount, equals(1));
    });

    test('getExtension returns matching extension', () {
      final ext = _TestExtension();
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        extensions: [ext],
      );
      addTearDown(session.dispose);

      expect(session.getExtension<_TestExtension>(), same(ext));
    });

    test('getExtension returns null for unregistered type', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.getExtension<_TestExtension>(), isNull);
    });

    test('empty extensions list works', () {
      createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      ).dispose();
    });

    test('double dispose does not double-dispose extensions', () {
      final ext = _TestExtension();
      createSession(
          api: api,
          agUiStreamClient: agUiStreamClient,
          logger: logger,
          extensions: [ext],
        )
        ..dispose()
        ..dispose();

      expect(ext.disposeCount, equals(1));
    });

    test('ScriptEnvironmentExtension adapter lifecycle', () {
      final env = _TestScriptEnvironment();
      final ext = ScriptEnvironmentExtension(env);

      expect(ext.tools, isEmpty);
      ext.onDispose();
      expect(env.disposeCount, equals(1));
    });
  });

  group('execution events', () {
    test('emitEvent updates lastExecutionEvent signal', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      expect(session.lastExecutionEvent.value, isNull);

      const event = TextDelta(delta: 'hello');
      session.emitEvent(event);

      expect(session.lastExecutionEvent.value, equals(event));
    });

    test(
      'executeSingle emits ClientToolExecuting then ClientToolCompleted',
      () async {
        final registry = _registryWith();
        stubCreateRun();

        final events = <ExecutionEvent>[];
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

        final session = createSession(
          api: api,
          agUiStreamClient: agUiStreamClient,
          logger: logger,
          toolRegistry: registry,
        );
        addTearDown(session.dispose);

        // Collect execution events
        session.lastExecutionEvent.subscribe((_) {
          final val = session.lastExecutionEvent.value;
          if (val != null) events.add(val);
        });

        await session.start(userMessage: 'Weather?');
        await session.result;

        final executing = events.whereType<ClientToolExecuting>().toList();
        final completed = events.whereType<ClientToolCompleted>().toList();
        expect(executing, hasLength(1));
        expect(executing.first.toolName, equals('weather'));
        expect(completed, hasLength(1));
        expect(completed.first.status, equals(ToolCallStatus.completed));
      },
    );

    test('executeSingle failure emits ClientToolCompleted(failed)', () async {
      final registry = _registryWith(
        executor: (_, __) async => throw Exception('oops'),
      );
      stubCreateRun();

      final events = <ExecutionEvent>[];
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

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        toolRegistry: registry,
      );
      addTearDown(session.dispose);

      session.lastExecutionEvent.subscribe((_) {
        final val = session.lastExecutionEvent.value;
        if (val != null) events.add(val);
      });

      await session.start(userMessage: 'Weather?');
      await session.result;

      final completed = events.whereType<ClientToolCompleted>().toList();
      expect(completed, hasLength(1));
      expect(completed.first.status, equals(ToolCallStatus.failed));
    });

    test('tool timeout emits failed with timeout message (R2)', () async {
      final registry = _registryWith(
        executor:
            (_, __) async =>
                throw TimeoutException(
                  'timed out',
                  const Duration(seconds: 60),
                ),
      );
      stubCreateRun();

      final events = <ExecutionEvent>[];
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

      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
        toolRegistry: registry,
      );
      addTearDown(session.dispose);

      session.lastExecutionEvent.subscribe((_) {
        final val = session.lastExecutionEvent.value;
        if (val != null) events.add(val);
      });

      await session.start(userMessage: 'Weather?');
      await session.result;

      final completed = events.whereType<ClientToolCompleted>().toList();
      expect(completed, hasLength(1));
      expect(completed.first.status, equals(ToolCallStatus.failed));
      expect(completed.first.result, contains('timed out after'));
    });

    test('cancelToken delegates to orchestrator', () {
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      // cancelToken returns a fresh token when no run is active.
      final token = session.cancelToken;
      expect(token, isA<CancelToken>());
    });

    test('ActivitySnapshotEvent bridges to ActivitySnapshot', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const ActivitySnapshotEvent(
            messageId: 'msg-1',
            activityType: 'skill_tool_call',
            content: {'tool_name': 'search'},
          ),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hi'),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      final events = <ExecutionEvent>[];
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      session.lastExecutionEvent.subscribe((_) {
        final val = session.lastExecutionEvent.value;
        if (val != null) events.add(val);
      });

      await session.start(userMessage: 'Hi');
      await session.result;

      final snapshots = events.whereType<ActivitySnapshot>().toList();
      expect(snapshots, hasLength(1));
      expect(snapshots.first.activityType, equals('skill_tool_call'));
      expect(snapshots.first.content, equals({'tool_name': 'search'}));
    });

    test('StepStartedEvent bridges to StepProgress', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const StepStartedEvent(stepName: 'planning'),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hi'),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      final events = <ExecutionEvent>[];
      final session = createSession(
        api: api,
        agUiStreamClient: agUiStreamClient,
        logger: logger,
      );
      addTearDown(session.dispose);

      session.lastExecutionEvent.subscribe((_) {
        final val = session.lastExecutionEvent.value;
        if (val != null) events.add(val);
      });

      await session.start(userMessage: 'Hi');
      await session.result;

      final steps = events.whereType<StepProgress>().toList();
      expect(steps, hasLength(1));
      expect(steps.first.stepName, equals('planning'));
    });
  });
}
