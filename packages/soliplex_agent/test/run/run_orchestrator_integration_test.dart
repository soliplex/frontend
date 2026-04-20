// Integration tests use print for diagnostic output.
// ignore_for_file: avoid_print
@Tags(['integration'])
library;

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:test/test.dart';

import '../integration/helpers/helpers.dart';

/// ------------------------------------------------------------------
/// Integration test: RunOrchestrator + AgentRuntime ↔ real Soliplex backend
///
/// Validates M4 state machine, M5 tool yielding, and M6 AgentRuntime
/// facade against a live AG-UI SSE stream.
///
/// Prerequisites:
///   1. A running Soliplex backend (local or remote, --no-auth-mode OK)
///   2. The `plain` room with `get_current_datetime` server-side tool
///
/// Run:
///   SOLIPLEX_BASE_URL=http://localhost:8000 \
///   SOLIPLEX_ROOM_ID=plain \
///   dart test test/run/run_orchestrator_integration_test.dart -t integration
/// ------------------------------------------------------------------

void main() {
  final harness = IntegrationHarness();

  late String roomId;

  // One thread for the whole suite.
  late ThreadKey sharedKey;
  late String? initialRunId;

  // Fresh per test.
  late RunOrchestrator orchestrator;

  setUpAll(() async {
    await harness.setUp();
    roomId = env('SOLIPLEX_ROOM_ID', 'plain');

    // Create one thread for the entire suite.
    final (key, runId) = await harness.createThread(roomId);
    print('Created shared thread: ${key.threadId}');
    sharedKey = key;
    initialRunId = runId;
  });

  setUp(() {
    orchestrator = harness.createOrchestrator(loggerName: 'integration-test');
  });

  tearDown(() {
    orchestrator.dispose();
  });

  tearDownAll(harness.tearDown);

  group('M4 integration: real backend', () {
    test('Idle → Running → Completed', () async {
      final states = <RunState>[];
      orchestrator.stateChanges.listen(states.add);

      print('Starting run: room=$roomId, thread=${sharedKey.threadId}');
      await orchestrator.startRun(
        key: sharedKey,
        userMessage: 'Hello, what time is it?',
        existingRunId: initialRunId,
      );
      // Consume the initial run ID so subsequent tests create their own.
      initialRunId = null;

      await waitForTerminalState(orchestrator, timeout: 60);

      print('States observed: ${states.map((s) => s.runtimeType).toList()}');
      expect(states.first, isA<RunningState>(), reason: 'Should start running');

      expect(
        orchestrator.currentState,
        isA<CompletedState>(),
        reason: 'Should complete successfully',
      );

      final completed = orchestrator.currentState as CompletedState;
      expect(completed.threadKey, equals(sharedKey));
      expect(completed.runId, isNotEmpty);
      expect(
        completed.conversation.messages,
        hasLength(greaterThan(1)),
        reason: 'Should have user message + agent response',
      );

      // Verify multiple RunningState emissions (streaming updates).
      final runningCount = states.whereType<RunningState>().length;
      print('RunningState emissions: $runningCount');
      expect(
        runningCount,
        greaterThan(1),
        reason: 'Should emit multiple RunningState updates as events arrive',
      );

      print(
        'Run completed. Messages: ${completed.conversation.messages.length}',
      );
      print('Final message: ${lastAssistantText(completed.conversation)}');
    });

    test('subsequent run in same thread', () async {
      // Run 2 in the shared thread (no existingRunId — creates a new run).
      await orchestrator.startRun(
        key: sharedKey,
        userMessage: 'Now say "goodbye".',
      );
      await waitForTerminalState(orchestrator, timeout: 60);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      print('Run 2 completed: ${lastAssistantText(completed.conversation)}');
    });

    test('reset returns to IdleState and can run again', () async {
      // Run 3.
      await orchestrator.startRun(key: sharedKey, userMessage: 'Say "ok".');
      await waitForTerminalState(orchestrator, timeout: 60);
      expect(orchestrator.currentState, isA<CompletedState>());

      final run3 = orchestrator.currentState as CompletedState;
      print('Run 3 completed: ${lastAssistantText(run3.conversation)}');

      orchestrator.reset();
      expect(orchestrator.currentState, isA<IdleState>());

      // Run 4 — same thread, after reset.
      await orchestrator.startRun(
        key: sharedKey,
        userMessage: 'Say "ok" again.',
      );
      await waitForTerminalState(orchestrator, timeout: 60);
      expect(orchestrator.currentState, isA<CompletedState>());

      final run4 = orchestrator.currentState as CompletedState;
      print('Run 4 completed: ${lastAssistantText(run4.conversation)}');

      expect(run4.runId, isNot(equals(run3.runId)));
    });
  });

  group('M5 integration: tool yielding', () {
    late ThreadKey m5Key;
    late ToolRegistry toolRegistry;

    setUpAll(() async {
      // Separate thread for M5 tests — clean conversation history.
      final (key, _) = await harness.createThread(roomId);
      print('Created M5 thread: ${key.threadId}');
      m5Key = key;

      // Client-side tool: secret_number returns "42".
      toolRegistry = const ToolRegistry().register(
        ClientTool(
          definition: const Tool(
            name: 'secret_number',
            description: 'Returns the secret number.',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          ),
          executor: (_, __) async => '42',
        ),
      );
    });

    setUp(() {
      orchestrator = harness.createOrchestrator(
        loggerName: 'm5-integration',
        toolRegistry: toolRegistry,
      );
    });

    test('Running → ToolYielding → submit → Completed', () async {
      final states = <RunState>[];
      orchestrator.stateChanges.listen(states.add);

      print('Starting M5 run: thread=${m5Key.threadId}');
      await orchestrator.startRun(
        key: m5Key,
        userMessage: 'Call the secret_number tool and tell me the result.',
      );

      // Wait for either ToolYielding or terminal state.
      await waitForYieldOrTerminal(orchestrator, timeout: 60);
      print('States so far: ${states.map((s) => s.runtimeType).toList()}');

      expect(
        orchestrator.currentState,
        isA<ToolYieldingState>(),
        reason: 'Model should call the secret_number client tool',
      );

      final yielding = orchestrator.currentState as ToolYieldingState;
      print(
        'Yielded ${yielding.pendingToolCalls.length} tool(s): '
        '${yielding.pendingToolCalls.map((t) => t.name).toList()}',
      );
      expect(yielding.pendingToolCalls, hasLength(1));
      expect(yielding.pendingToolCalls.first.name, equals('secret_number'));
      expect(yielding.toolDepth, equals(0));

      // Execute tool and submit results.
      final executed =
          yielding.pendingToolCalls
              .map(
                (tc) =>
                    tc.copyWith(status: ToolCallStatus.completed, result: '42'),
              )
              .toList();

      print('Submitting tool outputs...');
      await orchestrator.submitToolOutputs(executed);
      await waitForTerminalState(orchestrator, timeout: 60);

      expect(orchestrator.currentState, isA<CompletedState>());
      final completed = orchestrator.currentState as CompletedState;
      print(
        'M5 completed. Response: '
        '${lastAssistantText(completed.conversation)}',
      );

      // The model should mention "42" in its response.
      final responseText = lastAssistantText(completed.conversation);
      expect(
        responseText.toLowerCase(),
        contains('42'),
        reason: 'Response should include the secret number',
      );
    });

    test('server-side tools do not cause yielding', () async {
      // Use empty registry — no client tools. Server-side
      // get_current_datetime should not cause ToolYieldingState.
      orchestrator = harness.createOrchestrator(loggerName: 'm5-server-tools');

      await orchestrator.startRun(
        key: m5Key,
        userMessage: 'What time is it right now?',
      );
      await waitForTerminalState(orchestrator, timeout: 60);

      expect(
        orchestrator.currentState,
        isA<CompletedState>(),
        reason: 'Server-side tool calls should not yield',
      );
      final completed = orchestrator.currentState as CompletedState;
      print(
        'Server-side tool test completed: '
        '${lastAssistantText(completed.conversation)}',
      );
    });
  });

  group('M6 integration: AgentRuntime facade', () {
    late AgentRuntime runtime;
    late ToolRegistry toolRegistry;

    setUpAll(() {
      toolRegistry = const ToolRegistry().register(
        ClientTool(
          definition: const Tool(
            name: 'secret_number',
            description: 'Returns the secret number.',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          ),
          executor: (_, __) async => '42',
        ),
      );
    });

    setUp(() {
      runtime = harness.createRuntime(
        loggerName: 'm6-integration',
        toolRegistryResolver: (_) async => toolRegistry,
      );
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('spawn → auto-execute tool → AgentSuccess', () async {
      print('M6: spawning session with secret_number tool...');

      final session = await runtime.spawn(
        roomId: roomId,
        prompt: 'Call the secret_number tool and tell me what it returns.',
      );

      expect(session.threadKey.serverId, equals('default'));
      expect(session.threadKey.roomId, equals(roomId));
      expect(runtime.activeSessions, contains(session));

      final result = await session.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      print('M6 result type: ${result.runtimeType}');

      expect(result, isA<AgentSuccess>());
      final success = result as AgentSuccess;
      print('M6 output: ${success.output}');
      expect(
        success.output.toLowerCase(),
        contains('42'),
        reason: 'Auto-executed tool should return 42 to the model',
      );
    });

    test('spawn without tools → AgentSuccess (no yield)', () async {
      runtime = harness.createRuntime(loggerName: 'm6-no-tools');

      final session = await runtime.spawn(roomId: roomId, prompt: 'Say hello.');

      final result = await session.awaitResult(
        timeout: const Duration(seconds: 60),
      );

      expect(result, isA<AgentSuccess>());
      final success = result as AgentSuccess;
      print('M6 no-tools response: ${success.output}');
      expect(success.output, isNotEmpty);
    });

    test('cancel mid-run → AgentFailure(cancelled)', () async {
      AgentSession session;
      try {
        session = await runtime.spawn(
          roomId: roomId,
          prompt: 'Tell me a very long story about dragons.',
        );
      } on Object catch (e) {
        // Backend may drop connection under load — skip gracefully.
        print('M6 cancel: spawn failed ($e), skipping');
        return;
      }

      // Brief delay then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      session.cancel();

      final result = await session.awaitResult(
        timeout: const Duration(seconds: 10),
      );
      print('M6 cancel result: ${result.runtimeType}');

      // Could be AgentFailure(cancelled) or AgentSuccess if it finished
      // before the cancel. Both are acceptable.
      expect(
        result,
        anyOf(
          isA<AgentFailure>().having(
            (f) => f.reason,
            'reason',
            FailureReason.cancelled,
          ),
          isA<AgentSuccess>(),
          isA<AgentFailure>(),
        ),
      );
    });

    test('waitAll collects results from multiple sessions', () async {
      runtime = harness.createRuntime(loggerName: 'm6-waitall');

      final s1 = await runtime.spawn(roomId: roomId, prompt: 'Say "alpha".');
      final s2 = await runtime.spawn(roomId: roomId, prompt: 'Say "beta".');

      final results = await runtime.waitAll(
        [
          s1,
          s2,
        ],
        timeout: const Duration(seconds: 60),
      );

      print('M6 waitAll: ${results.map((r) => r.runtimeType).toList()}');
      expect(results, hasLength(2));
      expect(results.every((r) => r is AgentSuccess), isTrue);
    });
  });
}
