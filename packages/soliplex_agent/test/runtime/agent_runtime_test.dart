import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/tools/tool_registry_resolver.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:soliplex_logging/soliplex_logging.dart'
    show LogLevel, MemorySink;
import 'package:test/test.dart';

import '../helpers/create_run_bodies.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

/// Adapts a test event stream to the orchestrator's `DecodeOutcome`
/// contract. Hand-written events have no source JSON, so `rawJson` is
/// `const {}`.
Stream<DecodeOutcome> _wrap(Stream<BaseEvent> s) =>
    s.map<DecodeOutcome>((e) => DecodedEvent(e, const {}));

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _TestExtension extends SessionExtension {
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

class _ThrowingExtension extends SessionExtension {
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
      RunStartedEvent(threadId: _threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _toolCallEvents() => [
      RunStartedEvent(threadId: _threadId, runId: _runId),
      const ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather'),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"city":"NYC"}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _resumeTextEvents() => [
      RunStartedEvent(threadId: _threadId, runId: _runId),
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
    registerFallbackValue(Uri());
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
    AgentLlmProvider? llmProvider,
  }) {
    return AgentRuntime(
      connection: mockConnection(),
      llmProvider: llmProvider ??
          AgUiLlmProvider(
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
    when(
      () => api.createRun(any(), any(), parentRunId: any(named: 'parentRunId')),
    ).thenAnswer((_) async => _runInfo());
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
    ).thenAnswer(
      (_) => stream.map<DecodeOutcome>((e) => DecodedEvent(e, const {})),
    );
  }

  group('thread history carried between sends', () {
    test('a second send keeps how the runs before it ended', () async {
      // Every send rebuilds the conversation from the cached history, and the
      // record of a run that ended with nothing to show for itself lives only
      // there — no message carries it, and the backend cannot replay it. Lose
      // it here and the first turn's work has no tile to render on from the
      // moment the user sends again.
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      var call = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        call++;
        final events = call == 1
            ? <BaseEvent>[
                RunStartedEvent(threadId: _threadId, runId: 'run-first'),
                const ReasoningMessageStartEvent(messageId: 'reason-1'),
                const ReasoningMessageContentEvent(
                  messageId: 'reason-1',
                  delta: 'weighing it',
                ),
                const ReasoningMessageEndEvent(messageId: 'reason-1'),
                const RunFinishedEvent(threadId: _threadId, runId: 'run-first'),
              ]
            : _happyPathEvents();
        return Stream.fromIterable(events)
            .map<DecodeOutcome>((e) => DecodedEvent(e, const {}));
      });

      final first =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hi')]);
      await first.result;
      final second = await runtime.spawn(
        roomId: _roomId,
        threadId: _threadId,
        prompt: [const TextPart('And again')],
      );
      await second.result;

      final outcomes = switch (second.runState.value) {
        CompletedState(:final conversation) => conversation.runOutcomes,
        _ => const <String, NoResponseTile>{},
      };
      expect(
        outcomes['run-first'],
        isNotNull,
        reason: 'the first run ended saying nothing, and the second send '
            'is where that record has to survive',
      );
      expect(outcomes['run-first']!.thinkingText, equals('weighing it'));
    });

    test('a send after a run whose state was left incomplete carries the mark',
        () async {
      // Each stream breaks off without the closing snapshot that would replace
      // the state: the first after a delta that did not apply, the second
      // before any state event. What the second send starts from, and what the
      // next send reads, is the incomplete state.
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      var call = 0;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        call++;
        final runId = 'run-$call';
        return () async* {
          yield DecodedEvent(
            RunStartedEvent(threadId: _threadId, runId: runId),
            const {},
          );
          if (call == 1) {
            yield const DecodedEvent(
              StateDeltaEvent(
                delta: [
                  {'op': 'replace', 'path': '/rag/citations/0', 'value': 'c1'},
                ],
              ),
              {},
            );
          }
          throw const NetworkException(message: 'connection reset');
        }();
      });

      final first =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hi')]);
      await first.result;
      final second = await runtime.spawn(
        roomId: _roomId,
        threadId: _threadId,
        prompt: [const TextPart('And again')],
      );
      await second.result;

      expect(
        runtime.threadStateOf(second.threadKey)?.history?.aguiStateIncomplete,
        isTrue,
      );
    });

    group('a new turn names the run the history it sends ends with', () {
      late List<Object?> createRunBodies;

      setUp(() async {
        await runtime.dispose();
        final recording = providerRecordingCreateRunBodies(agUiStreamClient);
        createRunBodies = recording.createRunBodies;
        runtime = createRuntime(
          llmProvider: recording.provider,
          resolver: (_) async => _weatherRegistry(),
        );
      });

      void stubStreams(List<Stream<DecodeOutcome>> streams) {
        when(
          () => agUiStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => streams.removeAt(0));
      }

      Future<void> send(String prompt) async {
        final session = await runtime.spawn(
          roomId: _roomId,
          threadId: _threadId,
          prompt: [TextPart(prompt)],
        );
        await session.result;
        // The history is captured once the result's listeners have run.
        await Future<void>.delayed(Duration.zero);
      }

      test('after a turn a client tool continued, its last run', () async {
        stubStreams([
          _wrap(Stream.fromIterable(_toolCallEvents())),
          _wrap(Stream.fromIterable(_resumeTextEvents())),
          _wrap(Stream.fromIterable(_happyPathEvents())),
        ]);

        await send('Weather?');
        await send('And tomorrow?');

        expect(createRunBodies, [
          <String, dynamic>{},
          {'parent_run_id': 'run-1'},
          {'parent_run_id': 'run-2'},
        ]);
      });

      test('after a run cut off mid-reply, that run', () async {
        // The history keeps only what the cut-off run was sent, and that
        // carries its user message, so the next input still extends it.
        stubStreams([
          () async* {
            yield DecodedEvent(
              RunStartedEvent(threadId: _threadId, runId: _runId),
              const {},
            );
            yield const DecodedEvent(
              TextMessageStartEvent(messageId: 'msg-1'),
              {},
            );
            yield const DecodedEvent(
              TextMessageContentEvent(messageId: 'msg-1', delta: 'Hal'),
              {},
            );
            throw const NetworkException(message: 'connection reset');
          }(),
          _wrap(Stream.fromIterable(_happyPathEvents())),
        ]);

        await send('Hi');
        await send('And again');

        expect(createRunBodies, [
          <String, dynamic>{},
          {'parent_run_id': 'run-1'},
        ]);
      });
    });
  });

  group('follow', () {
    test(
        'a run followed to its end is in the history the next send on the '
        'thread carries', () async {
      when(
        () => agUiStreamClient.followRun(
          'rooms/$_roomId/agui/$_threadId/$_runId',
          _runId,
          cancelToken: any(named: 'cancelToken'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) => _wrap(Stream.fromIterable(_happyPathEvents())));
      final followed = await runtime.follow(
        roomId: _roomId,
        threadId: _threadId,
        run: RunInProgress(
          runId: _runId,
          userMessage: TextMessage.create(
            id: 'user-stored',
            user: ChatUser.user,
            text: 'Hi there',
            runId: _runId,
          ),
        ),
      );
      expect(await followed.result, isA<AgentSuccess>());
      await pumpEventQueue();

      stubCreateRun();
      SimpleRunAgentInput? sent;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((invocation) {
        sent = invocation.positionalArguments[1] as SimpleRunAgentInput;
        return _wrap(Stream.fromIterable(_happyPathEvents()));
      });
      final next = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('And now?')],
        threadId: _threadId,
      );
      await next.result;

      expect(
        [for (final m in sent!.messages!) m.toJson()['content']],
        ['Hi there', 'Hello', 'And now?'],
      );
    });
  });

  group('spawn', () {
    test('creates thread, starts session, returns AgentSuccess', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);
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
        prompt: [const TextPart('Hello')],
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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

      await session.result;
      // Should NOT call createRun because initialRunId was provided
      verifyNever(
        () =>
            api.createRun(any(), any(), parentRunId: any(named: 'parentRunId')),
      );
    });

    group("a thread's unused initial run", () {
      const key = (serverId: 'default', roomId: _roomId, threadId: _threadId);

      setUp(() {
        runtime.seedThreadHistory(
          key,
          ThreadHistory(messages: const [], unusedInitialRunId: 'run-initial'),
        );
        stubCreateRun();
        stubDeleteThread();
      });

      /// Answers each run with [answer], given the run id the run was sent
      /// with, how many runs came before it, and the run's cancel token, and
      /// returns every run's input in the order they were sent.
      List<SimpleRunAgentInput> answerRuns(
        Stream<BaseEvent> Function(String? runId, int index, CancelToken token)
            answer,
      ) {
        final sent = <SimpleRunAgentInput>[];
        when(
          () => agUiStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((invocation) {
          final input =
              invocation.positionalArguments[1] as SimpleRunAgentInput;
          final index = sent.length;
          sent.add(input);
          return _wrap(
            answer(
              input.runId,
              index,
              invocation.namedArguments[#cancelToken] as CancelToken,
            ),
          );
        });
        return sent;
      }

      List<String?> runIds(List<SimpleRunAgentInput> sent) =>
          [for (final input in sent) input.runId];

      /// The text of the user messages [input] carries.
      List<Object?> userTexts(SimpleRunAgentInput input) => [
            for (final message in input.messages ?? const <Message>[])
              if (message is UserMessage) message.content,
          ];

      /// The thread as the backend reports it when the run is re-read.
      void threadReadsAs(ThreadHistory history) {
        when(
          () => api.getThreadHistory(
            _roomId,
            _threadId,
            cancelToken: any(named: 'cancelToken'),
            observer: any(named: 'observer'),
          ),
        ).thenAnswer((_) async => history);
      }

      Future<AgentResult> send(String text) async {
        final session = await runtime.spawn(
          roomId: _roomId,
          prompt: [TextPart(text)],
          threadId: _threadId,
        );
        return session.result;
      }

      Stream<BaseEvent> answered(String? _, int __, CancelToken ___) =>
          Stream.fromIterable(_happyPathEvents());

      ApiException alreadyStarted() => const ApiException(
            message: 'HTTP 400: Bad Request',
            statusCode: 400,
          );

      test('runs the first send on it, and a later send on a run of its own',
          () async {
        final sent = answerRuns(answered);

        final first = await send('First');
        await send('Second');

        expect(runIds(sent), ['run-initial', _runId]);
        expect((first as AgentSuccess).output, 'Hello');
      });

      test('a later history without it leaves the next send a run of its own',
          () async {
        final sent = answerRuns(answered);
        runtime.seedThreadHistory(key, ThreadHistory(messages: const []));

        await send('First');

        expect(runIds(sent), [_runId]);
      });

      for (final refusal in const <SoliplexException>[
        AuthException(message: 'HTTP 401: Unauthorized', statusCode: 401),
        PermissionDeniedException(
          message: 'HTTP 403: Forbidden',
          statusCode: 403,
        ),
        NotFoundException(message: 'HTTP 404: Not Found'),
      ]) {
        test(
            'keeps it for the next send when the backend refuses the send '
            '(${refusal.runtimeType})', () async {
          final sent = answerRuns(
            (runId, index, token) => index == 0
                ? Stream.error(refusal)
                : answered(runId, index, token),
          );

          expect(await send('First'), isA<AgentFailure>());
          await send('Again');

          expect(runIds(sent), ['run-initial', 'run-initial']);
        });
      }

      test('keeps it for the next send when the session cannot be built',
          () async {
        var resolves = 0;
        await runtime.dispose();
        runtime = createRuntime(
          resolver: (_) async {
            if (resolves++ == 0) throw StateError('tools unavailable');
            return const ToolRegistry();
          },
        )..seedThreadHistory(
            key,
            ThreadHistory(
              messages: const [],
              unusedInitialRunId: 'run-initial',
            ),
          );
        final sent = answerRuns(answered);

        await expectLater(send('First'), throwsStateError);
        await send('Again');

        expect(runIds(sent), ['run-initial']);
      });

      test(
          'leaves the next send a run of its own, carrying the message, when '
          'the connection drops before the backend answers', () async {
        final sent = answerRuns(
          (runId, index, token) => index == 0
              ? Stream.error(const NetworkException(message: 'Connection lost'))
              : answered(runId, index, token),
        );

        expect(await send('First'), isA<AgentFailure>());
        await send('Again');

        expect(runIds(sent), ['run-initial', _runId]);
        expect(userTexts(sent.last), ['First', 'Again']);
      });

      test(
          'leaves the next send a run of its own, carrying the message, when '
          'a send is stopped before the backend answers', () async {
        final waiting = Completer<void>();
        final sent = answerRuns((runId, index, token) {
          if (index > 0) return answered(runId, index, token);
          // The backend never answers; the stream ends as the real client's
          // does when its token is cancelled.
          final controller = StreamController<BaseEvent>();
          unawaited(
            token.whenCancelled.then((_) {
              controller.addError(const CancelledException());
              unawaited(controller.close());
            }),
          );
          waiting.complete();
          return controller.stream;
        });

        final session = await runtime.spawn(
          roomId: _roomId,
          prompt: [const TextPart('First')],
          threadId: _threadId,
        );
        await waiting.future;
        await pumpEventQueue();
        session.cancel();
        final result = await session.result;
        await send('Again');

        expect((result as AgentFailure).reason, FailureReason.cancelled);
        expect(runIds(sent), ['run-initial', _runId]);
        expect(userTexts(sent.last), ['First', 'Again']);
      });

      test(
          'leaves the next send a run of its own when a send fails after the '
          'backend answered', () async {
        final sent = answerRuns(
          (runId, index, token) => index == 0
              ? () async* {
                  yield* Stream.fromIterable(_happyPathEvents().take(2));
                  throw const NetworkException(message: 'Connection lost');
                }()
              : answered(runId, index, token),
        );

        expect(await send('First'), isA<AgentFailure>());
        await send('Again');

        expect(runIds(sent), ['run-initial', _runId]);
      });

      test(
          'sends again on a run of its own when the backend refuses the run '
          'because another client started it', () async {
        threadReadsAs(ThreadHistory(messages: const []));
        final sent = answerRuns(
          (runId, index, token) => runId == 'run-initial'
              ? Stream.error(alreadyStarted())
              : answered(runId, index, token),
        );

        final result = await send('First');

        expect(result, isA<AgentSuccess>());
        expect(runIds(sent), ['run-initial', _runId]);
      });

      test(
          'records that it found the run started, even when no run can be '
          'made for the message', () async {
        final sink = MemorySink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));
        threadReadsAs(ThreadHistory(messages: const []));
        when(
          () => api.createRun(
            any(),
            any(),
            parentRunId: any(named: 'parentRunId'),
          ),
        ).thenThrow(
          const ApiException(
            message: 'HTTP 500: Internal Server Error',
            statusCode: 500,
          ),
        );
        answerRuns((_, __, ___) => Stream.error(alreadyStarted()));

        expect(await send('First'), isA<AgentFailure>());

        final records = [
          for (final record in sink.records)
            if (record.attributes['refusedRunId'] == 'run-initial') record,
        ];
        expect(records, hasLength(1));
        expect(records.single.level, LogLevel.warning);
        expect(records.single.error, isA<ApiException>());
      });

      test(
          'reports the refusal, and keeps it for the next send, when the '
          'thread cannot be re-read', () async {
        when(
          () => api.getThreadHistory(
            _roomId,
            _threadId,
            cancelToken: any(named: 'cancelToken'),
            observer: any(named: 'observer'),
          ),
        ).thenThrow(const NetworkException(message: 'Connection lost'));
        final sent = answerRuns(
          (runId, index, token) => index == 0
              ? Stream.error(alreadyStarted())
              : answered(runId, index, token),
        );

        final sink = MemorySink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));

        final result = await send('First');
        await send('Again');

        expect((result as AgentFailure).error, contains('HTTP 400'));
        expect(runIds(sent), ['run-initial', 'run-initial']);
        final reread = [
          for (final record in sink.records)
            if (record.level == LogLevel.warning &&
                record.error is NetworkException)
              record,
        ];
        expect(reread, hasLength(1));
      });

      test(
          'does not send again, and keeps the run, when a 400 leaves the run '
          'unused', () async {
        threadReadsAs(
          ThreadHistory(messages: const [], unusedInitialRunId: 'run-initial'),
        );
        final sent = answerRuns((_, __, ___) => Stream.error(alreadyStarted()));

        expect(await send('First'), isA<AgentFailure>());
        await send('Again');

        expect(runIds(sent), ['run-initial', 'run-initial']);
      });

      test(
          'does not send again, and keeps the run, on a refusal other than a '
          '400', () async {
        threadReadsAs(ThreadHistory(messages: const []));
        final sent = answerRuns(
          (_, __, ___) => Stream.error(
            const ApiException(
              message: 'HTTP 422: Unprocessable Entity',
              statusCode: 422,
            ),
          ),
        );

        expect(await send('First'), isA<AgentFailure>());
        await send('Again');

        expect(runIds(sent), ['run-initial', 'run-initial']);
      });

      test(
          'leaves the next send a run of its own when the backend fails the '
          'send with a server error', () async {
        threadReadsAs(ThreadHistory(messages: const []));
        final sent = answerRuns(
          (runId, index, token) => index == 0
              ? Stream.error(
                  const ApiException(
                    message: 'HTTP 500: Internal Server Error',
                    statusCode: 500,
                  ),
                )
              : answered(runId, index, token),
        );

        expect(await send('First'), isA<AgentFailure>());
        await send('Again');

        expect(runIds(sent), ['run-initial', _runId]);
      });

      test('sends again at most once, and not on it again', () async {
        threadReadsAs(ThreadHistory(messages: const []));
        final sent = answerRuns((_, __, ___) => Stream.error(alreadyStarted()));

        final result = await send('First');
        await send('Again');

        expect(result, isA<AgentFailure>());
        expect(runIds(sent), ['run-initial', _runId, _runId]);
      });

      test(
          'keeps the run a new thread was made with for the next send when '
          'the backend refuses the first', () async {
        stubCreateThread(
          info: ThreadInfo(
            id: _threadId,
            roomId: _roomId,
            initialRunId: 'run-made-with-thread',
            createdAt: DateTime(2026),
          ),
        );
        runtime.seedThreadHistory(key, ThreadHistory(messages: const []));
        final sent = answerRuns(
          (runId, index, token) => index == 0
              ? Stream.error(
                  const PermissionDeniedException(
                    message: 'HTTP 403: Forbidden',
                    statusCode: 403,
                  ),
                )
              : answered(runId, index, token),
        );

        final first = await runtime.spawn(
          roomId: _roomId,
          prompt: [const TextPart('First')],
        );
        await first.result;
        await send('Again');

        expect(runIds(sent), ['run-made-with-thread', 'run-made-with-thread']);
      });
    });

    test('sends initial AG-UI state from createThread to backend', () async {
      final initialState = <String, dynamic>{
        'rag': <String, dynamic>{
          'citation_index': <String, dynamic>{},
          'citations': <dynamic>[],
        },
      };
      when(
        () => api.createThread(any()),
      ).thenAnswer(
        (_) async => (_threadInfo(), initialState),
      );
      stubCreateRun();
      stubDeleteThread();

      SimpleRunAgentInput? capturedInput;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((invocation) {
        capturedInput =
            invocation.positionalArguments[1] as SimpleRunAgentInput;
        return _wrap(Stream.fromIterable(_happyPathEvents()));
      });

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Hello')],
      );
      await session.result;

      expect(capturedInput, isNotNull);
      expect(capturedInput!.state, equals(initialState));
    });

    test('seedThreadState makes initial state available for spawn', () async {
      final initialState = <String, dynamic>{
        'rag': <String, dynamic>{
          'citation_index': <String, dynamic>{},
          'citations': <dynamic>[],
        },
      };
      runtime.seedThreadState(
        (serverId: 'default', roomId: _roomId, threadId: _threadId),
        initialState,
      );

      stubCreateRun();
      stubDeleteThread();

      SimpleRunAgentInput? capturedInput;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((invocation) {
        capturedInput =
            invocation.positionalArguments[1] as SimpleRunAgentInput;
        return _wrap(Stream.fromIterable(_happyPathEvents()));
      });

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Hello')],
        threadId: _threadId,
      );
      await session.result;

      expect(capturedInput, isNotNull);
      expect(capturedInput!.state, equals(initialState));
    });

    test('session appears in activeSessions', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

      expect(runtime.activeSessions, contains(session));

      controller.add(RunStartedEvent(threadId: _threadId, runId: _runId));
      await Future<void>.delayed(Duration.zero);

      await controller.close();
      // The stream closes without a terminal event, so the session completes.
      await session.result;
    });

    test('spawn passes stateOverlay to backend via state merge', () async {
      // createThread returns server-side initial state (e.g. citations)
      final serverState = <String, dynamic>{
        'rag': <String, dynamic>{
          'citation_index': <String, dynamic>{},
          'citations': <dynamic>[],
        },
      };
      when(
        () => api.createThread(any()),
      ).thenAnswer(
        (_) async => (_threadInfo(), serverState),
      );
      stubCreateRun();
      stubDeleteThread();

      SimpleRunAgentInput? capturedInput;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((invocation) {
        capturedInput =
            invocation.positionalArguments[1] as SimpleRunAgentInput;
        return _wrap(Stream.fromIterable(_happyPathEvents()));
      });

      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Hello')],
        stateOverlay: {
          'rag': <String, dynamic>{
            'document_filter': "id = 'abc-123'",
          },
        },
      );
      await session.result;

      expect(capturedInput, isNotNull);
      // stateOverlay should be merged with server state:
      // server's citation_index/citations preserved, client's document_filter added
      expect(
        capturedInput!.state,
        equals(<String, dynamic>{
          'rag': <String, dynamic>{
            'citation_index': <String, dynamic>{},
            'citations': <dynamic>[],
            'document_filter': "id = 'abc-123'",
          },
        }),
      );
    });
  });

  group('getSession', () {
    test('finds session by ThreadKey', () async {
      stubCreateThread();
      stubCreateRun();
      stubDeleteThread();
      final controller = StreamController<BaseEvent>();
      stubRunAgent(stream: controller.stream);

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

      final found = runtime.getSession(session.threadKey);
      expect(found, equals(session));

      controller.add(RunStartedEvent(threadId: _threadId, runId: _runId));
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

      await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Hello')],
        autoDispose: true,
      );

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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

      // Signal and getter agree after spawn
      expect(runtime.sessions.value, contains(session));
      expect(runtime.sessions.value, equals(runtime.activeSessions));

      controller.add(RunStartedEvent(threadId: _threadId, runId: _runId));
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

      final s1 =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);
      final s2 =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);

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

      final s1 =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);
      final s2 =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);

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
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount == 1
            ? _wrap(controllerA.stream)
            : _wrap(controllerB.stream);
      });

      final sessionA =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);
      final sessionB =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);

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

      await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);
      expect(runtime.pendingSpawnCount, 0);

      final spawnFuture =
          runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);
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

      await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);
      expect(runtime.pendingSpawnCount, 0);

      // Second spawn should queue, not throw.
      final spawnFuture =
          runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);
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

      await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);

      // Queue a second spawn and immediately attach an error handler
      // so the test zone doesn't see an unhandled rejection.
      Object? caught;
      final spawnFuture =
          runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);
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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Root')]);

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
      final root = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Root')]);
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

      final parent = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Parent')]);
      expect(parent.depth, 0);

      expect(
        () => runtime.spawn(
          roomId: _roomId,
          prompt: [const TextPart('Child')],
          parent: parent,
        ),
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

      final parent = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Parent')]);

      // Should not throw even with a parent at depth 0
      final child = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Child')],
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
        ..add(RunStartedEvent(threadId: _threadId, runId: _runId));
      stubRunAgent(stream: controller.stream);

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Slow')]);

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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Fast')]);

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
        ..add(RunStartedEvent(threadId: _threadId, runId: _runId));
      stubRunAgent(stream: controller.stream);

      final parent = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Parent')]);
      await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Child')],
        parent: parent,
      );

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
        prompt: [const TextPart('Hello')],
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
        prompt: [const TextPart('Hello')],
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

      final s1 =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]);
      final s2 =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]);

      controller.add(RunStartedEvent(threadId: _threadId, runId: _runId));
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
        () => runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hello')]),
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

      await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('A')],
        ephemeral: true,
      );
      controller.add(RunStartedEvent(threadId: _threadId, runId: _runId));
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
        () => runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hello')]),
        throwsA(isA<AuthException>()),
      );
    });

    test('resolver failure propagates', () async {
      runtime = createRuntime(
        resolver: (_) async => throw StateError('No tools'),
      );
      stubCreateThread();

      expect(
        () => runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hello')]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('failed run state capture', () {
    test('captures thread history from mid-stream failure', () async {
      stubCreateRun();
      stubDeleteThread();

      // First spawn: stream fails after delivering a message
      final controller1 = StreamController<BaseEvent>();
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) => _wrap(controller1.stream));

      final s1 = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Hello')],
        threadId: 'thread-fail',
      );

      // Deliver partial events then error
      controller1
        ..add(
          RunStartedEvent(
            threadId: 'thread-fail',
            runId: _runId,
          ),
        )
        ..add(const TextMessageStartEvent(messageId: 'msg-1'))
        ..add(
          const TextMessageContentEvent(
            messageId: 'msg-1',
            delta: 'Partial',
          ),
        )
        ..add(const TextMessageEndEvent(messageId: 'msg-1'))
        ..addError(Exception('network lost'));
      await s1.result;

      // Wait for _captureThreadHistory to run
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Second spawn on same thread: should include prior messages
      SimpleRunAgentInput? capturedInput;
      when(
        () => agUiStreamClient.runAgent(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((invocation) {
        capturedInput =
            invocation.positionalArguments[1] as SimpleRunAgentInput;
        return _wrap(
          Stream<BaseEvent>.fromIterable([
            RunStartedEvent(
              threadId: 'thread-fail',
              runId: 'run-2',
            ),
            const RunFinishedEvent(
              threadId: 'thread-fail',
              runId: 'run-2',
            ),
          ]),
        );
      });

      final s2 = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Retry')],
        threadId: 'thread-fail',
      );
      await s2.result;

      // The failed run keeps what it was sent, its user message, but not the
      // text it streamed before failing.
      expect(
        capturedInput!.messages!.map((m) => (m as UserMessage).content),
        ['Hello', 'Retry'],
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
        () => runtime.spawn(
          roomId: _roomId,
          prompt: [const TextPart('Hello')],
          ephemeral: true,
        ),
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
        () => runtime.spawn(roomId: _roomId, prompt: [const TextPart('A')]),
        throwsA(isA<StateError>()),
      );

      // Second spawn should NOT hit concurrency limit — slot was freed.
      // It will still fail from the throwing extension, but the error
      // must be the extension error, not a concurrency guard error.
      await expectLater(
        () => runtime.spawn(roomId: _roomId, prompt: [const TextPart('B')]),
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
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        return callCount == 1
            ? _wrap(Stream.fromIterable(_toolCallEvents()))
            : _wrap(Stream.fromIterable(_resumeTextEvents()));
      });

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Weather?')]);
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
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
        ),
      ).thenAnswer((_) {
        callCount++;
        // First call: tool yield; second call: resume with text
        return callCount == 1
            ? _wrap(
                Stream<BaseEvent>.fromIterable([
                  RunStartedEvent(threadId: _threadId, runId: _runId),
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
                ]),
              )
            : _wrap(Stream.fromIterable(_resumeTextEvents()));
      });

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Run code')]);
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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);
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
        () => runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hello')]),
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

      await runtime.spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);

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
      final s1 = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);
      await s1.result;

      // Stub a second run on the same thread.
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));
      stubCreateRun();

      // Turn 2 — same thread, runtime should auto-inject history.
      final s2 = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Follow up')],
        threadId: s1.threadKey.threadId,
      );
      await s2.result;

      // Capture all runAgent calls.
      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
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

      final session = await runtime
          .spawn(roomId: _roomId, prompt: [const TextPart('Hello')]);
      await session.result;

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
        prompt: [const TextPart('Ephemeral')],
        ephemeral: true,
      );
      await s1.result;

      // Stub second run.
      stubRunAgent(stream: Stream.fromIterable(_happyPathEvents()));
      stubCreateRun();

      final s2 = await runtime.spawn(
        roomId: _roomId,
        prompt: [const TextPart('Another')],
        threadId: s1.threadKey.threadId,
      );
      await s2.result;

      final captured = verify(
        () => agUiStreamClient.runAgent(
          any(),
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          resumePolicy: any(named: 'resumePolicy'),
          onReconnectStatus: any(named: 'onReconnectStatus'),
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

      final session =
          await runtime.spawn(roomId: _roomId, prompt: [const TextPart('hi')]);

      expect(session.threadKey.serverId, equals('prod'));

      final result = await session.result;
      expect(result, isA<AgentSuccess>());
    });
  });
}
