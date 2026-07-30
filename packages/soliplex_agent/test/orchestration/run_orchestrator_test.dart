// These fixtures construct ag_ui 0.3.0's deprecated THINKING_TEXT_MESSAGE_*
// and THINKING_CONTENT events, exercising handling that is kept because a
// producer negotiating ag-ui-protocol below 0.1.13 emits that family live.
// Removal at ag_ui 1.0.0 surfaces as a compile error at these constructors.

import 'dart:async';
import 'dart:convert';

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
      RunStartedEvent(threadId: 'thread-1', runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
    ];

List<BaseEvent> _toolCallEvents({String toolName = 'weather'}) => [
      RunStartedEvent(threadId: 'thread-1', runId: _runId),
      ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: toolName),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"city":"NYC"}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
    ];

List<BaseEvent> _resumeTextEvents() => [
      RunStartedEvent(threadId: 'thread-1', runId: _runId),
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

/// Adapts a test event stream to the orchestrator's `DecodeOutcome`
/// contract. Hand-written events have no source JSON, so `rawJson` is
/// `const {}`.
Stream<DecodeOutcome> _wrap(Stream<BaseEvent> s) =>
    s.map<DecodeOutcome>((e) => DecodedEvent(e, const {}));

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
    ).thenAnswer((_) => _wrap(stream));
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

    test('stamps the user message with the run-start server time', () async {
      const startMs = 1782922475841;
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(
            threadId: 'thread-1',
            runId: _runId,
            timestamp: startMs,
          ),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      final userMessage = completed.conversation.messages
          .whereType<TextMessage>()
          .firstWhere((m) => m.user == ChatUser.user);
      expect(
        userMessage.createdAt,
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
      );
    });
  });

  group('error', () {
    test('RunErrorEvent transitions to FailedState(serverError)', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
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
            RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const TextMessageStartEvent(messageId: 'msg-1'),
          ]),
        );

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<FailedState>());
        final failed = orchestrator.currentState as FailedState;
        expect(failed.reason, equals(FailureReason.networkLost));
        // runId must be threaded through so terminal-state listeners
        // (e.g., the no-response tracker rekey) can find this run.
        expect(failed.runId, equals(_runId));
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
          ..add(RunStartedEvent(threadId: 'thread-1', runId: _runId))
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

    test(
        'RunErrorEvent with buffered thinking surfaces NoResponseTile in '
        'FailedState.conversation', () async {
      // Locks the cross-layer contract: processEvent appends the
      // synthesized tile, _mapEventResult must thread it through into
      // the terminal state's conversation.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const ThinkingStartEvent(),
          // Deprecated upstream; exercises the pre-REASONING_* replay path.
          // ignore: deprecated_member_use
          const ThinkingTextMessageStartEvent(),
          // Deprecated upstream; exercises the pre-REASONING_* replay path.
          // ignore: deprecated_member_use
          const ThinkingTextMessageContentEvent(delta: 'partial reasoning'),
          // Deprecated upstream; exercises the pre-REASONING_* replay path.
          // ignore: deprecated_member_use
          const ThinkingTextMessageEndEvent(),
          const RunErrorEvent(message: 'boom'),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      final synthesized = failed.conversation!.messages.last as NoResponseTile;
      expect(synthesized.id, equals(noResponseMessageId(_runId)));
      expect(synthesized.reason, equals(TerminalReason.failed));
      expect(synthesized.errorDetail, equals('boom'));
      expect(synthesized.thinkingText, equals('partial reasoning'));
    });

    test(
        'RunErrorEvent with empty thinking surfaces ErrorMessage in '
        'FailedState.conversation', () async {
      // Same cross-layer contract test for the empty-thinking fallback
      // branch. Without this, a regression that drops result.conversation
      // in _mapEventResult would not be caught.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const RunErrorEvent(message: 'rate limited'),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      final surfaced = failed.conversation!.messages.last as ErrorMessage;
      expect(surfaced.id, equals('run-error-$_runId'));
      expect(surfaced.errorText, equals('rate limited'));
    });

    test(
        'RunErrorEvent mid-text-stream commits the partial reply text and '
        'appends ErrorMessage', () async {
      // Without this commit the half-streamed reply the user was already
      // reading vanishes when streaming resets to AwaitingText.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'partial'),
          const RunErrorEvent(message: 'connection lost'),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<FailedState>());
      final failed = orchestrator.currentState as FailedState;
      final messages = failed.conversation!.messages;
      final committed =
          messages.firstWhere((m) => m.id == 'msg-1') as TextMessage;
      expect(committed.text, equals('partial'));
      expect(committed.user, equals(ChatUser.assistant));
      final surfaced = messages.firstWhere((m) => m.id == 'run-error-$_runId')
          as ErrorMessage;
      expect(surfaced.errorText, equals('connection lost'));
    });

    test(
        'event with out-of-range timestamp is tolerated; run completes '
        'instead of hanging', () async {
      // An absurd epoch must not throw out of the stream listener (where it
      // would escape the per-event guard and leave the run hung). The
      // timestamp is ignored; the event still processes.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(
            messageId: 'msg-1',
            delta: 'hello',
            // One past DateTime's max epoch-ms (kept under 2^53 for web).
            timestamp: 8640000000000001,
          ),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final reply = completed.conversation.messages
          .whereType<TextMessage>()
          .firstWhere((m) => m.id == 'msg-1');
      expect(reply.text, equals('hello'));
    });
  });

  group('cancel', () {
    test('cancelRun transitions to CancelledState', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller.add(
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
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

    test('cancelRun on Completed state is a no-op', () async {
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<CompletedState>());

      orchestrator.cancelRun();

      expect(orchestrator.currentState, isA<CompletedState>());
    });

    test('cancelRun on Failed state is a no-op', () async {
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable([
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const RunErrorEvent(message: 'backend error'),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<FailedState>());

      orchestrator.cancelRun();

      expect(orchestrator.currentState, isA<FailedState>());
    });

    test('cancelRun on Cancelled state is a no-op', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller.add(
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      orchestrator.cancelRun();
      expect(orchestrator.currentState, isA<CancelledState>());

      orchestrator.cancelRun();
      expect(orchestrator.currentState, isA<CancelledState>());

      await controller.close();
    });

    test(
        'cancelRun on Running with buffered thinking and no reply '
        'synthesizes a NoResponseTile with reason: cancelled', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final staleTs = DateTime.utc(2026).millisecondsSinceEpoch;
      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller
        ..add(RunStartedEvent(threadId: 'thread-1', runId: _runId))
        ..add(const ThinkingStartEvent())
        // Deprecated upstream; exercises the pre-REASONING_* replay path.
        // ignore: deprecated_member_use
        ..add(const ThinkingTextMessageStartEvent())
        ..add(
          // Deprecated upstream; exercises the pre-REASONING_* replay path.
          // ignore: deprecated_member_use
          const ThinkingTextMessageContentEvent(
            delta: 'considering options',
          ),
        )
        // Deprecated upstream; exercises the pre-REASONING_* replay path.
        // ignore: deprecated_member_use
        ..add(ThinkingTextMessageEndEvent(timestamp: staleTs));
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<RunningState>());

      orchestrator.cancelRun();

      final cancelled = orchestrator.currentState as CancelledState;
      final synthesized =
          cancelled.conversation!.messages.last as NoResponseTile;
      expect(synthesized.id, equals(noResponseMessageId(_runId)));
      expect(synthesized.reason, equals(TerminalReason.cancelled));
      expect(synthesized.thinkingText, equals('considering options'));
      // The cancel is a client action with no backend event, so the tile
      // carries the cancel instant (client now) — not the stale last-event
      // time.
      expect(synthesized.createdAt, isNotNull);
      expect(synthesized.createdAt!.isUtc, isTrue);
      expect(synthesized.createdAt!.isAfter(DateTime.utc(2026, 1, 2)), isTrue);

      await controller.close();
    });

    test(
        'cancelRun mid-text-stream commits the partial reply as a finalized '
        'TextMessage (mirrors RunFinished/RunError behavior)', () async {
      // Without the partial-text commit, a half-streamed reply vanishes
      // when streaming resets to AwaitingText on Stop. Synthesis declines
      // on TextStreaming, so the commit is the only surfacing path.
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final lastChunkTime = DateTime.utc(2026, 1, 1, 12);
      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller
        ..add(RunStartedEvent(threadId: 'thread-1', runId: _runId))
        ..add(const TextMessageStartEvent(messageId: 'reply-1'))
        ..add(
          const TextMessageContentEvent(
            messageId: 'reply-1',
            delta: 'half-rendered ',
          ),
        )
        ..add(
          TextMessageContentEvent(
            messageId: 'reply-1',
            delta: 'reply',
            timestamp: lastChunkTime.millisecondsSinceEpoch,
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<RunningState>());

      orchestrator.cancelRun();

      final cancelled = orchestrator.currentState as CancelledState;
      final committed = cancelled.conversation!.messages
          .whereType<TextMessage>()
          .singleWhere((m) => m.id == 'reply-1');
      expect(committed.text, equals('half-rendered reply'));
      expect(committed.user, equals(ChatUser.assistant));
      // The committed partial is backend content, so it carries the last
      // received backend event time — not a client now().
      expect(committed.createdAt, isNotNull);
      expect(committed.createdAt!.isAtSameMomentAs(lastChunkTime), isTrue);
      // No NoResponseTile — partial-commit is the user-visible signal,
      // and synthesis declines on TextStreaming by design.
      expect(
        cancelled.conversation!.messages.whereType<NoResponseTile>(),
        isEmpty,
      );

      await controller.close();
    });
  });

  group('guard', () {
    test('startRun while running throws StateError', () async {
      stubCreateRun();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      await orchestrator.startRun(key: _key, userMessage: 'Hi');
      controller.add(
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
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

    test(
        'continuation run excludes synthesized NoResponseTile, ErrorMessage, '
        'LoadingMessage, and DroppedEventMessage from prior cachedHistory '
        '(wire-leak regression for the convertToAgui skip set)', () async {
      // The wire-leak fix in `agui_message_mapper.convertToAgui` is the
      // last line of defense, but the only way to verify it through the
      // orchestrator is to inspect what `_buildInput` actually sends. A
      // future change that imports cachedHistory unfiltered (or routes
      // around `convertToAgui`) would silently re-introduce the leak.
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final history = ThreadHistory(
        messages: [
          TextMessage.create(
            id: 'prior-user',
            user: ChatUser.user,
            text: 'q',
          ),
          NoResponseTile.cancelled(
            id: noResponseMessageId('prior-run'),
            thinkingText: 'thinking',
          ),
          ErrorMessage.create(id: 'run-error-prior', message: 'boom'),
          LoadingMessage.create(id: 'loading-prior'),
          DroppedEventMessage.create(
            id: 'dropped-prior',
            source: DropSource.decode,
            reason: 'malformed',
          ),
          TextMessage.create(
            id: 'prior-assistant',
            user: ChatUser.assistant,
            text: 'a',
          ),
        ],
      );

      await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'follow-up',
        toolExecutor: (_) async => [],
        cachedHistory: history,
      );

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).captured;

      final input = captured.single as SimpleRunAgentInput;
      final wireMessages = input.messages ?? const [];
      final wireIds = wireMessages.map((m) => m.id).toList();
      // Real conversation messages survive.
      expect(wireIds, contains('prior-user'));
      expect(wireIds, contains('prior-assistant'));
      // Frontend-synthesized tiles are filtered out.
      expect(
        wireIds,
        isNot(contains(noResponseMessageId('prior-run'))),
        reason: 'NoResponseTile is frontend-only; must not reach the backend',
      );
      expect(wireIds, isNot(contains('run-error-prior')));
      expect(wireIds, isNot(contains('loading-prior')));
      expect(wireIds, isNot(contains('dropped-prior')));
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
        return callCount == 1 ? _wrap(first) : _wrap(second);
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
          return _wrap(Stream.fromIterable(_toolCallEvents()));
        }
        return _wrap(Stream.fromIterable(_resumeTextEvents()));
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
      ).thenAnswer((_) => _wrap(Stream.fromIterable(_toolCallEvents())));

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
          return _wrap(Stream.fromIterable(_toolCallEvents()));
        }
        return _wrap(
          Stream<BaseEvent>.error(
            const NetworkException(message: 'transport drop on resume'),
          ),
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
        return _wrap(controller.stream);
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
          return _wrap(Stream.fromIterable(_toolCallEvents()));
        }
        return _wrap(resumeStreamController.stream);
      });

      // Block the tool executor so the test can re-stub createRun before
      // _resumeStream fires.
      final toolExecutorTrigger = Completer<void>();
      var toolExecutorCallCount = 0;
      final runFuture = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) async {
          toolExecutorCallCount++;
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
      expect(
        toolExecutorCallCount,
        equals(1),
        reason: 'the tool must execute exactly once — after the resume drains '
            'on cancel, the loop must not re-enter the tool executor on the '
            'stale ToolYieldingState held by the consumed completer',
      );
    });

    test('reset during _resumeStream createRun await runs the tool once',
        () async {
      // Sibling to the cancelRun-during-resume test: pressing reset (via
      // syncToThread(null) in production) while a tool-yield resume is
      // awaiting createRun must abandon the run without re-executing the
      // tool. reset transitions to the non-terminal IdleState, so without
      // re-minting the consumed completer the loop spins on the stale
      // ToolYieldingState, re-running the tool up to maxToolDepth times
      // before failing on the depth guard.
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
      final resumeStreamController = StreamController<BaseEvent>();
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
          return _wrap(Stream.fromIterable(_toolCallEvents()));
        }
        return _wrap(resumeStreamController.stream);
      });

      final toolExecutorTrigger = Completer<void>();
      var toolExecutorCallCount = 0;
      final runFuture = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Weather?',
        toolExecutor: (_) async {
          toolExecutorCallCount++;
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

      orchestrator.reset();
      expect(
        orchestrator.currentState,
        isA<IdleState>(),
        reason: 'reset must transition to IdleState immediately',
      );

      resumeCreateRun.complete(_runInfo());
      final result = await runFuture;

      expect(
        result,
        isA<IdleState>(),
        reason: 'reset abandons the run; the loop must settle on IdleState '
            'rather than spinning to a depth-exceeded FailedState',
      );
      expect(
        toolExecutorCallCount,
        equals(1),
        reason: 'the tool must execute exactly once — after reset the loop '
            'must not re-run the tool on the stale ToolYieldingState held by '
            'the consumed completer',
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

    test(
        'cancelRun during runToCompletion createRun await yields '
        'CancelledState.preRun (IdleState arm + post-await race close)',
        () async {
      // Stop pressed during a slow createRun while in IdleState.
      // Pins two coupled contracts:
      //   - cancelRun's IdleState arm cancels `_cancelToken` so the
      //     in-flight createRun await aborts (without this arm, the
      //     run continues silently after the response arrives).
      //   - _initializeStream's post-await race close throws
      //     CancelledException when the await resolved before the
      //     token cancellation propagated, so _handleStartError can
      //     route the user's intent to CancelledState.preRun rather
      //     than overwriting it with RunningState via _subscribeToStream.
      final createRunCompleter = Completer<RunInfo>();
      when(
        () => api.createRun(any(), any()),
      ).thenAnswer((_) => createRunCompleter.future);
      stubRunAgent(stream: const Stream<BaseEvent>.empty());

      final runFuture = orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Hi',
        toolExecutor: (_) async => [],
      );
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<IdleState>());

      orchestrator.cancelRun();

      // Resolve the await *after* cancelRun has cancelled the token,
      // simulating the race where startRun's future already had its
      // value before the cancellation propagated.
      createRunCompleter.complete(_runInfo());
      final result = await runFuture;

      expect(
        result,
        isA<CancelledState>(),
        reason: 'state must be CancelledState; without the IdleState arm '
            'the cancel is dropped, and without the post-await race '
            'close _subscribeToStream would overwrite it with RunningState',
      );
      final cancelled = result as CancelledState;
      expect(
        cancelled.startedRun,
        isFalse,
        reason: 'pre-run cancel: no backend run was in flight from the '
            'orchestrator-state perspective',
      );
    });
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
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
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
        ..add(RunStartedEvent(threadId: 'thread-1', runId: _runId))
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
      expect(
        state,
        containsPair('citations', <String>[]),
      );
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
            return _wrap(
              Stream<BaseEvent>.fromIterable([
                RunStartedEvent(threadId: 'thread-1', runId: _runId),
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
              ]),
            );
          }
          // Second run: just complete.
          return _wrap(Stream.fromIterable(_resumeTextEvents()));
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
          return _wrap(
            Stream<BaseEvent>.fromIterable([
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const StateSnapshotEvent(
                snapshot: {'turn': 1, 'docs': <String>[]},
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
            ]),
          );
        }
        if (callCount == 2) {
          // Run 2: update state via new snapshot + yield tool again.
          return _wrap(
            Stream<BaseEvent>.fromIterable([
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
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
              const ToolCallArgsEvent(
                toolCallId: 'tc-2',
                delta: '{"city":"LA"}',
              ),
              const ToolCallEndEvent(toolCallId: 'tc-2'),
              const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
            ]),
          );
        }
        // Run 3: complete.
        return _wrap(Stream.fromIterable(_resumeTextEvents()));
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
      expect(
        state3['docs'],
        equals(['doc-a']),
      );
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
    // A run's cited set arrives either in one terminal StateSnapshotEvent or,
    // for a thread recorded before the backend switched carriers, as
    // StateDeltaEvents whose post-delta `citations` is that contribution's
    // absolute set. Either way `citations` is run-scoped — the turn seeds it
    // empty — while `citation_index` is session-cumulative, so an id cited by
    // an earlier run still resolves.
    StateDeltaEvent namespaceDelta(
      String namespace, {
      required Map<String, Map<String, dynamic>> citationIndex,
      required List<String> citations,
      Map<String, dynamic>? searches,
    }) =>
        StateDeltaEvent(
          delta: [
            {
              'op': 'add',
              'path': '/$namespace',
              'value': {
                'citation_index': citationIndex,
                'citations': citations,
                if (searches != null) 'searches': searches,
              },
            },
          ],
        );

    StateDeltaEvent ragDelta({
      required Map<String, Map<String, dynamic>> citationIndex,
      required List<String> citations,
      Map<String, dynamic>? searches,
    }) =>
        namespaceDelta(
          'rag',
          citationIndex: citationIndex,
          citations: citations,
          searches: searches,
        );

    Map<String, dynamic> citation(
      String chunkId, {
      String documentId = 'doc-1',
      List<String>? pictureRefs,
    }) =>
        {
          'chunk_id': chunkId,
          'content': 'Citation text',
          'document_id': documentId,
          'document_uri': 'https://example.com/doc.pdf',
          if (pictureRefs != null) 'picture_refs': pictureRefs,
        };

    /// One retrieval row carrying an inline figure's base64 bytes, shaped like
    /// a `rag.searches` entry.
    Map<String, dynamic> figureSearch(
      String documentId,
      String ref,
      String base64Bytes,
    ) =>
        {
          'q': [
            {
              'content': 'row',
              'document_id': documentId,
              'image_data': {ref: base64Bytes},
            },
          ],
        };

    List<BaseEvent> citationEvents() => [
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          ragDelta(
            citationIndex: {'chunk-1': citation('chunk-1')},
            citations: ['chunk-1'],
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

    test("credits citations from the run's terminal state snapshot", () async {
      // The backend carries a run's cited set in one StateSnapshotEvent
      // emitted just before RUN_FINISHED, with no deltas at all.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          const TextMessageEndEvent(messageId: 'msg-1'),
          StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {'chunk-1': citation('chunk-1')},
                'citations': ['chunk-1'],
              },
            },
          ),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;

      expect(refs, hasLength(1));
      expect(refs[0].chunkId, 'chunk-1');
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

    test('unions citations across multiple deltas in one run', () async {
      // Two skill invocations in a single run. The backend clears citations at
      // each invocation start, so each delta carries only that invocation's
      // set; the union is the run's complete cited set (Issue 2).
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          ragDelta(
            citationIndex: {'chunk-1': citation('chunk-1')},
            citations: ['chunk-1'],
          ),
          ragDelta(
            citationIndex: {
              'chunk-1': citation('chunk-1'),
              'chunk-2': citation('chunk-2'),
            },
            citations: ['chunk-2'],
          ),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;
      expect(refs, hasLength(2));
      expect(
        refs.map((r) => r.chunkId),
        containsAll(<String>['chunk-1', 'chunk-2']),
      );
    });

    test('keeps an earlier invocation figure after a later one wipes searches',
        () async {
      // Two skill invocations in one run. Invocation 1 cites chunk-1, whose
      // inline figure bytes ride its searches; invocation 2 cites chunk-2 and
      // REPLACES the rag block, so searches no longer holds chunk-1's figure.
      // The turn-level figure accumulator must preserve it.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          ragDelta(
            citationIndex: {
              'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
            },
            citations: ['chunk-1'],
            searches: figureSearch('doc-1', '#/pictures/0', 'aGVsbG8='),
          ),
          ragDelta(
            citationIndex: {
              'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
              'chunk-2': citation('chunk-2', documentId: 'doc-2'),
            },
            citations: ['chunk-2'],
            searches: const {
              'q': [
                {'content': 'row', 'document_id': 'doc-2'},
              ],
            },
          ),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;
      final chunk1 = refs.firstWhere((r) => r.chunkId == 'chunk-1');
      expect(chunk1.figures, hasLength(1));
      expect(chunk1.figures.single.ref, '#/pictures/0');
      expect(chunk1.figures.single.bytes, utf8.encode('hello'));
    });

    test('excludes a stale sibling namespace this run never invoked', () async {
      // rag's cumulative citation_index still resolves a chunk a prior turn
      // cited, but rag was not invoked this run, so its run-scoped citations
      // comes back as the turn seeded it: empty. Only the analysis namespace
      // this run's delta touched may be credited.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {
                  'seed-chunk': {
                    'chunk_id': 'seed-chunk',
                    'content': 'Seed citation',
                    'document_id': 'doc-seed',
                    'document_uri': 'https://example.com/seed.pdf',
                  },
                },
                'citations': <String>[],
              },
            },
          ),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          namespaceDelta(
            'analysis',
            citationIndex: {'chunk-2': citation('chunk-2')},
            citations: ['chunk-2'],
          ),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Analyze');
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;
      expect(refs.map((r) => r.chunkId), ['chunk-2']);
    });

    test('keeps a chunk re-cited from the cumulative index', () async {
      // A chunk a prior turn cited is still in the cumulative citation_index.
      // When this run re-cites it, it must appear — the run's cited set is
      // credited as-is, with no subtraction of what the index already knew.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {
                  'seed-chunk': {
                    'chunk_id': 'seed-chunk',
                    'content': 'Seed citation',
                    'document_id': 'doc-seed',
                    'document_uri': 'https://example.com/seed.pdf',
                  },
                },
                'citations': <String>[],
              },
            },
          ),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          ragDelta(
            citationIndex: {'seed-chunk': citation('seed-chunk')},
            citations: ['seed-chunk'],
          ),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;
      expect(refs.map((r) => r.chunkId), ['seed-chunk']);
    });

    test('credits nothing when the terminal snapshot cites nothing', () async {
      // The snapshot's cumulative citation_index can resolve a chunk, but the
      // run cited none. Credit follows what `citations` says was cited, not
      // what the index happens to be able to resolve.
      stubCreateRun();
      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          const StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {
                  'seed-chunk': {
                    'chunk_id': 'seed-chunk',
                    'content': 'Seed citation',
                    'document_id': 'doc-seed',
                    'document_uri': 'https://example.com/seed.pdf',
                  },
                },
                'citations': <String>[],
              },
            },
          ),
          const TextMessageStartEvent(messageId: 'msg-1'),
          const TextMessageContentEvent(messageId: 'msg-1', delta: 'Answer'),
          const TextMessageEndEvent(messageId: 'msg-1'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);

      final completed = orchestrator.currentState as CompletedState;
      final entry = completed.conversation.messageStates.values.first;
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
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
        ragDelta(
          citationIndex: {'chunk-1': citation('chunk-1')},
          citations: ['chunk-1'],
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
          // Invocation 1 cites chunk-1.
          return _wrap(
            Stream<BaseEvent>.fromIterable([
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              ragDelta(
                citationIndex: {'chunk-1': citation('chunk-1')},
                citations: ['chunk-1'],
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
            ]),
          );
        }
        // Invocation 2 clears citations and cites only chunk-2; the index
        // stays session-cumulative.
        return _wrap(
          Stream<BaseEvent>.fromIterable([
            RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const TextMessageStartEvent(messageId: 'msg-2'),
            const TextMessageContentEvent(messageId: 'msg-2', delta: 'Done'),
            ragDelta(
              citationIndex: {
                'chunk-1': citation('chunk-1'),
                'chunk-2': citation('chunk-2'),
              },
              citations: ['chunk-2'],
            ),
            const TextMessageEndEvent(messageId: 'msg-2'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]),
        );
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

    test("keeps both runs' figures across a snapshot-carried tool resume",
        () async {
      // A turn spanning two runs, each carrying its cited set in its own
      // terminal snapshot. `citation_index` is session-cumulative, so run 1's
      // chunk still resolves from run 2's snapshot — but `searches` is cleared
      // per run, so run 2's snapshot holds none of run 1's figure bytes. The
      // turn accumulator is the only thing that can still supply them, which
      // makes this the case where a lost merge is silent: the citation renders
      // with its text intact and its image missing.
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
          return _wrap(
            Stream<BaseEvent>.fromIterable([
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const ToolCallStartEvent(
                toolCallId: 'tc-1',
                toolCallName: 'weather',
              ),
              const ToolCallArgsEvent(
                toolCallId: 'tc-1',
                delta: '{"city":"NYC"}',
              ),
              const ToolCallEndEvent(toolCallId: 'tc-1'),
              StateSnapshotEvent(
                snapshot: {
                  'rag': {
                    'citation_index': {
                      'chunk-1':
                          citation('chunk-1', pictureRefs: ['#/pictures/0']),
                    },
                    'citations': ['chunk-1'],
                    'searches':
                        figureSearch('doc-1', '#/pictures/0', 'aGVsbG8='),
                  },
                },
              ),
              const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
            ]),
          );
        }
        return _wrap(
          Stream<BaseEvent>.fromIterable([
            RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const TextMessageStartEvent(messageId: 'msg-2'),
            const TextMessageContentEvent(messageId: 'msg-2', delta: 'Done'),
            StateSnapshotEvent(
              snapshot: {
                'rag': {
                  'citation_index': {
                    'chunk-1':
                        citation('chunk-1', pictureRefs: ['#/pictures/0']),
                    'chunk-2': citation(
                      'chunk-2',
                      documentId: 'doc-2',
                      pictureRefs: ['#/pictures/0'],
                    ),
                  },
                  'citations': ['chunk-2'],
                  'searches': figureSearch('doc-2', '#/pictures/0', 'd29ybGQ='),
                },
              },
            ),
            const TextMessageEndEvent(messageId: 'msg-2'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]),
        );
      });

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: 'Search',
        toolExecutor: (pending) async => pending
            .map(
              (tc) => tc.copyWith(
                status: ToolCallStatus.completed,
                result: 'result',
              ),
            )
            .toList(),
      );

      final completed = result as CompletedState;
      final refs =
          completed.conversation.messageStates.values.first.sourceReferences;

      expect(refs.map((r) => r.chunkId), ['chunk-1', 'chunk-2']);
      expect(refs[0].figures.single.bytes, base64Decode('aGVsbG8='));
      expect(refs[1].figures.single.bytes, base64Decode('d29ybGQ='));
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
          // Invocation 1 cites chunk-1 and chunk-2.
          return _wrap(
            Stream<BaseEvent>.fromIterable([
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              ragDelta(
                citationIndex: {
                  'chunk-1': citation('chunk-1'),
                  'chunk-2': citation('chunk-2'),
                },
                citations: ['chunk-1', 'chunk-2'],
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
            ]),
          );
        }
        // Invocation 2 re-cites chunk-2 (duplicate) and adds chunk-3.
        return _wrap(
          Stream<BaseEvent>.fromIterable([
            RunStartedEvent(threadId: 'thread-1', runId: _runId),
            const TextMessageStartEvent(messageId: 'msg-2'),
            const TextMessageContentEvent(
              messageId: 'msg-2',
              delta: 'Done',
            ),
            ragDelta(
              citationIndex: {
                'chunk-1': citation('chunk-1'),
                'chunk-2': citation('chunk-2'),
                'chunk-3': citation('chunk-3'),
              },
              citations: ['chunk-2', 'chunk-3'],
            ),
            const TextMessageEndEvent(messageId: 'msg-2'),
            const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
          ]),
        );
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

    test("does not leak a prior turn's citations into the next turn", () async {
      // Two turns back-to-back with no reset between them. Turn 1 cites
      // chunk-1; turn 2 cites nothing, but chunk-1 is still in turn 2's
      // cumulative citation_index. The turn accumulator is cleared at turn
      // start, so turn 2 shows no sources — otherwise turn 1's id would
      // resolve against turn 2's state and leak in. This isolates the
      // turn-start clear: reset and syncToThread also null _userMessageId
      // (short-circuiting resolve), so only a back-to-back run exercises it.
      stubCreateRun();
      stubRunAgent(stream: Stream.fromIterable(citationEvents()));

      await orchestrator.startRun(key: _key, userMessage: 'Search');
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.currentState, isA<CompletedState>());

      stubRunAgent(
        stream: Stream.fromIterable(<BaseEvent>[
          RunStartedEvent(threadId: 'thread-1', runId: _runId),
          StateSnapshotEvent(
            snapshot: {
              'rag': {
                'citation_index': {'chunk-1': citation('chunk-1')},
                'citations': <String>[],
              },
            },
          ),
          const TextMessageStartEvent(messageId: 'msg-2'),
          const TextMessageContentEvent(messageId: 'msg-2', delta: 'Answer'),
          const TextMessageEndEvent(messageId: 'msg-2'),
          const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
        ]),
      );
      await orchestrator.startRun(key: _key, userMessage: 'Again');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      final entry = completed.conversation.messageStates.values.first;
      expect(entry.sourceReferences, isEmpty);
    });

    test('preserves runId on RunErrorEvent', () async {
      stubCreateRun();

      final events = <BaseEvent>[
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
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
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
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
        RunStartedEvent(threadId: 'thread-1', runId: _runId),
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

  group('live drop tiles', () {
    test(
      'DecodeFailed yields a DroppedEventMessage(decode); run still '
      'finishes and the tracker never sees the failure',
      () async {
        stubCreateRun();
        final controller = StreamController<DecodeOutcome>();
        when(
          () => agUiStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => controller.stream);

        final trackerEvents = <BaseEvent>[];
        final trackerSub = orchestrator.baseEvents.listen(trackerEvents.add);
        addTearDown(trackerSub.cancel);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        // Backend run-started, then an undecodable payload, then a
        // structurally-valid text turn, then RunFinished.
        controller
          ..add(
            DecodedEvent(
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const {'type': 'RUN_STARTED'},
            ),
          )
          ..add(
            const DecodeFailed(
              FormatException('boom'),
              <String, dynamic>{'type': 'GIBBERISH', 'foo': 'bar'},
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageStartEvent(messageId: 'msg-1'),
              {'type': 'TEXT_MESSAGE_START'},
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageContentEvent(
                messageId: 'msg-1',
                delta: 'Hello',
              ),
              {'type': 'TEXT_MESSAGE_CONTENT'},
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageEndEvent(messageId: 'msg-1'),
              {'type': 'TEXT_MESSAGE_END'},
            ),
          )
          ..add(
            const DecodedEvent(
              RunFinishedEvent(threadId: 'thread-1', runId: _runId),
              {'type': 'RUN_FINISHED'},
            ),
          );
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<CompletedState>());
        final completed = orchestrator.currentState as CompletedState;
        final messages = completed.conversation.messages;
        // Drop tile must sit between the user input and the assistant
        // reply, not be flushed at run-end.
        expect(
          messages.map((m) => m.runtimeType).toList(),
          equals([TextMessage, DroppedEventMessage, TextMessage]),
        );
        final drops = messages.whereType<DroppedEventMessage>().toList();
        expect(drops, hasLength(1));
        expect(drops.single.source, equals(DropSource.decode));
        expect(drops.single.runId, equals(_runId));
        expect(drops.single.id, startsWith('dropped-$_runId-'));
        expect(drops.single.rawPayload, containsPair('type', 'GIBBERISH'));
        // The reply still landed.
        expect(
          messages.whereType<TextMessage>().where((m) => m.text == 'Hello'),
          hasLength(1),
        );
        // Tracker never saw the DecodeFailed payload — only events
        // whose application-layer processing succeeded reach
        // baseEvents, keeping the tracker consistent with the
        // conversation.
        expect(
          trackerEvents.map((e) => e.runtimeType).toList(),
          equals([
            RunStartedEvent,
            TextMessageStartEvent,
            TextMessageContentEvent,
            TextMessageEndEvent,
            RunFinishedEvent,
          ]),
        );

        await controller.close();
      },
    );

    test(
      'a processEvent throw yields DroppedEventMessage(eventProcessing); '
      'subsequent events still process',
      () async {
        stubCreateRun();
        final controller = StreamController<DecodeOutcome>();
        when(
          () => agUiStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => controller.stream);

        final trackerEvents = <BaseEvent>[];
        final trackerSub = orchestrator.baseEvents.listen(trackerEvents.add);
        addTearDown(trackerSub.cancel);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        controller
          ..add(
            DecodedEvent(
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const {'type': 'RUN_STARTED'},
            ),
          )
          // Non-Map snapshot triggers the cast throw inside
          // _processStateSnapshot — the wrapper catches it.
          ..add(
            const DecodedEvent(
              StateSnapshotEvent(snapshot: ['not', 'a', 'map']),
              {
                'type': 'STATE_SNAPSHOT',
                'snapshot': ['not', 'a', 'map'],
              },
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageStartEvent(messageId: 'msg-1'),
              {'type': 'TEXT_MESSAGE_START'},
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageContentEvent(
                messageId: 'msg-1',
                delta: 'survived',
              ),
              {'type': 'TEXT_MESSAGE_CONTENT'},
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageEndEvent(messageId: 'msg-1'),
              {'type': 'TEXT_MESSAGE_END'},
            ),
          )
          ..add(
            const DecodedEvent(
              RunFinishedEvent(threadId: 'thread-1', runId: _runId),
              {'type': 'RUN_FINISHED'},
            ),
          );
        await Future<void>.delayed(Duration.zero);

        expect(orchestrator.currentState, isA<CompletedState>());
        final completed = orchestrator.currentState as CompletedState;
        final messages = completed.conversation.messages;
        final drops = messages.whereType<DroppedEventMessage>().toList();
        expect(drops, hasLength(1));
        expect(drops.single.source, equals(DropSource.eventProcessing));
        expect(drops.single.rawPayload, containsPair('type', 'STATE_SNAPSHOT'));
        // The text turn that arrived after the throw still rendered.
        expect(
          messages.whereType<TextMessage>().where((m) => m.text == 'survived'),
          hasLength(1),
        );
        // The throwing StateSnapshotEvent never reaches baseEvents —
        // a tracker observing the stream stays consistent with the
        // conversation, which never reflected the bad snapshot.
        expect(
          trackerEvents.map((e) => e.runtimeType).toList(),
          equals([
            RunStartedEvent,
            TextMessageStartEvent,
            TextMessageContentEvent,
            TextMessageEndEvent,
            RunFinishedEvent,
          ]),
        );

        await controller.close();
      },
    );

    test(
      'live DecodeFailed with String rawData preserves it on the tile',
      () async {
        // Top-level JSON parse failures arrive with `rawData: String`.
        // The orchestrator must pass that through unmodified — the tile
        // widget renders the raw bytes so a developer can inspect the
        // wire content the parser rejected.
        stubCreateRun();
        final controller = StreamController<DecodeOutcome>();
        when(
          () => agUiStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => controller.stream);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        controller
          ..add(
            DecodedEvent(
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const {'type': 'RUN_STARTED'},
            ),
          )
          ..add(
            const DecodeFailed(
              FormatException('Unexpected character'),
              'not valid json at all',
            ),
          )
          ..add(
            const DecodedEvent(
              RunFinishedEvent(threadId: 'thread-1', runId: _runId),
              {'type': 'RUN_FINISHED'},
            ),
          );
        await Future<void>.delayed(Duration.zero);

        final completed = orchestrator.currentState as CompletedState;
        final drop = completed.conversation.messages
            .whereType<DroppedEventMessage>()
            .single;
        expect(drop.rawPayload, equals('not valid json at all'));

        await controller.close();
      },
    );

    test(
      'live drop tile ids align with the replay formula at the same '
      'event position',
      () async {
        // Live mints `dropped-${runId}-${eventIndex}` from a per-event
        // counter; replay mints `dropped-${runId}-${i}` from the loop
        // index over backend-stored events. Both formulas must produce
        // the same id for the same backend event so reload reconstructs
        // the same drop set. This pins the live counter's positional
        // invariant; the replay-side companion is in
        // `soliplex_api_test.dart`'s `replay drop tile ids are
        // deterministic across reloads`.
        stubCreateRun();
        final controller = StreamController<DecodeOutcome>();
        when(
          () => agUiStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => controller.stream);

        await orchestrator.startRun(key: _key, userMessage: 'Hi');
        // Outcome positions: 0 RunStarted, 1 DecodeFailed, 2 TextStart,
        // 3 STATE_SNAPSHOT (throws inside processEvent), 4 RunFinished.
        controller
          ..add(
            DecodedEvent(
              RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const {'type': 'RUN_STARTED'},
            ),
          )
          ..add(
            const DecodeFailed(
              FormatException('boom'),
              {'type': 'GIBBERISH'},
            ),
          )
          ..add(
            const DecodedEvent(
              TextMessageStartEvent(messageId: 'msg-1'),
              {'type': 'TEXT_MESSAGE_START'},
            ),
          )
          ..add(
            const DecodedEvent(
              StateSnapshotEvent(snapshot: ['not', 'a', 'map']),
              {
                'type': 'STATE_SNAPSHOT',
                'snapshot': ['not', 'a', 'map'],
              },
            ),
          )
          ..add(
            const DecodedEvent(
              RunFinishedEvent(threadId: 'thread-1', runId: _runId),
              {'type': 'RUN_FINISHED'},
            ),
          );
        await Future<void>.delayed(Duration.zero);

        final completed = orchestrator.currentState as CompletedState;
        final drops = completed.conversation.messages
            .whereType<DroppedEventMessage>()
            .map((m) => m.id)
            .toList();
        // Replay over the same backend events would mint these same
        // ids — `dropped-<runId>-<positional-index>` aligns the live
        // counter to the replay loop's `i`.
        expect(
          drops,
          equals(['dropped-$_runId-1', 'dropped-$_runId-3']),
        );

        await controller.close();
      },
    );
  });
}
