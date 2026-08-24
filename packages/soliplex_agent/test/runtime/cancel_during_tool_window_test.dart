import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

// Guards the session cancellation signal against the lifetime it must not
// be given. `RunOrchestrator`'s token is scoped to one HTTP request and is
// absent for the whole tool-execution window (`_handleRunFinished` clears it
// before emitting `ToolYieldingState`) and at `onAttach` time. Sourcing
// `AgentSession.cancelToken` from it leaves tools and extensions holding a
// token that a later cancel never reaches.

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class _MockLogger extends Mock implements Logger {}

class _MockAgentRuntime extends Mock implements AgentRuntime {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

/// Records whether the extension was asked, so a test can assert that a
/// cancelled session never surfaces an approval at all.
class _RecordingApprovalExtension extends ToolApprovalExtension {
  int requestCount = 0;

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
    return true;
  }
}

/// Holds `attachAll` open so a cancel can land mid-attach.
class _GatedExtension extends SessionExtension {
  _GatedExtension(this.gate);

  final Future<void> gate;

  @override
  String get namespace => 'gated';

  @override
  Future<void> onAttach(AgentSession session) => gate;

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() {}
}

/// The same shape as `HumanApprovalExtension`: one `whenCancelled`
/// subscription taken at attach time, a completer per request, and a deny on
/// either cancel or dispose. It omits the parts that do not bear on cancel —
/// denying a superseded request, and the state signal.
class _PendingApprovalExtension extends ToolApprovalExtension {
  Completer<bool>? _pending;
  bool get isPending => !(_pending?.isCompleted ?? true);

  @override
  Future<void> onAttach(AgentSession session) async {
    unawaited(
      session.cancelToken.whenCancelled.then((_) => _deny()),
    );
  }

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() => _deny();

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) {
    final completer = Completer<bool>();
    _pending = completer;
    return completer.future;
  }

  void _deny() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(false);
  }
}

const ThreadKey _key = (
  serverId: 'srv-1',
  roomId: 'room-1',
  threadId: 'thread-1',
);

const _runId = 'run-abc';

RunInfo _runInfo() =>
    RunInfo(id: _runId, threadId: _key.threadId, createdAt: DateTime(2026));

/// A run that ends on a pending tool call, which is what parks the
/// orchestrator in `ToolYieldingState` and runs the tool executor.
List<BaseEvent> _toolCallEvents() => [
      RunStartedEvent(threadId: _key.threadId, runId: _runId),
      const ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather'),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"city":"NYC"}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      RunFinishedEvent(threadId: _key.threadId, runId: _runId),
    ];

/// Marks every pending call executed so the orchestrator resumes rather
/// than failing the resume on an unfinished tool call.
List<ToolCallInfo> _completed(List<ToolCallInfo> pending) => pending
    .map(
      (tc) => tc.copyWith(status: ToolCallStatus.completed, result: 'sunny'),
    )
    .toList();

/// The resume segment: plain text, no pending tool call, so the run ends.
List<BaseEvent> _replyEvents() => [
      RunStartedEvent(threadId: _key.threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Sunny'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      RunFinishedEvent(threadId: _key.threadId, runId: _runId),
    ];

ToolRegistry _registry() => const ToolRegistry().register(
      ClientTool(
        definition: const Tool(name: 'weather', description: 'A test tool'),
        executor: (_, __) async => 'result',
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late _MockSoliplexApi api;
  late _MockAgUiStreamClient agUiStreamClient;
  late _MockLogger logger;
  late RunOrchestrator orchestrator;
  late int segment;

  setUp(() {
    segment = 0;
    api = _MockSoliplexApi();
    agUiStreamClient = _MockAgUiStreamClient();
    logger = _MockLogger();
    orchestrator = RunOrchestrator(
      llmProvider:
          AgUiLlmProvider(api: api, agUiStreamClient: agUiStreamClient),
      toolRegistry: _registry(),
      logger: logger,
    );
    when(() => api.createRun(any(), any())).thenAnswer((_) async => _runInfo());
    when(
      () => agUiStreamClient.runAgent(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((_) {
      // First segment yields a pending tool call (which opens the tool
      // window); the resume segment answers with text so the run reaches
      // CompletedState instead of looping to the depth limit.
      final events = segment++ == 0 ? _toolCallEvents() : _replyEvents();
      return Stream.fromIterable(events)
          .map<DecodeOutcome>((e) => DecodedEvent(e, const {}));
    });
  });

  tearDown(() {
    orchestrator.dispose();
  });

  /// Mirrors `AgentSession.start()`'s ordering: extensions are attached
  /// before the run begins, which is the window the defect lives in.
  Future<AgentSession> buildSession(List<SessionExtension> extensions) async {
    final coordinator = SessionCoordinator(extensions, logger: logger);
    final session = AgentSession(
      threadKey: _key,
      ephemeral: false,
      depth: 0,
      runtime: _MockAgentRuntime(),
      orchestrator: orchestrator,
      toolRegistry: _registry(),
      coordinator: coordinator,
      logger: logger,
    );
    await coordinator.attachAll(session);
    return session;
  }

  test(
    'a cancelled session does not surface an approval request',
    () async {
      final ext = _RecordingApprovalExtension();
      final session = await buildSession([ext]);
      addTearDown(session.dispose);

      final result = await orchestrator.runToCompletion(
        key: _key,
        userMessage: [const TextPart('Weather?')],
        toolExecutor: (pending) async {
          session.cancel();
          // A tool that reaches its approval point after the user pressed
          // Stop. `AgentSession.requestApproval`'s cancel short-circuit
          // exists precisely to deny this without showing a dialog.
          await session.requestApproval(
            toolCallId: 'tc-1',
            toolName: 'weather',
            arguments: const {},
            rationale: 'r',
          );
          return pending;
        },
      );

      expect(result, isA<CancelledState>());
      expect(
        ext.requestCount,
        0,
        reason: 'a cancelled session must not raise an approval dialog',
      );
    },
  );

  test(
    'cancelling lets the run finish while an approval is pending',
    () async {
      final ext = _PendingApprovalExtension();
      final session = await buildSession([ext]);
      // Registered rather than called inline: disposing before the check
      // would resolve the approval and mask a hang.
      addTearDown(session.dispose);

      final run = orchestrator.runToCompletion(
        key: _key,
        userMessage: [const TextPart('Weather?')],
        toolExecutor: (pending) async {
          final approval = session.requestApproval(
            toolCallId: 'tc-1',
            toolName: 'weather',
            arguments: const {},
            rationale: 'r',
          );
          session.cancel();
          await approval;
          return _completed(pending);
        },
      );

      // Completing at all is the assertion: a cancelled run must not park
      // forever on an approval that only its cancel listener can resolve.
      // `completes` surfaces a real throw instead of reporting it as a hang.
      await expectLater(run.timeout(const Duration(seconds: 2)), completes);
    },
  );

  test(
    'a session cancelled while attaching never starts a run',
    () async {
      // `AgentRuntime.spawn` registers a child with its parent before
      // awaiting `start`, so a parent cancel can land inside `onAttach`.
      final attaching = Completer<void>();
      final ext = _GatedExtension(attaching.future);
      final session = AgentSession(
        threadKey: _key,
        ephemeral: false,
        depth: 0,
        runtime: _MockAgentRuntime(),
        orchestrator: orchestrator,
        toolRegistry: _registry(),
        coordinator: SessionCoordinator([ext], logger: logger),
        logger: logger,
      );
      addTearDown(session.dispose);

      final started = session.start(userMessage: [const TextPart('hi')]);
      session.cancel();
      attaching.complete();
      await started;
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.currentState, isA<IdleState>());
      verifyNever(() => api.createRun(any(), any()));
      // The runtime awaits this before disposing the session and draining
      // the spawn queue, so it has to settle.
      expect(
        await session.result.timeout(const Duration(seconds: 2)),
        isA<AgentFailure>().having(
          (f) => f.reason,
          'reason',
          FailureReason.cancelled,
        ),
      );
    },
  );

  test(
    'a session disposed while attaching settles without throwing',
    () async {
      // `dispose()` cancels the token as well, and disposes the signals
      // `_completeWith` writes — so the cancelled-during-attach path has to
      // recognise that dispose already settled the result.
      final attaching = Completer<void>();
      final ext = _GatedExtension(attaching.future);
      final session = AgentSession(
        threadKey: _key,
        ephemeral: false,
        depth: 0,
        runtime: _MockAgentRuntime(),
        orchestrator: orchestrator,
        toolRegistry: _registry(),
        coordinator: SessionCoordinator([ext], logger: logger),
        logger: logger,
      );

      final started = session.start(userMessage: [const TextPart('hi')]);
      session.dispose();
      attaching.complete();

      await expectLater(started, completes);
      verifyNever(() => api.createRun(any(), any()));
      expect(await session.result, isA<AgentFailure>());
    },
  );
}
