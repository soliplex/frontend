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
    orchestrator = RunOrchestrator(
      llmProvider: AgUiLlmProvider(
        api: api,
        agUiStreamClient: agUiStreamClient,
      ),
      toolRegistry: const ToolRegistry(),
      logger: logger,
    );
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
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((_) => stream);
  }

  group('happy path', () {
    test('streams to CompletedState', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');

      // Give stream time to complete
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      expect(completed.threadKey, equals(_key));
      expect(completed.runId, equals(_runId));
    });

    test('stateChanges emits transitions', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final states = <RunState>[];
      orchestrator.stateChanges.listen(states.add);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      // Expect: RunningState (initial), then updates per event, CompletedState
      expect(states.first, isA<RunningState>());
      expect(states.last, isA<CompletedState>());
    });

    test('currentState matches last emission', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      RunState? lastEmitted;
      orchestrator.stateChanges.listen((s) => lastEmitted = s);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, equals(lastEmitted));
    });

    test('existingRunId skips createRun', () async {
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await orchestrator.startRun(
        key: _key,
        userMessage: 'Hi',
        existingRunId: _runId,
      );
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => api.createRun(any(), any()));
      expect(orchestrator.currentState, isA<CompletedState>());
    });
  });

  group('error', () {
    test('RunErrorEvent transitions to FailedState(serverError)', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const RunErrorEvent(message: 'backend error'),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      expect(failed.reason, equals(FailureReason.serverError));
      expect(failed.error, equals('backend error'));
    });

    test(
      'HTTP 401 TransportError transitions to FailedState(authExpired)',
      () async {
        stubCreateRun();
        stubRunAgent(
          stream: Stream.error(
            const TransportError('Unauthorized', statusCode: 401),
          ),
        );

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<FailedState>());
        final failed = orchestrator.currentState as FailedState;
        expect(failed.reason, equals(FailureReason.authExpired));
      },
    );

    test(
      'HTTP 429 TransportError transitions to FailedState(rateLimited)',
      () async {
        stubCreateRun();
        stubRunAgent(
          stream: Stream.error(
            const TransportError('Too many requests', statusCode: 429),
          ),
        );

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<FailedState>());
        final failed = orchestrator.currentState as FailedState;
        expect(failed.reason, equals(FailureReason.rateLimited));
      },
    );

    test(
      'stream ends without terminal event transitions to networkLost',
      () async {
        stubCreateRun();
        stubRunAgent(
          stream: Stream.fromIterable([
            const RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const TextMessageStartEvent(messageId: 'msg-1'),
          ]),
        );

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<FailedState>());
        final failed = orchestrator.currentState as FailedState;
        expect(failed.reason, equals(FailureReason.networkLost));
      },
    );

    test('createRun throws transitions to FailedState', () async {
      when(
        () => api.createRun(any(), any()),
      ).thenThrow(const AuthException(message: 'Token expired'));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      expect(failed.reason, equals(FailureReason.authExpired));
    });

    test(
      'stream error after RunFinishedEvent does not change CompletedState',
      () async {
        stubCreateRun();
        final controller = StreamController<BaseEvent>();
        stubRunAgent(stream: controller.stream);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');

        controller
          ..add(const RunStartedEvent(threadId: 'thread-1', runId: _runId))
          ..add(const TextMessageStartEvent(messageId: 'msg-1'))
          ..add(const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hi'))
          ..add(const TextMessageEndEvent(messageId: 'msg-1'))
          ..add(const RunFinishedEvent(threadId: 'thread-1', runId: _runId));
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<CompletedState>());

        // Simulate server TCP close — should NOT cause FailedState.
        controller.addError(
          const NetworkException(message: 'Connection closed'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<CompletedState>());

        await controller.close();
      },
    );

    test(
      'FailedState.error unwraps SoliplexException to its message',
      () async {
        // The friendly-error rewrite in
        // `ThreadViewState._friendlyMessage` matches
        // `error.startsWith(streamResumeFailedPrefix)`. Without
        // unwrapping, `SoliplexException.toString()` adds a
        // `RuntimeType: ` prefix that defeats the match — the user
        // ends up seeing the raw nested exception text instead of
        // "Connection lost. The response may be incomplete — you
        // can send your message again."
        stubCreateRun();
        final controller = StreamController<BaseEvent>();
        addTearDown(controller.close);
        stubRunAgent(stream: controller.stream);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        await Future<void>.delayed(Duration.zero);

        controller.addError(
          const NetworkException(
            message: 'Stream resume failed: transient',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<FailedState>());
        final failed = orchestrator.currentState as FailedState;
        expect(
          failed.error,
          equals('Stream resume failed: transient'),
          reason: 'must surface NetworkException.message — not the '
              'type-prefixed toString — so the friendly-message '
              "contract's startsWith check matches",
        );
      },
    );
  });

  group('cancel', () {
    test('cancelRun transitions to CancelledState', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<RunningState>());

      orchestrator.cancelRun();

      expect(orchestrator.currentState, isA<CancelledState>());
      final cancelled = orchestrator.currentState as CancelledState;
      expect(cancelled.threadKey, equals(_key));
      expect(cancelled.conversation, isNotNull);

      await controller.close();
    });

    test('cancelRun while idle is a no-op', () {
      expect(orchestrator.currentState, isA<IdleState>());
      orchestrator.cancelRun();
      expect(orchestrator.currentState, isA<IdleState>());
    });
  });

  group('guard', () {
    test('startRun while running throws StateError', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
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
            contains('already active'),
          ),
        ),
      );

      await controller.close();
    });
  });

  group('reset', () {
    test('reset transitions to IdleState', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());

      orchestrator.reset();

      expect(orchestrator.currentState, isA<IdleState>());
    });
  });

  group('cachedHistory', () {
    test('prepends cached messages before new user message', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: [
          TextMessage.create(
            id: 'prior-user',
            user: ChatUser.user,
            text: 'First question',
          ),
          TextMessage.create(
            id: 'prior-assistant',
            user: ChatUser.assistant,
            text: 'First answer',
          ),
        ],
      );

      await orchestrator.startRun(
        key: _key,
        userMessage: 'Follow-up',
        cachedHistory: history,
      );
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final messages = completed.conversation.messages;

      // Prior user + prior assistant + new user + streamed assistant = 4
      expect(messages, hasLength(4));
      expect(
        messages[0],
        isA<TextMessage>().having((m) => m.text, 'text', 'First question'),
      );
      expect(
        messages[1],
        isA<TextMessage>().having((m) => m.text, 'text', 'First answer'),
      );
      expect(
        messages[2],
        isA<TextMessage>().having((m) => m.text, 'text', 'Follow-up'),
      );
      expect(
        messages[3],
        isA<TextMessage>().having((m) => m.text, 'text', 'Hello'),
      );
    });

    test('null cachedHistory produces single user message', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final messages = completed.conversation.messages;

      // New user + streamed assistant = 2
      expect(messages, hasLength(2));
      expect(
        messages.first,
        isA<TextMessage>().having((m) => m.text, 'text', 'Hi'),
      );
    });

    test('aguiState from cachedHistory flows to Conversation', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: [
          TextMessage.create(
            id: 'prior-user',
            user: ChatUser.user,
            text: 'Search',
          ),
        ],
        aguiState: const {'key': 'value'},
      );

      await orchestrator.startRun(
        key: _key,
        userMessage: 'More',
        cachedHistory: history,
      );
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      expect(completed.conversation.aguiState, containsPair('key', 'value'));
    });

    test('cachedHistory works with runToCompletion', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: [
          TextMessage.create(
            id: 'prior-user',
            user: ChatUser.user,
            text: 'Turn 1',
          ),
          TextMessage.create(
            id: 'prior-assistant',
            user: ChatUser.assistant,
            text: 'Response 1',
          ),
        ],
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Turn 2',
        toolExecutor: (_) async => [],
        cachedHistory: history,
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final messages = completed.conversation.messages;

      expect(messages, hasLength(4));
      expect(
        messages[0],
        isA<TextMessage>().having((m) => m.text, 'text', 'Turn 1'),
      );
      expect(
        messages[1],
        isA<TextMessage>().having((m) => m.text, 'text', 'Response 1'),
      );
      expect(
        messages[2],
        isA<TextMessage>().having((m) => m.text, 'text', 'Turn 2'),
      );
    });
  });

  group('stateOverlay', () {
    test('runToCompletion merges stateOverlay into aguiState', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        stateOverlay: {
          'rag': <String, dynamic>{'document_filter': "id = 'abc-123'"},
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final rag = completed.conversation.aguiState['rag'] as Map;
      expect(rag['document_filter'], "id = 'abc-123'");
    });

    test('runToCompletion merges stateOverlay with cachedHistory aguiState',
        () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'citations': <int>[1, 2, 3],
          },
          'other': 'data',
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: {
          'rag': <String, dynamic>{'document_filter': "id = 'abc-123'"},
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final rag = completed.conversation.aguiState['rag'] as Map;
      expect(rag['document_filter'], "id = 'abc-123'");
      expect(rag['citations'], [1, 2, 3]);
      expect(completed.conversation.aguiState['other'], 'data');
    });

    test('deep-merges nested maps recursively', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'config': <String, dynamic>{
              'maxChunks': 5,
              'strategy': 'semantic',
            },
          },
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: {
          'rag': <String, dynamic>{
            'config': <String, dynamic>{
              'maxChunks': 10,
            },
          },
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final config =
          (completed.conversation.aguiState['rag'] as Map)['config'] as Map;
      expect(config['maxChunks'], 10);
      expect(config['strategy'], 'semantic');
    });

    test('overlay replaces non-map with map value', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': 'old-string-value',
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: {
          'rag': <String, dynamic>{'document_filter': "id = 'x-1'"},
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      expect(
        completed.conversation.aguiState['rag'],
        {'document_filter': "id = 'x-1'"},
      );
    });

    test('overlay scalar replaces existing map', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'config': <String, dynamic>{'maxChunks': 5},
          },
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: {
          'rag': <String, dynamic>{'config': null},
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final rag = completed.conversation.aguiState['rag'] as Map;
      expect(rag['config'], isNull);
    });

    test('overlay list replaces existing list', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'citations': <int>[1, 2, 3],
          },
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: {
          'rag': <String, dynamic>{
            'citations': <int>[99],
          },
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final rag = completed.conversation.aguiState['rag'] as Map;
      expect(rag['citations'], [99]);
    });

    test('merges untyped map literals correctly', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'existing': 'value',
          },
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: {
          'rag': {'new_key': 'new_value'},
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final rag = completed.conversation.aguiState['rag'] as Map;
      expect(rag['existing'], 'value');
      expect(rag['new_key'], 'new_value');
    });

    test('empty overlay produces no change', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'citations': <int>[1],
          },
        },
      );

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'test',
        toolExecutor: (_) async => [],
        cachedHistory: history,
        stateOverlay: const {},
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      expect(
        completed.conversation.aguiState['rag'],
        {
          'citations': [1],
        },
      );
    });
  });

  group('tool yielding', () {
    test('pending client tools → ToolYieldingState', () async {
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

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<ToolYieldingState>());
      final yielding = orchestrator.currentState as ToolYieldingState;
      expect(yielding.pendingToolCalls, hasLength(1));
      expect(yielding.pendingToolCalls.first.name, equals('weather'));
      expect(yielding.toolDepth, equals(0));
    });

    test('no pending client tools → CompletedState', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_toolCallEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
    });

    test('server-side tools (not in registry) → CompletedState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(toolName: 'other_tool'),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(
          _toolCallEvents(toolName: 'server_only_tool'),
        ),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
    });
  });

  group('submitToolOutputs', () {
    late int callCount;

    void stubRunAgentSequential({
      required Stream<BaseEvent> first,
      required Stream<BaseEvent> second,
    }) {
      callCount = 0;
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
        return callCount == 1 ? first : second;
      });
    }

    test('resume → Running → Completed', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      stubRunAgentSequential(
        first: Stream.fromIterable(_toolCallEvents()),
        second: Stream.fromIterable(_resumeTextEvents()),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());

      await orchestrator.submitToolOutputs(_executedTools());
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
    });

    test('throws when not in ToolYieldingState', () {
      expect(
        () => orchestrator.submitToolOutputs(_executedTools()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Not in ToolYieldingState'),
          ),
        ),
      );
    });

    test('throws when disposed', () async {
      orchestrator.dispose();
      expect(
        () => orchestrator.submitToolOutputs(_executedTools()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });
  });

  group('tool chain', () {
    test('2 rounds of yield/submit/resume', () async {
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
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        if (callCount <= 2) {
          return Stream.fromIterable(_toolCallEvents());
        }
        return Stream.fromIterable(_resumeTextEvents());
      });

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());
      final yield1 = orchestrator.currentState as ToolYieldingState;
      expect(yield1.toolDepth, equals(0));

      await orchestrator.submitToolOutputs(_executedTools());
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());
      final yield2 = orchestrator.currentState as ToolYieldingState;
      expect(yield2.toolDepth, equals(1));

      await orchestrator.submitToolOutputs(_executedTools());
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<CompletedState>());
    });
  });

  group('depth limit', () {
    test('exceed max → FailedState(toolExecutionFailed)', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) => Stream.fromIterable(_toolCallEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 10; i++) {
        expect(orchestrator.currentState, isA<ToolYieldingState>());
        await orchestrator.submitToolOutputs(_executedTools());
        await Future<void>.delayed(Duration.zero);
      }

      expect(orchestrator.currentState, isA<ToolYieldingState>());
      await orchestrator.submitToolOutputs(_executedTools());

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      expect(failed.reason, equals(FailureReason.toolExecutionFailed));
      expect(failed.error, contains('depth limit'));
    });

    test('NetworkException during resume → FailedState(networkLost)', () async {
      // The post-tool-yield resume goes through `_failResume`, which must
      // route via `classifyError` rather than hardcoding
      // `toolExecutionFailed`. A transport drop on the resume should
      // surface as `networkLost` so the UI can render reconnect copy
      // instead of a tool-failure message.
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      var runAgentCallCount = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        runAgentCallCount++;
        if (runAgentCallCount == 1) {
          return Stream.fromIterable(_toolCallEvents());
        }
        return Stream<BaseEvent>.error(
          const NetworkException(message: 'transport drop on resume'),
        );
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) async => _executedTools(),
      );

      expect(result, isA<FailedState>());
      final failed = result as FailedState;
      expect(
        failed.reason,
        equals(FailureReason.networkLost),
        reason: 'transport failure during resume must classify as '
            'networkLost, not toolExecutionFailed',
      );
    });
  });

  group('cancel during yield', () {
    test('cancelRun → CancelledState', () async {
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

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());

      orchestrator.cancelRun();

      expect(orchestrator.currentState, isA<CancelledState>());
      final cancelled = orchestrator.currentState as CancelledState;
      expect(cancelled.conversation, isNotNull);
    });

    test('startRun blocked during ToolYieldingState', () async {
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

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());

      expect(
        () => orchestrator.startRun(key: _key, userMessage: 'Again'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already active'),
          ),
        ),
      );
    });

    test('cancelRun during RunningState cancels the token passed to runAgent',
        () async {
      // Pins the orchestrator → SSE-client cancel handshake: the
      // orchestrator must (a) pass a non-null token to `runAgent`
      // and (b) cancel it on `cancelRun`, so cancellation propagates
      // to the in-flight SSE stream.
      CancelToken? capturedToken;
      final controller = StreamController<BaseEvent>();
      addTearDown(controller.close);
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((invocation) {
        capturedToken = invocation.namedArguments[#cancelToken] as CancelToken?;
        return controller.stream;
      });
      stubCreateRun();

      unawaited(
        orchestrator.runToCompletion(
          key: _key,
          userMessage: 'Hi',
          toolExecutor: (_) async => [],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<RunningState>());
      expect(
        capturedToken,
        isNotNull,
        reason: 'orchestrator must pass a non-null cancel token',
      );
      expect(capturedToken!.isCancelled, isFalse);

      orchestrator.cancelRun();

      expect(
        capturedToken!.isCancelled,
        isTrue,
        reason: "cancelRun must propagate to the SSE client's token",
      );
      expect(orchestrator.currentState, isA<CancelledState>());
    });

    test('cancelRun during _resumeStream createRun await yields CancelledState',
        () async {
      // Pins three coupled contracts that fire when the user presses
      // Stop during a tool-yield resume:
      //   - cancelRun's ToolYieldingState arm cancels the live token
      //     so the in-flight createRun await aborts.
      //   - _resumeStream does not call _subscribeToStream after the
      //     await if state has transitioned away from ToolYieldingState
      //     (otherwise CancelledState would be overwritten with
      //     RunningState).
      //   - _driveToolLoop's catch routes a cancel-byproduct exception
      //     to CancelledState, not FailedState.
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();
      // First runAgent call: tool call events drive us to ToolYieldingState.
      // Second runAgent call: resume; an empty stream is enough. The
      // post-await `_currentState is! ToolYieldingState` guard in
      // `_resumeStream` prevents `_subscribeToStream` from running —
      // if it ran, RunningState would overwrite CancelledState, then
      // `_onStreamDone` would flip to FailedState via the "Stream
      // ended without terminal event" path.
      var runAgentCallCount = 0;
      var resumeStreamSubscribeCount = 0;
      final resumeStreamController = StreamController<BaseEvent>(
        onListen: () => resumeStreamSubscribeCount++,
      );
      addTearDown(resumeStreamController.close);
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        runAgentCallCount++;
        if (runAgentCallCount == 1) {
          return Stream.fromIterable(_toolCallEvents());
        }
        return resumeStreamController.stream;
      });

      // Block the tool executor so the test can re-stub createRun before
      // _resumeStream fires.
      final toolExecutorTrigger = Completer<void>();
      final runFuture = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) async {
          await toolExecutorTrigger.future;
          return _executedTools();
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());

      final resumeCreateRun = Completer<RunInfo>();
      when(
        () => api.createRun(any(), any()),
      ).thenAnswer((_) => resumeCreateRun.future);

      toolExecutorTrigger.complete();
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());

      orchestrator.cancelRun();
      expect(
        orchestrator.currentState,
        isA<CancelledState>(),
        reason: 'cancelRun must transition to CancelledState immediately',
      );

      resumeCreateRun.complete(_runInfo());
      final result = await runFuture;

      expect(
        result,
        isA<CancelledState>(),
        reason: 'state must remain CancelledState; without the post-await '
            'guard, `_subscribeToStream` would overwrite it with '
            'RunningState and the empty resume stream would then flip '
            'to FailedState via `_onStreamDone`',
      );
      expect(runAgentCallCount, equals(2));
      expect(
        resumeStreamSubscribeCount,
        equals(1),
        reason: 'orchestrator must drain the abandoned LlmRunHandle.events '
            'stream so the underlying SSE socket releases — without the '
            'subscribe-then-cancel, the HTTP transport would hold it open',
      );
    });
  });

  group('cancel during async gap', () {
    test('dispose during startRun await aborts', () async {
      final createRunCompleter = Completer<RunInfo>();
      when(
        () => api.createRun(any(), any()),
      ).thenAnswer((_) => createRunCompleter.future);
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      // Start run — will suspend on createRun.
      unawaited(orchestrator.startRun(key: _key, userMessage: 'Hi'));
      await Future<void>.delayed(Duration.zero);

      // Dispose while awaiting createRun.
      orchestrator.dispose();

      // Complete the createRun after disposal.
      createRunCompleter.complete(_runInfo());
      await Future<void>.delayed(Duration.zero);

      // With AgentLlmProvider, runAgent is called inside startRun()
      // (bundled with createRun), but the orchestrator's disposal check
      // prevents subscribing to the returned stream. The key safety
      // guarantee: no state transitions after disposal.
      expect(orchestrator.currentState, isA<IdleState>());
    });

    test('cancelRun during submitToolOutputs await aborts', () async {
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

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<ToolYieldingState>());

      // Make the resume createRun hang.
      final resumeCompleter = Completer<RunInfo>();
      when(
        () => api.createRun(any(), any()),
      ).thenAnswer((_) => resumeCompleter.future);

      unawaited(orchestrator.submitToolOutputs(_executedTools()));
      await Future<void>.delayed(Duration.zero);

      // Cancel while awaiting resume createRun.
      orchestrator.cancelRun();

      // Complete the createRun after cancellation.
      resumeCompleter.complete(_runInfo());
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CancelledState>());
    });

    test(
      'CancelledException through stream → CancelledState (not FailedState)',
      () async {
        // Pins that `_onStreamError` routes both cancellation shapes
        // to `CancelledState`: `CancelledException` (from our
        // `CancelToken`) and Dart-core `CancellationError` (from
        // `CancelableOperation`). The `CancellationError` arm is
        // exercised by `run_to_completion_test.dart`'s
        // `'completer resolves for CancelledState'`.
        stubCreateRun();
        final controller = StreamController<BaseEvent>();
        addTearDown(controller.close);
        stubRunAgent(stream: controller.stream);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        await Future<void>.delayed(Duration.zero);
        expect(orchestrator.currentState, isA<RunningState>());

        controller.addError(const CancelledException(reason: 'user'));
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<CancelledState>());
      },
    );

    test(
      'CancelledException from initial startRun → CancelledState',
      () async {
        // Pins that `_handleStartError` routes a cancel during the
        // initial `startRun` await (the IdleState window) to
        // `CancelledState`, not `FailedState`.
        when(() => api.createRun(any(), any()))
            .thenThrow(const CancelledException(reason: 'user'));

        await orchestrator.startRun(key: _key, userMessage: 'Hi');

        expect(orchestrator.currentState, isA<CancelledState>());
      },
    );
  });

  group('graceful SSE close', () {
    test(
      'dispose after RunFinishedEvent does not cancel subscription',
      () async {
        stubCreateRun();

        var subscriptionCancelled = false;
        final controller = StreamController<BaseEvent>(
          onCancel: () => subscriptionCancelled = true,
        );
        stubRunAgent(stream: controller.stream);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');

        // Emit a complete happy-path sequence.
        _happyPathEvents().forEach(controller.add);
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<CompletedState>());
        // Reset flag — _handleRunFinished detaches without cancel,
        // but the stream controller may fire onCancel when the sub
        // reference is dropped. We care about the dispose() path.
        subscriptionCancelled = false;

        // Dispose after terminal event — should NOT force-cancel.
        orchestrator.dispose();

        expect(
          subscriptionCancelled,
          isFalse,
          reason: 'dispose() after RunFinishedEvent must not cancel '
              'the subscription to avoid poisoning the server '
              'connection pool',
        );

        await controller.close();
      },
    );

    test('dispose during active run still cancels subscription', () async {
      stubCreateRun();

      var subscriptionCancelled = false;
      final controller = StreamController<BaseEvent>(
        onCancel: () => subscriptionCancelled = true,
      );
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<RunningState>());

      // Dispose while stream is active — SHOULD cancel.
      orchestrator.dispose();

      expect(
        subscriptionCancelled,
        isTrue,
        reason: 'dispose() during active run must cancel subscription',
      );

      await controller.close();
    });

    test('RunErrorEvent still force-cancels subscription', () async {
      stubCreateRun();

      var subscriptionCancelled = false;
      final controller = StreamController<BaseEvent>(
        onCancel: () => subscriptionCancelled = true,
      );
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller
        ..add(const RunStartedEvent(threadId: 'thread-1', runId: _runId))
        ..add(const RunErrorEvent(message: 'backend error'));
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      expect(
        subscriptionCancelled,
        isTrue,
        reason: 'RunErrorEvent should force-cancel to clean up',
      );

      await controller.close();
    });
  });

  group('AG-UI state round-trip', () {
    test('_buildInput sends aguiState from cachedHistory to backend', () async {
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

      final history = ThreadHistory(
        messages: [
          TextMessage.create(
            id: 'prior-user',
            user: ChatUser.user,
            text: 'Search',
          ),
        ],
        aguiState: const {'filter': 'docs', 'citations': <String>[]},
      );

      await orchestrator.startRun(
        key: _key,
        userMessage: 'More',
        cachedHistory: history,
      );
      await Future<void>.delayed(Duration.zero);

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).captured;

      final input = captured.first as SimpleRunAgentInput;
      final state = input.state as Map<String, dynamic>;
      expect(state, containsPair('filter', 'docs'));
      expect(state, containsPair('citations', <String>[]));
    });

    test(
      'state accumulated via StateSnapshotEvent survives to resume run',
      () async {
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
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) {
          callCount++;
          if (callCount == 1) {
            // First run: emit state snapshot + tool call.
            return Stream.fromIterable([
              const RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const StateSnapshotEvent(
                snapshot: {'rag_context': 'doc-42', 'turn': 1},
              ),
              const ToolCallStartEvent(
                toolCallId: 'tc-1',
                toolCallName: 'weather',
              ),
              const ToolCallArgsEvent(
                toolCallId: 'tc-1',
                delta: '{"city":"NYC"}',
              ),
              const ToolCallEndEvent(toolCallId: 'tc-1'),
              const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
            ]);
          }
          // Second run: just complete.
          return Stream.fromIterable(_resumeTextEvents());
        });

        await orchestrator.startRun(key: _key, userMessage: 'Weather?');
        await Future<void>.delayed(Duration.zero);
        expect(orchestrator.currentState, isA<ToolYieldingState>());

        await orchestrator.submitToolOutputs(_executedTools());
        await Future<void>.delayed(Duration.zero);
        expect(orchestrator.currentState, isA<CompletedState>());

        // Verify the second runAgent call received the state from the snapshot.
        final captured = verify(
          () => agUiStreamClient.runAgent(
            any(),
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).captured;

        // captured has 2 entries: first call and second call.
        final resumeInput = captured[1] as SimpleRunAgentInput;
        final state = resumeInput.state as Map<String, dynamic>;
        expect(state, containsPair('rag_context', 'doc-42'));
        expect(state, containsPair('turn', 1));
      },
    );

    test('state modified across multiple runs via runToCompletion', () async {
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
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          // Run 1: set initial state + yield tool.
          return Stream.fromIterable([
            const RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const StateSnapshotEvent(snapshot: {'turn': 1, 'docs': <String>[]}),
            const ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'weather',
            ),
            const ToolCallArgsEvent(
              toolCallId: 'tc-1',
              delta: '{"city":"NYC"}',
            ),
            const ToolCallEndEvent(toolCallId: 'tc-1'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]);
        }
        if (callCount == 2) {
          // Run 2: update state via new snapshot + yield tool again.
          return Stream.fromIterable([
            const RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const StateSnapshotEvent(
              snapshot: {
                'turn': 2,
                'docs': ['doc-a'],
              },
            ),
            const ToolCallStartEvent(
              toolCallId: 'tc-2',
              toolCallName: 'weather',
            ),
            const ToolCallArgsEvent(toolCallId: 'tc-2', delta: '{"city":"LA"}'),
            const ToolCallEndEvent(toolCallId: 'tc-2'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]);
        }
        // Run 3: complete.
        return Stream.fromIterable(_resumeTextEvents());
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (pending) async {
          return pending
              .map(
                (tc) => tc.copyWith(
                  status: ToolCallStatus.completed,
                  result: 'result',
                ),
              )
              .toList();
        },
      );
      expect(result, isA<CompletedState>());

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).captured;

      // 3 calls total.
      expect(captured, hasLength(3));

      // Run 1: initial state should be empty (no cachedHistory).
      final input1 = captured[0] as SimpleRunAgentInput;
      final state1 = input1.state as Map<String, dynamic>;
      expect(state1, isEmpty);

      // Run 2: state from StateSnapshotEvent in run 1.
      final input2 = captured[1] as SimpleRunAgentInput;
      final state2 = input2.state as Map<String, dynamic>;
      expect(state2, containsPair('turn', 1));
      expect(state2['docs'], isEmpty);

      // Run 3: state updated by StateSnapshotEvent in run 2.
      final input3 = captured[2] as SimpleRunAgentInput;
      final state3 = input3.state as Map<String, dynamic>;
      expect(state3, containsPair('turn', 2));
      expect(state3['docs'], equals(['doc-a']));
    });

    test('empty state sent when no cachedHistory or snapshots', () async {
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

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).captured;

      final input = captured.first as SimpleRunAgentInput;
      final state = input.state as Map<String, dynamic>;
      expect(state, isEmpty);
    });
  });

  group('dispose', () {
    test('cleans up resources', () async {
      orchestrator.dispose();

      expect(
        () => orchestrator.startRun(key: _key, userMessage: 'Hi'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('stateChanges stream closes on dispose', () async {
      final done = Completer<void>();
      orchestrator.stateChanges.listen(null, onDone: done.complete);

      orchestrator.dispose();

      await expectLater(done.future, completes);
    });

    test('dispose during active run does not throw', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<RunningState>());

      // Dispose while the stream is still open — should not throw.
      orchestrator.dispose();

      // Emitting after dispose should be silently ignored.
      controller.addError(Exception('connection closed'));
      await controller.close();
    });

    test('double dispose is a no-op', () {
      orchestrator
        ..dispose()
        ..dispose(); // Second call should not throw.
    });
  });

  group('citation extraction', () {
    List<BaseEvent> citationEvents() => [
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          const StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {
                  'chunk-1': {
                    'chunk_id': 'chunk-1',
                    'content': 'Citation text',
                    'document_id': 'doc-1',
                    'document_uri': 'https://example.com/doc.pdf',
                  },
                },
                'citations': ['chunk-1'],
              },
            },
          ),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ];

    test('populates messageStates with citations on CompletedState', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(citationEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final messageStates = completed.conversation.messageStates;

      expect(messageStates, hasLength(1));
      final entry = messageStates.values.first;
      expect(entry.runId, _runId);
      expect(entry.sourceReferences, hasLength(1));
      expect(entry.sourceReferences[0].chunkId, 'chunk-1');
    });

    test('populates messageStates with runId even without citations', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final messageStates = completed.conversation.messageStates;

      expect(messageStates, hasLength(1));
      final entry = messageStates.values.first;
      expect(entry.runId, _runId);
      expect(entry.sourceReferences, isEmpty);
    });

    test('extracts citations at ToolYieldingState', () async {
      orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: agUiStreamClient,
        ),
        toolRegistry: _registryWith(),
        logger: logger,
      );
      stubCreateRun();

      final toolCallWithCitations = <BaseEvent>[
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
        const StateSnapshotEvent(
          snapshot: {
            'rag': {
              'citation_index': {
                'chunk-1': {
                  'chunk_id': 'chunk-1',
                  'content': 'Citation text',
                  'document_id': 'doc-1',
                  'document_uri': 'https://example.com/doc.pdf',
                },
              },
              'citations': ['chunk-1'],
            },
          },
        ),
        const ToolCallStartEvent(
          toolCallId: 'tc-1',
          toolCallName: 'weather',
        ),
        const ToolCallArgsEvent(
          toolCallId: 'tc-1',
          delta: '{"city":"NYC"}',
        ),
        const ToolCallEndEvent(toolCallId: 'tc-1'),
        const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
      ];

      stubRunAgent(stream: Stream.fromIterable(toolCallWithCitations));

      await orchestrator.startRun(key: _key, userMessage: 'Weather?');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<ToolYieldingState>());
      final yielding = orchestrator.currentState as ToolYieldingState;
      final messageStates = yielding.conversation.messageStates;

      expect(messageStates, hasLength(1));
      expect(messageStates.values.first.sourceReferences, hasLength(1));
    });

    test('citations accumulate across tool-resume cycle', () async {
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
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const StateSnapshotEvent(
              snapshot: {
                'rag': {
                  'citation_index': {
                    'chunk-1': {
                      'chunk_id': 'chunk-1',
                      'content': 'First citation',
                      'document_id': 'doc-1',
                      'document_uri': 'https://example.com/doc1.pdf',
                    },
                  },
                  'citations': ['chunk-1'],
                },
              },
            ),
            const ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'weather',
            ),
            const ToolCallArgsEvent(
              toolCallId: 'tc-1',
              delta: '{"city":"NYC"}',
            ),
            const ToolCallEndEvent(toolCallId: 'tc-1'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]);
        }
        return Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-2'),
          const TextMessageContentEvent(messageId: 'msg-2', delta: 'Done'),
          const StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {
                  'chunk-1': {
                    'chunk_id': 'chunk-1',
                    'content': 'First citation',
                    'document_id': 'doc-1',
                    'document_uri': 'https://example.com/doc1.pdf',
                  },
                  'chunk-2': {
                    'chunk_id': 'chunk-2',
                    'content': 'Second citation',
                    'document_id': 'doc-2',
                    'document_uri': 'https://example.com/doc2.pdf',
                  },
                },
                'citations': ['chunk-1', 'chunk-2'],
              },
            },
          ),
          const TextMessageEndEvent(messageId: 'msg-2'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]);
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Search',
        toolExecutor: (pending) async {
          return pending
              .map(
                (tc) => tc.copyWith(
                  status: ToolCallStatus.completed,
                  result: 'result',
                ),
              )
              .toList();
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final messageStates = completed.conversation.messageStates;

      expect(messageStates, hasLength(1));
      final entry = messageStates.values.first;
      expect(entry.sourceReferences, hasLength(2));
      expect(entry.sourceReferences[0].chunkId, 'chunk-1');
      expect(entry.sourceReferences[1].chunkId, 'chunk-2');
    });

    test('duplicate chunks across segments are deduplicated', () async {
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
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          // Segment 1: ask() returns chunk-1 and chunk-2.
          return Stream.fromIterable([
            const RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const StateSnapshotEvent(
              snapshot: {
                'rag': {
                  'citation_index': {
                    'chunk-1': {
                      'chunk_id': 'chunk-1',
                      'content': 'First',
                      'document_id': 'doc-1',
                      'document_uri': 'file:///doc1.pdf',
                    },
                    'chunk-2': {
                      'chunk_id': 'chunk-2',
                      'content': 'Second',
                      'document_id': 'doc-1',
                      'document_uri': 'file:///doc1.pdf',
                    },
                  },
                  'citations': ['chunk-1', 'chunk-2'],
                },
              },
            ),
            const ToolCallStartEvent(
              toolCallId: 'tc-1',
              toolCallName: 'weather',
            ),
            const ToolCallArgsEvent(
              toolCallId: 'tc-1',
              delta: '{"city":"NYC"}',
            ),
            const ToolCallEndEvent(toolCallId: 'tc-1'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]);
        }
        // Segment 2: ask() returns chunk-2 (duplicate) and chunk-3 (new).
        return Stream.fromIterable([
          const RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-2'),
          const TextMessageContentEvent(
            messageId: 'msg-2',
            delta: 'Done',
          ),
          const StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {
                  'chunk-1': {
                    'chunk_id': 'chunk-1',
                    'content': 'First',
                    'document_id': 'doc-1',
                    'document_uri': 'file:///doc1.pdf',
                  },
                  'chunk-2': {
                    'chunk_id': 'chunk-2',
                    'content': 'Second',
                    'document_id': 'doc-1',
                    'document_uri': 'file:///doc1.pdf',
                  },
                  'chunk-3': {
                    'chunk_id': 'chunk-3',
                    'content': 'Third',
                    'document_id': 'doc-2',
                    'document_uri': 'file:///doc2.pdf',
                  },
                },
                'citations': ['chunk-1', 'chunk-2', 'chunk-3'],
              },
            },
          ),
          const TextMessageEndEvent(messageId: 'msg-2'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]);
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Search',
        toolExecutor: (pending) async {
          return pending
              .map(
                (tc) => tc.copyWith(
                  status: ToolCallStatus.completed,
                  result: 'result',
                ),
              )
              .toList();
        },
      );

      expect(result, isA<CompletedState>());
      final completed = result as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;

      // chunk-2 appeared in both segments; should appear only once.
      expect(refs, hasLength(3));
      expect(refs[0].chunkId, 'chunk-1');
      expect(refs[1].chunkId, 'chunk-2');
      expect(refs[2].chunkId, 'chunk-3');
    });

    test('reset clears citation state', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(citationEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<CompletedState>());

      orchestrator.reset();

      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));
      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final entry = completed.conversation.messageStates.values.first;
      expect(entry.sourceReferences, isEmpty);
    });

    test('preserves runId on RunErrorEvent', () async {
      stubCreateRun();

      final events = <BaseEvent>[
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
        const TextMessageStartEvent(messageId: 'msg-1'),
        const TextMessageContentEvent(messageId: 'msg-1', delta: 'Partial'),
        const RunErrorEvent(message: 'server error'),
      ];
      stubRunAgent(stream: Stream.fromIterable(events));

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      final messageStates = failed.conversation!.messageStates;
      expect(messageStates, hasLength(1));
      expect(messageStates.values.first.runId, _runId);
    });

    test('preserves runId on stream error', () async {
      stubCreateRun();

      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      controller.addError(Exception('network lost'));
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      final messageStates = failed.conversation!.messageStates;
      expect(messageStates, hasLength(1));
      expect(messageStates.values.first.runId, _runId);

      await controller.close();
    });

    test('preserves runId on cancelRun', () async {
      stubCreateRun();

      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      controller.add(
        const RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      orchestrator.cancelRun();

      expect(orchestrator.currentState, isA<CancelledState>());
      final cancelled = orchestrator.currentState as CancelledState;
      final messageStates = cancelled.conversation!.messageStates;
      expect(messageStates, hasLength(1));
      expect(messageStates.values.first.runId, _runId);

      await controller.close();
    });
  });
}
