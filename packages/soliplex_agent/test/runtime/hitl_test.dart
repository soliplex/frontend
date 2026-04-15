import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mocks / fixtures (minimal — only what the concurrent-approval test needs)
// ---------------------------------------------------------------------------

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class _MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

const ({String roomId, String serverId, String threadId}) _key = (
  serverId: 'srv',
  roomId: 'room',
  threadId: 'thread',
);
const _runId = 'run-1';

RunInfo _runInfo() =>
    RunInfo(id: _runId, threadId: 'thread', createdAt: DateTime(2026));

List<BaseEvent> _approvalTextEvents() => const [
      RunStartedEvent(threadId: 'thread', runId: _runId),
      TextMessageStartEvent(messageId: 'msg-done'),
      TextMessageContentEvent(messageId: 'msg-done', delta: 'Done'),
      TextMessageEndEvent(messageId: 'msg-done'),
      RunFinishedEvent(threadId: 'thread', runId: _runId),
    ];

AgentSession _makeSession(
  _MockSoliplexApi api,
  _MockAgUiStreamClient stream,
  _MockLogger logger,
  ToolRegistry registry,
) {
  final orchestrator = RunOrchestrator(
    llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: stream),
    toolRegistry: registry,
    logger: logger,
  );
  return AgentSession(
    threadKey: _key,
    ephemeral: false,
    depth: 0,
    runtime: _MockAgentRuntime(),
    orchestrator: orchestrator,
    toolRegistry: registry,
    logger: logger,
  );
}

class _MockAgentRuntime extends Mock implements AgentRuntime {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });
  // ── requiresApproval flag ─────────────────────────────────────────────────

  group('ClientTool.requiresApproval', () {
    test('defaults to false', () {
      final tool = ClientTool(
        definition: const Tool(name: 'render_widget', description: ''),
        executor: (_, __) async => '',
      );
      expect(tool.requiresApproval, isFalse);
    });

    test('can be set to true', () {
      final tool = ClientTool(
        definition: const Tool(name: 'execute_python', description: ''),
        executor: (_, __) async => '',
        requiresApproval: true,
      );
      expect(tool.requiresApproval, isTrue);
    });

    test('ClientTool.simple defaults to false', () {
      final tool = ClientTool.simple(
        name: 'get_location',
        description: 'Returns GPS coordinates.',
        executor: (_, __) async => '{"lat": 37.7749, "lng": -122.4194}',
      );
      expect(tool.requiresApproval, isFalse);
    });
  });

  // ── Approval categories ───────────────────────────────────────────────────
  //
  // Three tool categories with distinct approval semantics:
  //
  // 1. execute_python — requiresApproval: true
  //    The agent framework suspends execution and emits PendingApprovalRequest
  //    on AgentSession.pendingApproval. No code runs until the UI calls
  //    session.approveToolCall() or session.denyToolCall().
  //
  // 2. get_location — requiresApproval: false
  //    The agent framework skips its gate entirely. The OS (iOS/macOS/Web)
  //    shows its own "Allow location access?" dialog inside the executor.
  //    The agent sees the result (or a permission error); it never sees the
  //    dialog.
  //
  // 3. render_widget — requiresApproval: false
  //    Fire-and-forget. No approval at any level. The executor emits a signal
  //    for the Flutter layer and returns "" immediately. The agent continues.

  group('approval categories', () {
    test(
      'execute_python: requiresApproval true — agent gate fires',
      () {
        final tool = ClientTool(
          definition: const Tool(name: 'execute_python', description: ''),
          requiresApproval: true,
          executor: (_, __) async => '42',
        );
        expect(
          tool.requiresApproval,
          isTrue,
          reason: 'execute_python suspends via AgentSession.pendingApproval '
              'until session.approveToolCall() is called.',
        );
      },
    );

    test(
      'get_location: requiresApproval false — OS handles consent',
      () {
        final tool = ClientTool.simple(
          name: 'get_location',
          description: 'Returns GPS coordinates.',
          // requiresApproval defaults to false —
          // OS dialog fires inside executor
          executor: (_, __) async => '{"lat": 37.7749, "lng": -122.4194}',
        );
        expect(
          tool.requiresApproval,
          isFalse,
          reason: 'get_location skips the agent gate. The OS shows its own '
              '"Allow location?" dialog inside the executor. The agent '
              'framework is not involved.',
        );
      },
    );

    test(
      'render_widget: requiresApproval false — no approval at any level',
      () {
        final tool = ClientTool.simple(
          name: 'render_widget',
          description: 'Renders a UI widget.',
          // requiresApproval defaults to false — fire-and-forget
          executor: (_, __) async => '',
        );
        expect(
          tool.requiresApproval,
          isFalse,
          reason: 'render_widget is fire-and-forget. The agent receives "" '
              'and continues. No gate, no OS dialog.',
        );
      },
    );
  });

  // ── PendingApprovalRequest ────────────────────────────────────────────────

  group('PendingApprovalRequest', () {
    test('carries toolCallId, toolName, and arguments', () {
      const req = PendingApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'execute_python',
        arguments: {'code': 'print("hello")'},
      );
      expect(req.toolCallId, equals('tc-1'));
      expect(req.toolName, equals('execute_python'));
      expect(req.arguments, equals({'code': 'print("hello")'}));
    });
  });

  // ── platformConsentNote ───────────────────────────────────────────────────
  //
  // Non-blocking consent notices for platform-conditional permission dialogs
  // (e.g. clipboard read on web triggers a browser prompt; on native it does
  // not). The callback returns null when no notice is needed so the session
  // emits nothing.

  group('ClientTool.platformConsentNote', () {
    test('defaults to null', () {
      final tool = ClientTool.simple(
        name: 'get_device_info',
        description: 'Returns device info.',
        executor: (_, __) async => '{}',
      );
      expect(tool.platformConsentNote, isNull);
    });

    test('can be set and returns the expected string', () {
      const note = 'Clipboard read requires browser permission on web.';
      final tool = ClientTool.simple(
        name: 'get_clipboard',
        description: 'Reads clipboard text.',
        executor: (_, __) async => '',
        platformConsentNote: () => note,
      );
      expect(tool.platformConsentNote?.call(), equals(note));
    });

    test('callback may return null to suppress the notice', () {
      final tool = ClientTool.simple(
        name: 'get_clipboard',
        description: 'Reads clipboard text.',
        executor: (_, __) async => '',
        // Simulates native path: no browser permission needed.
        platformConsentNote: () => null,
      );
      expect(tool.platformConsentNote?.call(), isNull);
    });
  });

  // ── PlatformConsentNotice event ───────────────────────────────────────────

  group('PlatformConsentNotice', () {
    test('carries toolCallId, toolName, and note', () {
      const event = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'Clipboard read requires browser permission on web.',
      );
      expect(event.toolCallId, equals('tc-2'));
      expect(event.toolName, equals('get_clipboard'));
      expect(
        event.note,
        equals('Clipboard read requires browser permission on web.'),
      );
    });

    test('equality compares all fields', () {
      const a = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'note',
      );
      const b = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'note',
      );
      const c = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'different note',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // ── Concurrent approval serialisation ────────────────────────────────────
  //
  // When the LLM returns N tool calls at once and all have
  // requiresApproval: true,
  // _executeAll must not run them concurrently.  Concurrent execution causes
  // _pendingApprovalSignal to be overwritten N times; only the last survives in
  // the UI and the first N-1 deadlock silently.
  //
  // The fix serialises approval-required tools: tc-2 is not started until tc-1
  // has been approved/denied, so the signal never has more than one live request.

  group('concurrent approval serialisation', () {
    late _MockSoliplexApi api;
    late _MockAgUiStreamClient agUiStream;
    late _MockLogger logger;

    setUp(() {
      api = _MockSoliplexApi();
      agUiStream = _MockAgUiStreamClient();
      logger = _MockLogger();
    });

    test(
      'three concurrent approval-required tools are shown one at a time',
      () async {
        // LLM returns three execute_python calls in a single turn.
        const firstTurn = [
          RunStartedEvent(threadId: 'thread', runId: _runId),
          ToolCallStartEvent(
              toolCallId: 'tc-1', toolCallName: 'execute_python',),
          ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"code":"1+1"}'),
          ToolCallEndEvent(toolCallId: 'tc-1'),
          ToolCallStartEvent(
              toolCallId: 'tc-2', toolCallName: 'execute_python',),
          ToolCallArgsEvent(toolCallId: 'tc-2', delta: '{"code":"2+2"}'),
          ToolCallEndEvent(toolCallId: 'tc-2'),
          ToolCallStartEvent(
              toolCallId: 'tc-3', toolCallName: 'execute_python',),
          ToolCallArgsEvent(toolCallId: 'tc-3', delta: '{"code":"3+3"}'),
          ToolCallEndEvent(toolCallId: 'tc-3'),
          RunFinishedEvent(threadId: 'thread', runId: _runId),
        ];

        when(() => api.createRun(any(), any()))
            .thenAnswer((_) async => _runInfo());

        var turn = 0;
        when(
          () => agUiStream.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) {
          turn++;
          return turn == 1
              ? Stream.fromIterable(firstTurn)
              : Stream.fromIterable(_approvalTextEvents());
        });

        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(name: 'execute_python', description: ''),
            executor: (_, __) async => 'ok',
            requiresApproval: true,
          ),
        );

        final session = _makeSession(api, agUiStream, logger, registry);
        addTearDown(session.dispose);

        // Track the order in which approval requests appear in the signal.
        final approvedIds = <String>[];
        final unsub = session.pendingApproval.subscribe((req) {
          if (req != null) {
            approvedIds.add(req.toolCallId);
            // Approve each request as soon as it appears, driving the queue.
            unawaited(
              Future.microtask(
                () => session.approveToolCall(req.toolCallId),
              ),
            );
          }
        });
        addTearDown(unsub);

        unawaited(session.start(userMessage: 'sort'));
        final result = await session.result.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'Session did not complete — '
            'likely a deadlock in the approval queue',
          ),
        );

        expect(result, isA<AgentSuccess>());
        // All three were shown, in order, one at a time.
        expect(approvedIds, equals(['tc-1', 'tc-2', 'tc-3']));
      },
    );
  });
}
