import 'dart:async';
import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

class MockSoliplexHttpClient extends Mock implements SoliplexHttpClient {}

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockLogger extends Mock implements Logger {}

/// A provider whose event stream is an `async*` generator parked inside
/// `await for` — the shape `AgUiStreamClient.runAgent` has, and the one that
/// reports an unwinding error through `StreamSubscription.cancel()`.
class _ParkedProvider implements AgentLlmProvider {
  _ParkedProvider(this.inner, {this.startGate});

  final StreamController<DecodeOutcome> inner;

  /// Holds `startRun` open so a cancel can land while the orchestrator is
  /// awaiting it, which is the window `_initializeStream` drains from.
  final Future<void>? startGate;

  @override
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    if (startGate != null) await startGate;
    return LlmRunHandle(runId: 'run-1', events: _events());
  }

  Stream<DecodeOutcome> _events() async* {
    await for (final outcome in inner.stream) {
      yield outcome;
    }
  }
}

const ThreadKey _key = (
  serverId: 'srv-1',
  roomId: 'room-1',
  threadId: 'thread-1',
);

String _sse(Map<String, dynamic> event) => 'data: ${jsonEncode(event)}\n\n';

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  test(
    'cancelling a streaming run does not leak the injected cancel as an '
    'unhandled error',
    () async {
      final httpClient = MockSoliplexHttpClient();
      final api = MockSoliplexApi();
      final logger = MockLogger();
      final body = StreamController<List<int>>();
      addTearDown(body.close);

      for (final stub in [
        () => logger.warning(
              any(),
              error: any(named: 'error'),
              stackTrace: any(named: 'stackTrace'),
              attributes: any(named: 'attributes'),
            ),
        () => logger.info(
              any(),
              error: any(named: 'error'),
              stackTrace: any(named: 'stackTrace'),
              attributes: any(named: 'attributes'),
            ),
        () => logger.error(
              any(),
              error: any(named: 'error'),
              stackTrace: any(named: 'stackTrace'),
              attributes: any(named: 'attributes'),
            ),
        () => logger.debug(
              any(),
              error: any(named: 'error'),
              stackTrace: any(named: 'stackTrace'),
              attributes: any(named: 'attributes'),
            ),
      ]) {
        when(stub).thenReturn(null);
      }

      when(() => api.createRun(any(), any())).thenAnswer(
        (_) async => RunInfo(
          id: 'run-1',
          threadId: _key.threadId,
          createdAt: DateTime(2026),
        ),
      );
      when(
        () => httpClient.requestStream(
          any(),
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => StreamedHttpResponse(
          statusCode: 200,
          headers: const {'content-type': 'text/event-stream'},
          body: body.stream,
        ),
      );

      final orchestrator = RunOrchestrator(
        llmProvider: AgUiLlmProvider(
          api: api,
          agUiStreamClient: AgUiStreamClient(
            httpTransport: HttpTransport(client: httpClient),
            urlBuilder: UrlBuilder('https://example.com'),
          ),
        ),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      addTearDown(orchestrator.dispose);

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final run = orchestrator.runToCompletion(
            key: _key,
            userMessage: [const TextPart('hi')],
            toolExecutor: (_) async => [],
          );

          // Park the AG-UI generator mid-stream so its teardown has to
          // unwind an `await for`.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          body.add(
            utf8.encode(
              _sse({
                'type': 'RUN_STARTED',
                'threadId': _key.threadId,
                'runId': 'run-1',
              }),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(orchestrator.currentState, isA<RunningState>());

          orchestrator.cancelRun();

          expect(await run, isA<CancelledState>());
          await Future<void>.delayed(const Duration(milliseconds: 150));
        },
        (error, _) => unhandled.add(error),
      );

      expect(
        unhandled,
        isEmpty,
        reason: 'the transport injects CancelledException into the body '
            'stream as the run is cancelled; tearing down the subscription '
            'must absorb it rather than let it reach the zone',
      );
      // Absorbed, not recorded: the cancellation tells no one anything the
      // caller who initiated it does not already know.
      verifyNever(
        () => logger.warning(
          any(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: any(named: 'attributes'),
        ),
      );
    },
  );

  test(
    'a non-cancel teardown failure is recorded rather than absorbed',
    () async {
      final logger = MockLogger();
      when(
        () => logger.warning(
          any(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: any(named: 'attributes'),
        ),
      ).thenReturn(null);

      final inner = StreamController<DecodeOutcome>();
      addTearDown(inner.close);
      final orchestrator = RunOrchestrator(
        llmProvider: _ParkedProvider(inner),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      addTearDown(orchestrator.dispose);

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final run = orchestrator.runToCompletion(
            key: _key,
            userMessage: [const TextPart('hi')],
            toolExecutor: (_) async => [],
          );
          await Future<void>.delayed(Duration.zero);
          inner.add(
            DecodedEvent(
              RunStartedEvent(threadId: _key.threadId, runId: 'run-1'),
              const {},
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(orchestrator.currentState, isA<RunningState>());

          // Scheduled before the cancel, so it is still undelivered when the
          // subscription is torn down and surfaces on the cancel future.
          inner.addError(StateError('teardown blew up'));
          orchestrator.cancelRun();

          expect(await run, isA<CancelledState>());
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
        (error, _) => unhandled.add(error),
      );

      expect(unhandled, isEmpty);

      // The record is the only trace this branch leaves, and it must carry a
      // description rather than the exception object.
      final logged = verify(
        () => logger.warning(
          captureAny(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: captureAny(named: 'attributes'),
        ),
      ).captured;
      expect(logged[0], 'SSE subscription teardown failed: cleanup');
      expect(logged[1], {'failure': 'StateError'});
    },
  );

  test(
    'disposing mid-run does not leak the teardown error either',
    () async {
      // `dispose()` reaches the same absorption as `cancelRun()`, through
      // `AgentSession.dispose()`.
      final logger = MockLogger();
      when(
        () => logger.warning(
          any(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: any(named: 'attributes'),
        ),
      ).thenReturn(null);

      final inner = StreamController<DecodeOutcome>();
      addTearDown(inner.close);
      final orchestrator = RunOrchestrator(
        llmProvider: _ParkedProvider(inner),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final run = orchestrator.runToCompletion(
            key: _key,
            userMessage: [const TextPart('hi')],
            toolExecutor: (_) async => [],
          );
          await Future<void>.delayed(Duration.zero);
          inner.add(
            DecodedEvent(
              RunStartedEvent(threadId: _key.threadId, runId: 'run-1'),
              const {},
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(orchestrator.currentState, isA<RunningState>());

          inner.addError(StateError('teardown blew up'));
          orchestrator.dispose();

          expect(await run, isA<CancelledState>());
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
        (error, _) => unhandled.add(error),
      );

      expect(unhandled, isEmpty);
      final logged = verify(
        () => logger.warning(
          captureAny(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: captureAny(named: 'attributes'),
        ),
      ).captured;
      expect(logged[0], 'SSE subscription teardown failed: dispose');
      expect(logged[1], {'failure': 'StateError'});
    },
  );

  test(
    'draining a stream we never owned records its teardown failure',
    () async {
      // Cancel landing between `startRun` returning and `_subscribeToStream`:
      // the orchestrator owns an event stream it will never subscribe to, and
      // drains it to release the socket.
      final logger = MockLogger();
      when(
        () => logger.warning(
          any(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: any(named: 'attributes'),
        ),
      ).thenReturn(null);

      final gate = Completer<void>();
      final inner = StreamController<DecodeOutcome>();
      addTearDown(inner.close);
      final orchestrator = RunOrchestrator(
        llmProvider: _ParkedProvider(inner, startGate: gate.future),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );
      addTearDown(orchestrator.dispose);

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final run = orchestrator.runToCompletion(
            key: _key,
            userMessage: [const TextPart('hi')],
            toolExecutor: (_) async => [],
          );
          await Future<void>.delayed(Duration.zero);

          orchestrator.cancelRun();
          inner.addError(StateError('drain blew up'));
          gate.complete();

          expect(await run, isA<CancelledState>());
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
        (error, _) => unhandled.add(error),
      );

      expect(unhandled, isEmpty);
      final logged = verify(
        () => logger.warning(
          captureAny(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: captureAny(named: 'attributes'),
        ),
      ).captured;
      expect(
        logged[0],
        'SSE subscription teardown failed: initialize drain (cancelled)',
      );
      expect(logged[1], {'failure': 'StateError'});
    },
  );

  test(
    'disposing during startRun drains the stream it never owned',
    () async {
      // The sibling of the cancelled drain: dispose lands in the same
      // post-`startRun` window and takes the other branch.
      final logger = MockLogger();
      when(
        () => logger.warning(
          any(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: any(named: 'attributes'),
        ),
      ).thenReturn(null);

      final gate = Completer<void>();
      final inner = StreamController<DecodeOutcome>();
      addTearDown(inner.close);
      final orchestrator = RunOrchestrator(
        llmProvider: _ParkedProvider(inner, startGate: gate.future),
        toolRegistry: const ToolRegistry(),
        logger: logger,
      );

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final run = orchestrator.runToCompletion(
            key: _key,
            userMessage: [const TextPart('hi')],
            toolExecutor: (_) async => [],
          );
          await Future<void>.delayed(Duration.zero);

          orchestrator.dispose();
          inner.addError(StateError('drain blew up'));
          gate.complete();

          expect(await run, isA<CancelledState>());
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
        (error, _) => unhandled.add(error),
      );

      expect(unhandled, isEmpty);
      final logged = verify(
        () => logger.warning(
          captureAny(),
          error: any(named: 'error'),
          stackTrace: any(named: 'stackTrace'),
          attributes: captureAny(named: 'attributes'),
        ),
      ).captured;
      expect(
        logged[0],
        'SSE subscription teardown failed: initialize drain (disposed)',
      );
      expect(logged[1], {'failure': 'StateError'});
    },
  );
}
