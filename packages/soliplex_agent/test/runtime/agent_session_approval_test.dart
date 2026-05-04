import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class _MockLogger extends Mock implements Logger {}

class _MockAgentRuntime extends Mock implements AgentRuntime {}

class _FakeApprovalExtension extends ToolApprovalExtension {
  _FakeApprovalExtension({required this.decision});

  final bool decision;
  int requestCount = 0;
  Map<String, dynamic>? lastArguments;

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() {}

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async {
    requestCount++;
    lastArguments = arguments;
    return decision;
  }
}

const ThreadKey _key = (
  serverId: 'srv-1',
  roomId: 'room-1',
  threadId: 'thread-1',
);

AgentSession _createSession({
  required _MockLogger logger,
  List<SessionExtension> extensions = const [],
}) {
  final api = _MockSoliplexApi();
  final agUi = _MockAgUiStreamClient();
  final orchestrator = RunOrchestrator(
    llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: agUi),
    toolRegistry: const ToolRegistry(),
    logger: logger,
  );
  return AgentSession(
    threadKey: _key,
    ephemeral: false,
    depth: 0,
    runtime: _MockAgentRuntime(),
    orchestrator: orchestrator,
    toolRegistry: const ToolRegistry(),
    coordinator: SessionCoordinator(extensions, logger: logger),
    logger: logger,
  );
}

void main() {
  late _MockLogger logger;

  setUp(() {
    logger = _MockLogger();
  });

  group('AgentSession.requestApproval', () {
    test(
      'no ToolApprovalExtension registered → resolves false, warning logged, '
      'no AwaitingApproval emitted',
      () async {
        final session = _createSession(logger: logger);
        addTearDown(session.dispose);

        var awaitingEmitted = false;
        final unsub = session.lastExecutionEvent.subscribe((event) {
          if (event is AwaitingApproval) awaitingEmitted = true;
        });
        addTearDown(unsub.call);

        final result = await session.requestApproval(
          toolCallId: 'tc-1',
          toolName: 'send_email',
          arguments: const {},
          rationale: 'r',
        );

        expect(result, isFalse);
        expect(awaitingEmitted, isFalse);
        verify(() => logger.warning(any())).called(greaterThanOrEqualTo(1));
      },
    );

    test('extension returns true → resolves true and AwaitingApproval emitted',
        () async {
      final ext = _FakeApprovalExtension(decision: true);
      final session = _createSession(logger: logger, extensions: [ext]);
      addTearDown(session.dispose);

      AwaitingApproval? emitted;
      final unsub = session.lastExecutionEvent.subscribe((event) {
        if (event is AwaitingApproval) emitted = event;
      });
      addTearDown(unsub.call);

      final result = await session.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {'to': 'a@b.c'},
        rationale: 'send a message',
      );

      expect(result, isTrue);
      expect(emitted, isNotNull);
      expect(emitted!.toolCallId, 'tc-1');
      expect(emitted!.toolName, 'send_email');
      expect(ext.requestCount, 1);
      expect(ext.lastArguments, equals({'to': 'a@b.c'}));
    });

    test('extension returns false → resolves false', () async {
      final ext = _FakeApprovalExtension(decision: false);
      final session = _createSession(logger: logger, extensions: [ext]);
      addTearDown(session.dispose);

      final result = await session.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );

      expect(result, isFalse);
    });

    // The cancelToken.isCancelled short-circuit at AgentSession.requestApproval
    // is only reachable mid-run (the orchestrator creates the token lazily in
    // _subscribeToStream). Exercising it requires a real run; the disposed-
    // session test below covers the equivalent deny-without-extension-call
    // semantics through the _disposed guard, which is the path actually taken
    // when AgentRuntime tears the session down.

    test(
      'session disposed → resolves false without touching extension',
      () async {
        final ext = _FakeApprovalExtension(decision: true);
        final session = _createSession(logger: logger, extensions: [ext])
          ..dispose();

        final result = await session.requestApproval(
          toolCallId: 'tc-1',
          toolName: 't',
          arguments: const {},
          rationale: 'r',
        );

        expect(result, isFalse);
        expect(ext.requestCount, 0);
        expect(session.cancelToken.isCancelled, isTrue);
      },
    );

    test('spawnChild on disposed session yields Future.error', () async {
      final session = _createSession(logger: logger)..dispose();

      // Future.error rather than sync-throw: a fire-and-forget caller or a
      // chained .catchError must see the error rather than have an uncaught
      // synchronous exception escape.
      await expectLater(
        session.spawnChild(prompt: 'hello'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
