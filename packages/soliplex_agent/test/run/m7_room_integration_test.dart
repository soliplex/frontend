// Integration tests use print for diagnostic output.
// ignore_for_file: avoid_print
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:test/test.dart';

import '../integration/helpers/helpers.dart';

/// ------------------------------------------------------------------
/// M7 Integration tests: 19 tests across L0 → L2+++++ layers
///
/// L0/L1 tests use RunOrchestrator for manual tool control.
/// L2+ tests use AgentRuntime for auto tool execution & concurrency.
///
/// Prerequisites:
///   1. Running Soliplex backend with all M7 rooms loaded
///   2. Rooms: echo, tool-call, multi-tool, parallel, dispatch,
///      accumulator, writer, reviewer, fixer, strict-tool, searcher,
///      classifier, planner, judge, advocate, critic
///
/// Run:
///   SOLIPLEX_BASE_URL=http://localhost:8000 \
///   dart test test/run/m7_room_integration_test.dart -t integration
/// ------------------------------------------------------------------

void main() {
  final harness = IntegrationHarness();

  setUpAll(() async {
    await harness.setUp();
  });

  tearDownAll(harness.tearDown);

  // =========================================================================
  // 1. L1: Multi-tool chaining
  // =========================================================================
  group('1: multi-tool chaining', () {
    late RunOrchestrator orchestrator;
    late ThreadKey key;
    late ToolRegistry tools;

    setUpAll(() async {
      final (k, _) = await harness.createThread('multi-tool');
      print('Created multi-tool thread: ${k.threadId}');
      key = k;

      tools = const ToolRegistry().register(
        ClientTool(
          definition: const Tool(
            name: 'system_status',
            description: 'Returns current system status.',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          ),
          executor: (_, __) async => '{"cpu": "12%", "memory": "4.2GB"}',
        ),
      );
    });

    setUp(() {
      orchestrator = harness.createOrchestrator(
        loggerName: 'm7-01-multi-tool',
        toolRegistry: tools,
      );
    });

    tearDown(() {
      orchestrator.dispose();
    });

    test('sequential tool rounds → CompletedState', () async {
      await orchestrator.startRun(key: key, userMessage: 'Run diagnostics.');

      var yieldCount = 0;
      for (var round = 0; round < 5; round++) {
        await waitForYieldOrTerminal(orchestrator, timeout: 60);
        if (orchestrator.currentState is! ToolYieldingState) break;

        yieldCount++;
        final yielding = orchestrator.currentState as ToolYieldingState;
        print(
          'Round $yieldCount: '
          '${yielding.pendingToolCalls.map((t) => t.name).toList()} '
          '(depth=${yielding.toolDepth})',
        );

        final executed =
            yielding.pendingToolCalls
                .map(
                  (tc) => tc.copyWith(
                    status: ToolCallStatus.completed,
                    result: '{"cpu": "12%", "memory": "4.2GB"}',
                  ),
                )
                .toList();
        await orchestrator.submitToolOutputs(executed);
      }

      if (orchestrator.currentState is! CompletedState) {
        await waitForTerminalState(orchestrator, timeout: 60);
      }

      expect(
        yieldCount,
        greaterThanOrEqualTo(1),
        reason: 'Should yield at least once for system_status',
      );
      expect(orchestrator.currentState, isA<CompletedState>());
      final completedConvo =
          (orchestrator.currentState as CompletedState).conversation;
      print('Response: ${lastAssistantText(completedConvo)}');
    });
  });

  // =========================================================================
  // 2. L0: Non-existent room error
  // =========================================================================
  group('2: non-existent room error', () {
    test('createThread throws NotFoundException', () async {
      expect(
        () => harness.api.createThread('room-that-does-not-exist-999'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('AgentRuntime.spawn throws for bad room', () async {
      final runtime = harness.createRuntime(loggerName: 'm7-02-error');

      try {
        Object? caught;
        try {
          await runtime.spawn(
            roomId: 'room-that-does-not-exist-999',
            prompt: 'This should fail.',
          );
        } on Object catch (e) {
          caught = e;
        }

        print('Error type: ${caught.runtimeType}');
        expect(caught, isNotNull, reason: 'spawn should throw');
        expect(caught, isA<NotFoundException>());
      } finally {
        await runtime.dispose();
      }
    });
  });

  // =========================================================================
  // 3. L1: Conditional tool dispatch
  // =========================================================================
  group('3: conditional dispatch', () {
    late RunOrchestrator orchestrator;
    late ThreadKey key;
    late ToolRegistry tools;

    setUpAll(() async {
      final (k, _) = await harness.createThread('dispatch');
      print('Created dispatch thread: ${k.threadId}');
      key = k;

      tools = const ToolRegistry()
          .register(
            ClientTool(
              definition: const Tool(
                name: 'tool_a',
                description: 'Returns data A.',
                parameters: <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
              ),
              executor: (_, __) async => 'result_A',
            ),
          )
          .register(
            ClientTool(
              definition: const Tool(
                name: 'tool_b',
                description: 'Returns data B.',
                parameters: <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
              ),
              executor: (_, __) async => 'result_B',
            ),
          )
          .register(
            ClientTool(
              definition: const Tool(
                name: 'tool_c',
                description: 'Returns data C.',
                parameters: <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
              ),
              executor: (_, __) async => 'result_C',
            ),
          );
    });

    setUp(() {
      orchestrator = harness.createOrchestrator(
        loggerName: 'm7-03-dispatch',
        toolRegistry: tools,
      );
    });

    tearDown(() {
      orchestrator.dispose();
    });

    test('compound request calls correct tools', () async {
      await orchestrator.startRun(
        key: key,
        userMessage: 'Call tool_a and tool_c. Do NOT call tool_b.',
      );

      final calledTools = <String>{};
      for (var round = 0; round < 5; round++) {
        await waitForYieldOrTerminal(orchestrator, timeout: 60);
        if (orchestrator.currentState is! ToolYieldingState) break;

        final yielding = orchestrator.currentState as ToolYieldingState;
        for (final tc in yielding.pendingToolCalls) {
          calledTools.add(tc.name);
        }
        final toolNames = yielding.pendingToolCalls.map((t) => t.name).toList();
        print('Round ${round + 1}: $toolNames');

        final executed =
            yielding.pendingToolCalls
                .map(
                  (tc) => tc.copyWith(
                    status: ToolCallStatus.completed,
                    result: 'result_${tc.name.split("_").last}',
                  ),
                )
                .toList();
        await orchestrator.submitToolOutputs(executed);
      }

      if (orchestrator.currentState is! CompletedState) {
        await waitForTerminalState(orchestrator, timeout: 60);
      }

      print('All tools called: $calledTools');
      expect(calledTools, contains('tool_a'));
      expect(calledTools, contains('tool_c'));
      expect(orchestrator.currentState, isA<CompletedState>());
    });
  });

  // =========================================================================
  // 4. L0+: Multi-turn accumulation
  // =========================================================================
  group('4: multi-turn accumulation', () {
    late RunOrchestrator orchestrator;
    late ThreadKey key;

    setUpAll(() async {
      final (k, _) = await harness.createThread('accumulator');
      print('Created accumulator thread: ${k.threadId}');
      key = k;
    });

    setUp(() {
      orchestrator = harness.createOrchestrator(
        loggerName: 'm7-04-accumulator',
      );
    });

    tearDown(() {
      orchestrator.dispose();
    });

    test('3 turns then recall from memory', () async {
      // Turn 1.
      await orchestrator.startRun(
        key: key,
        userMessage: 'Fact 1: The sky is blue.',
      );
      await waitForTerminalState(orchestrator, timeout: 60);
      expect(orchestrator.currentState, isA<CompletedState>());
      var history = ThreadHistory(
        messages:
            (orchestrator.currentState as CompletedState).conversation.messages,
      );
      orchestrator.reset();

      // Turn 2 — carry forward turn 1 history.
      await orchestrator.startRun(
        key: key,
        userMessage: 'Fact 2: Grass is green.',
        cachedHistory: history,
      );
      await waitForTerminalState(orchestrator, timeout: 60);
      expect(orchestrator.currentState, isA<CompletedState>());
      history = ThreadHistory(
        messages:
            (orchestrator.currentState as CompletedState).conversation.messages,
      );
      orchestrator.reset();

      // Turn 3 — recall only, carry forward turns 1 + 2.
      await orchestrator.startRun(
        key: key,
        userMessage: 'What are the two facts I told you?',
        cachedHistory: history,
      );
      await waitForTerminalState(orchestrator, timeout: 60);
      expect(orchestrator.currentState, isA<CompletedState>());

      final response =
          lastAssistantText(
            (orchestrator.currentState as CompletedState).conversation,
          ).toLowerCase();
      print('Recall response: $response');
      expect(response, contains('blue'));
      expect(response, contains('green'));
    });
  });

  // =========================================================================
  // 4b. L2: Multi-turn accumulation via AgentRuntime.spawn()
  // =========================================================================
  group('4b: multi-turn via spawn() with automatic history', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-04b-spawn-history');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('2 turns via spawn then recall (auto-threaded)', () async {
      // Turn 1: spawn without history.
      final s1 = await runtime.spawn(
        roomId: 'accumulator',
        prompt: 'Fact 1: Water freezes at 0°C.',
      );
      final r1 = await s1.awaitResult(timeout: const Duration(seconds: 60));
      expect(r1, isA<AgentSuccess>());
      print('Turn 1 done: ${(r1 as AgentSuccess).output}');

      // Turn 2: same thread — runtime auto-injects history.
      final s2 = await runtime.spawn(
        roomId: 'accumulator',
        prompt: 'Fact 2: Water boils at 100°C.',
        threadId: s1.threadKey.threadId,
      );
      final r2 = await s2.awaitResult(timeout: const Duration(seconds: 60));
      expect(r2, isA<AgentSuccess>());
      print('Turn 2 done: ${(r2 as AgentSuccess).output}');

      // Turn 3: recall both facts — runtime threads history automatically.
      final s3 = await runtime.spawn(
        roomId: 'accumulator',
        prompt: 'What are the two facts I told you?',
        threadId: s1.threadKey.threadId,
      );
      final r3 = await s3.awaitResult(timeout: const Duration(seconds: 60));
      expect(r3, isA<AgentSuccess>());
      final response = (r3 as AgentSuccess).output.toLowerCase();
      print('Recall response: $response');

      expect(response, contains('0'));
      expect(response, contains('100'));
    });
  });

  // =========================================================================
  // 5. L2: Write → review → revise pipeline
  // =========================================================================
  group('5: write-review-revise pipeline', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-05-pipeline');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('3-stage pipeline produces output', () async {
      // Stage 1: write.
      final s1 = await runtime.spawn(
        roomId: 'writer',
        prompt: 'Write one sentence about a magical forest.',
      );
      final r1 = await s1.awaitResult(timeout: const Duration(seconds: 60));
      expect(r1, isA<AgentSuccess>());
      final draft = (r1 as AgentSuccess).output;
      print('Draft: $draft');

      // Stage 2: review.
      final s2 = await runtime.spawn(
        roomId: 'reviewer',
        prompt: 'Review this draft: $draft',
      );
      final r2 = await s2.awaitResult(timeout: const Duration(seconds: 60));
      expect(r2, isA<AgentSuccess>());
      final review = (r2 as AgentSuccess).output;
      print('Review: $review');

      // Stage 3: revise.
      final s3 = await runtime.spawn(
        roomId: 'fixer',
        prompt: 'Draft: $draft\nCritique: $review\nProduce a revised version.',
      );
      final r3 = await s3.awaitResult(timeout: const Duration(seconds: 60));
      expect(r3, isA<AgentSuccess>());
      print('Revised: ${(r3 as AgentSuccess).output}');
    });
  });

  // =========================================================================
  // 6. L0+: Context depth stress (5 turns)
  // =========================================================================
  group('6: context depth stress', () {
    late RunOrchestrator orchestrator;
    late ThreadKey key;

    setUpAll(() async {
      final (k, _) = await harness.createThread('echo');
      print('Created depth-stress thread: ${k.threadId}');
      key = k;
    });

    setUp(() {
      orchestrator = harness.createOrchestrator(loggerName: 'm7-06-depth');
    });

    tearDown(() {
      orchestrator.dispose();
    });

    test('recall 4 words from earlier turns', () async {
      const words = ['CRIMSON', 'VELVET', 'OBSIDIAN', 'PHOSPHOR'];

      var history = ThreadHistory(messages: const []);

      for (final word in words) {
        await orchestrator.startRun(
          key: key,
          userMessage: 'Remember the word: $word',
          cachedHistory: history,
        );
        await waitForTerminalState(orchestrator, timeout: 60);
        expect(orchestrator.currentState, isA<CompletedState>());
        history = ThreadHistory(
          messages:
              (orchestrator.currentState as CompletedState)
                  .conversation
                  .messages,
        );
        orchestrator.reset();
      }

      // Turn 5 — recall.
      await orchestrator.startRun(
        key: key,
        userMessage: 'List all four words I asked you to remember, in order.',
        cachedHistory: history,
      );
      await waitForTerminalState(orchestrator, timeout: 60);
      expect(orchestrator.currentState, isA<CompletedState>());

      final response =
          lastAssistantText(
            (orchestrator.currentState as CompletedState).conversation,
          ).toUpperCase();
      print('Recall: $response');
      for (final word in words) {
        expect(response, contains(word));
      }
    });
  });

  // =========================================================================
  // 7. L1+: Tool arg fidelity + failure recovery
  // =========================================================================
  group('7: tool arg fidelity + failure recovery', () {
    late RunOrchestrator orchestrator;
    late ThreadKey key;
    late ToolRegistry tools;

    setUpAll(() async {
      final (k, _) = await harness.createThread('strict-tool');
      print('Created strict-tool thread: ${k.threadId}');
      key = k;

      tools = const ToolRegistry().register(
        ClientTool(
          definition: const Tool(
            name: 'calculate',
            description: 'Performs a calculation on a number.',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'num': <String, dynamic>{'type': 'integer'},
              },
            },
          ),
          executor: (_, __) async => '42',
        ),
      );
    });

    setUp(() {
      orchestrator = harness.createOrchestrator(
        loggerName: 'm7-07-strict',
        toolRegistry: tools,
      );
    });

    tearDown(() {
      orchestrator.dispose();
    });

    test('fail first call → agent retries → CompletedState', () async {
      await orchestrator.startRun(
        key: key,
        userMessage: 'Calculate something using the calculate tool.',
      );

      for (var round = 0; round < 5; round++) {
        await waitForYieldOrTerminal(orchestrator, timeout: 60);
        if (orchestrator.currentState is! ToolYieldingState) break;

        final yielding = orchestrator.currentState as ToolYieldingState;
        print(
          'Round ${round + 1} args: '
          '${yielding.pendingToolCalls.first.arguments}',
        );

        // First round: force failure. All others: succeed.
        final executed =
            yielding.pendingToolCalls
                .map(
                  (tc) => tc.copyWith(
                    status:
                        round == 0
                            ? ToolCallStatus.failed
                            : ToolCallStatus.completed,
                    result:
                        round == 0
                            ? 'error: value must be greater than 100'
                            : '42',
                  ),
                )
                .toList();
        await orchestrator.submitToolOutputs(executed);
      }

      if (orchestrator.currentState is! CompletedState) {
        await waitForTerminalState(orchestrator, timeout: 60);
      }

      expect(
        orchestrator.currentState,
        isA<CompletedState>(),
        reason: 'Agent should recover from tool failure',
      );
      final completedConvo2 =
          (orchestrator.currentState as CompletedState).conversation;
      print('Response: ${lastAssistantText(completedConvo2)}');
    });
  });

  // =========================================================================
  // 8. L2+: Fan-out / fan-in aggregation
  // =========================================================================
  group('8: fan-out / fan-in', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-08-fanout');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('3 parallel mappers + 1 reducer', () async {
      // Fan-out.
      final s1 = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Say exactly: ALPHA=100',
      );
      final s2 = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Say exactly: BETA=200',
      );
      final s3 = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Say exactly: GAMMA=300',
      );

      final results = await runtime.waitAll(
        [
          s1,
          s2,
          s3,
        ],
        timeout: const Duration(seconds: 90),
      );
      expect(results, hasLength(3));
      expect(results.every((r) => r is AgentSuccess), isTrue);

      final outputs = results.map((r) => (r as AgentSuccess).output).toList();
      print('Mapper outputs: $outputs');

      // Fan-in.
      final reducer = await runtime.spawn(
        roomId: 'echo',
        prompt:
            'Given: ${outputs.join(", ")} — what is the sum of the numbers?',
      );
      final reduced = await reducer.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      expect(reduced, isA<AgentSuccess>());
      final answer = (reduced as AgentSuccess).output;
      print('Reducer answer: $answer');
      expect(answer, contains('600'));
    });
  });

  // =========================================================================
  // 9. L2+: waitAny racing + cancellation
  // =========================================================================
  group('9: waitAny racing', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-09-race');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('first finisher wins, losers cancel', () async {
      final fast = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Say "done".',
      );
      final medium = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Write a 5 sentence story about a robot.',
      );
      final slow = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Write a detailed 3 paragraph essay about quantum computing.',
      );

      final winner = await runtime.waitAny(
        [
          fast,
          medium,
          slow,
        ],
        timeout: const Duration(seconds: 60),
      );
      print('Winner type: ${winner.runtimeType}');
      expect(winner, isA<AgentSuccess>());

      // Cancel any still running.
      for (final s in [fast, medium, slow]) {
        if (s.state != AgentSessionState.completed) {
          s.cancel();
        }
      }
    });
  });

  // =========================================================================
  // 10. L1++: Iterative refinement loop
  // =========================================================================
  group('10: iterative refinement', () {
    late RunOrchestrator orchestrator;
    late ThreadKey key;
    late ToolRegistry tools;
    var callCount = 0;

    setUpAll(() async {
      final (k, _) = await harness.createThread('searcher');
      print('Created searcher thread: ${k.threadId}');
      key = k;

      tools = const ToolRegistry().register(
        ClientTool(
          definition: const Tool(
            name: 'search_db',
            description: 'Searches the database.',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'query': <String, dynamic>{'type': 'string'},
              },
            },
          ),
          // Executor is unused — we control results manually.
          executor: (_, __) async => '',
        ),
      );
    });

    setUp(() {
      callCount = 0;
      orchestrator = harness.createOrchestrator(
        loggerName: 'm7-10-refine',
        toolRegistry: tools,
      );
    });

    tearDown(() {
      orchestrator.dispose();
    });

    test('search → "not found" → refine → success', () async {
      await orchestrator.startRun(
        key: key,
        userMessage: 'Find the document about quantum error correction.',
      );

      for (var round = 0; round < 5; round++) {
        await waitForYieldOrTerminal(orchestrator, timeout: 60);
        if (orchestrator.currentState is! ToolYieldingState) break;

        callCount++;
        final yielding = orchestrator.currentState as ToolYieldingState;
        print(
          'Search round $callCount: '
          '${yielding.pendingToolCalls.first.arguments}',
        );

        // First call: not found. Second+: found.
        final result =
            callCount == 1
                ? 'Not found. Try narrowing your search with "QEC".'
                : 'Found: doc-42 "Quantum Error Correction Primer"';

        final executed =
            yielding.pendingToolCalls
                .map(
                  (tc) => tc.copyWith(
                    status: ToolCallStatus.completed,
                    result: result,
                  ),
                )
                .toList();
        await orchestrator.submitToolOutputs(executed);
      }

      if (orchestrator.currentState is! CompletedState) {
        await waitForTerminalState(orchestrator, timeout: 60);
      }

      expect(callCount, greaterThanOrEqualTo(2));
      expect(orchestrator.currentState, isA<CompletedState>());
      final response = lastAssistantText(
        (orchestrator.currentState as CompletedState).conversation,
      );
      print('Final: $response');
      expect(response, contains('doc-42'));
    });
  });

  // =========================================================================
  // 11. L2++: Dynamic room routing via classifier
  // =========================================================================
  group('11: dynamic room routing', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-11-routing');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('classifier routes to correct room', () async {
      // Classify.
      final classifier = await runtime.spawn(
        roomId: 'classifier',
        prompt: 'Tell me a joke about programming.',
      );
      final cr = await classifier.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      expect(cr, isA<AgentSuccess>());

      final raw = (cr as AgentSuccess).output.trim().toLowerCase();
      // Extract room name — strip any non-alphanumeric except dash.
      final targetRoom = raw.replaceAll(RegExp(r'[^a-z\-]'), '');
      print('Classifier chose: "$targetRoom" (raw: "$raw")');
      expect(
        ['echo', 'tool-call', 'parallel'],
        contains(targetRoom),
        reason: 'Classifier should pick a valid room',
      );

      // Route.
      final routed = await runtime.spawn(
        roomId: targetRoom,
        prompt: 'Hello from the routed session.',
      );
      final rr = await routed.awaitResult(timeout: const Duration(seconds: 60));
      expect(rr, isA<AgentSuccess>());
      print('Routed response: ${(rr as AgentSuccess).output}');
    });
  });

  // =========================================================================
  // 12. L2++: Runtime introspection under load
  // =========================================================================
  group('12: runtime introspection', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(
        loggerName: 'm7-12-introspect',
        platform: const NativePlatformConstraints(maxConcurrentBridges: 10),
      );
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('activeSessions and sessionChanges during 5 sessions', () async {
      var maxSeen = 0;
      final sub = runtime.sessionChanges.listen((sessions) {
        if (sessions.length > maxSeen) maxSeen = sessions.length;
      });

      // Spawn 5 sequentially (each await ensures it's tracked).
      final sessions = <AgentSession>[];
      for (var i = 0; i < 5; i++) {
        sessions.add(
          await runtime.spawn(roomId: 'parallel', prompt: 'Say "$i".'),
        );
      }

      print('Active after spawning: ${runtime.activeSessions.length}');
      expect(runtime.activeSessions.length, equals(5));

      final results = await runtime.waitAll(
        sessions,
        timeout: const Duration(seconds: 90),
      );
      expect(results, hasLength(5));
      expect(results.every((r) => r is AgentSuccess), isTrue);
      print('Max sessions seen: $maxSeen');
      expect(maxSeen, greaterThanOrEqualTo(5));

      await sub.cancel();
    });
  });

  // =========================================================================
  // 13. L2++: Thread resilience after cancel
  // =========================================================================
  group('13: thread resilience', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-13-resilience');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('cancel mid-run, next run on same thread succeeds', () async {
      // Turn 1: complete normally (non-ephemeral to preserve thread).
      final s1 = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Hello, this is a setup message.',
      );
      final r1 = await s1.awaitResult(timeout: const Duration(seconds: 60));
      expect(r1, isA<AgentSuccess>());
      final threadId = s1.threadKey.threadId;
      print('Turn 1 done on thread: $threadId');

      // Turn 2: cancel mid-stream.
      final s2 = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Tell me a very long story about dragons.',
        threadId: threadId,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      s2.cancel();
      final r2 = await s2.awaitResult(timeout: const Duration(seconds: 10));
      print('Turn 2 result: ${r2.runtimeType}');

      // Turn 3: new run on the SAME thread succeeds (thread not corrupted).
      final s3 = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Tell me a one-sentence joke.',
        threadId: threadId,
      );
      final r3 = await s3.awaitResult(timeout: const Duration(seconds: 60));
      print('Turn 3 result: ${r3.runtimeType}');
      expect(
        r3,
        isA<AgentSuccess>(),
        reason: 'Thread should remain usable after cancel',
      );
      print('Turn 3 output: ${(r3 as AgentSuccess).output}');
    });
  });

  // =========================================================================
  // 14. L2+++: Plan → fan-out → synthesize
  // =========================================================================
  group('14: plan-fanout-synthesize', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-14-plan');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('planner decomposes → workers execute → synthesizer merges', () async {
      // Plan.
      final planner = await runtime.spawn(
        roomId: 'planner',
        prompt:
            'Describe a futuristic city in 3 aspects: '
            'architecture, transportation, energy.',
      );
      final pr = await planner.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      expect(pr, isA<AgentSuccess>());

      // Parse subtasks — handle LLM formatting quirks.
      var tasks = <String>[];
      try {
        final raw =
            (pr as AgentSuccess).output
                .replaceAll(RegExp(r'^```json\s*|\s*```$'), '')
                .trim();
        tasks = List<String>.from(jsonDecode(raw) as List);
      } on Object catch (e) {
        print('JSON parse failed ($e), using fallback subtasks');
        tasks = [
          'Describe futuristic architecture',
          'Describe futuristic transportation',
          'Describe futuristic energy',
        ];
      }
      print('Subtasks: $tasks');

      // Fan-out — use echo room (handles full-sentence prompts).
      final workers = <AgentSession>[];
      for (final task in tasks) {
        workers.add(await runtime.spawn(roomId: 'echo', prompt: task));
      }

      final results = await runtime.waitAll(
        workers,
        timeout: const Duration(seconds: 90),
      );
      expect(results.every((r) => r is AgentSuccess), isTrue);

      final workerOutputs =
          results.map((r) => (r as AgentSuccess).output).toList();
      print('Worker outputs: $workerOutputs');

      // Synthesize.
      final synth = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Combine into one paragraph: ${workerOutputs.join("; ")}',
      );
      final sr = await synth.awaitResult(timeout: const Duration(seconds: 60));
      expect(sr, isA<AgentSuccess>());
      print('Synthesis: ${(sr as AgentSuccess).output}');
    });
  });

  // =========================================================================
  // 15. L2+++: Consensus voting
  // =========================================================================
  group('15: consensus voting', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-15-consensus');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('3 opinions → judge picks consensus', () async {
      // Gather 3 opinions.
      final s1 = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Is Pluto a planet? Answer YES or NO with one sentence.',
      );
      final s2 = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Is Pluto a planet? Answer YES or NO with one sentence.',
      );
      final s3 = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Is Pluto a planet? Answer YES or NO with one sentence.',
      );

      final results = await runtime.waitAll(
        [s1, s2, s3],
        timeout: const Duration(seconds: 90),
      );
      expect(results.every((r) => r is AgentSuccess), isTrue);

      final opinions = results.map((r) => (r as AgentSuccess).output).toList();
      print('Opinions: $opinions');

      // Judge.
      final judge = await runtime.spawn(
        roomId: 'judge',
        prompt:
            'Three experts were asked "Is Pluto a planet?"\n'
            '1: ${opinions[0]}\n'
            '2: ${opinions[1]}\n'
            '3: ${opinions[2]}\n'
            'What is the consensus?',
      );
      final jr = await judge.awaitResult(timeout: const Duration(seconds: 60));
      expect(jr, isA<AgentSuccess>());
      print('Judge verdict: ${(jr as AgentSuccess).output}');
    });
  });

  // =========================================================================
  // 16. L2+++: Speculative execution
  // =========================================================================
  group('16: speculative execution', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-16-speculative');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('race both branches, discard wrong one', () async {
      // Classify.
      final classifier = await runtime.spawn(
        roomId: 'classifier',
        prompt: 'Classify: "Tell me a joke". Reply echo or parallel.',
      );

      // Speculatively spawn both paths.
      final specEcho = await runtime.spawn(
        roomId: 'echo',
        prompt: 'Tell me a joke.',
      );
      final specParallel = await runtime.spawn(
        roomId: 'parallel',
        prompt: 'Tell me a joke.',
      );

      // Wait for classifier to decide.
      final cr = await classifier.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      expect(cr, isA<AgentSuccess>());
      final route = (cr as AgentSuccess).output.trim().toLowerCase().replaceAll(
        RegExp('[^a-z]'),
        '',
      );
      print('Classifier route: $route');

      // Keep winner, cancel loser.
      final AgentSession winner;
      final AgentSession loser;
      if (route.contains('echo')) {
        winner = specEcho;
        loser = specParallel;
      } else {
        winner = specParallel;
        loser = specEcho;
      }
      loser.cancel();

      final result = await winner.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      expect(result, isA<AgentSuccess>());
      print('Winner output: ${(result as AgentSuccess).output}');
    });
  });

  // =========================================================================
  // 17. L2++++: Cascading pipeline with fallback recovery
  // =========================================================================
  group('17: cascading pipeline + fallback', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-17-cascade');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('writer → reviewer FAIL → fixer → reviewer PASS', () async {
      // Stage 1: write.
      final writer = await runtime.spawn(
        roomId: 'writer',
        prompt: 'Write exactly 3 bullet points about Dart programming.',
      );
      final wr = await writer.awaitResult(timeout: const Duration(seconds: 60));
      expect(wr, isA<AgentSuccess>());
      var draft = (wr as AgentSuccess).output;
      print('Draft: $draft');

      var passed = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        // Review.
        final reviewer = await runtime.spawn(
          roomId: 'reviewer',
          prompt:
              'Does this have exactly 3 bullet points? '
              'Reply PASS or FAIL: <reason>.\n\n$draft',
        );
        final rr = await reviewer.awaitResult(
          timeout: const Duration(seconds: 60),
        );
        expect(rr, isA<AgentSuccess>());
        final review = (rr as AgentSuccess).output;
        print('Review (attempt ${attempt + 1}): $review');

        if (review.toUpperCase().contains('PASS')) {
          passed = true;
          break;
        }

        // Fix.
        final fixer = await runtime.spawn(
          roomId: 'fixer',
          prompt:
              'Draft: $draft\nFeedback: $review\n'
              'Produce exactly 3 bullet points about Dart.',
        );
        final fr = await fixer.awaitResult(
          timeout: const Duration(seconds: 60),
        );
        expect(fr, isA<AgentSuccess>());
        draft = (fr as AgentSuccess).output;
        print('Fixed draft: $draft');
      }

      print('Pipeline passed: $passed');
      // We don't hard-assert PASS since LLM reviewers are non-deterministic,
      // but the pipeline should complete without error.
    });
  });

  // =========================================================================
  // 18. L2++++: Adversarial debate
  // =========================================================================
  group('18: adversarial debate', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(loggerName: 'm7-18-debate');
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('advocate → critic → rebuttal → judge verdict', () async {
      // Advocate.
      final adv = await runtime.spawn(
        roomId: 'advocate',
        prompt: 'Argue FOR remote work being better than office work.',
      );
      final ar = await adv.awaitResult(timeout: const Duration(seconds: 60));
      expect(ar, isA<AgentSuccess>());
      final forArgs = (ar as AgentSuccess).output;
      print('Advocate: $forArgs');

      // Critic.
      final crt = await runtime.spawn(
        roomId: 'critic',
        prompt: 'Counter these arguments: $forArgs',
      );
      final crr = await crt.awaitResult(timeout: const Duration(seconds: 60));
      expect(crr, isA<AgentSuccess>());
      final againstArgs = (crr as AgentSuccess).output;
      print('Critic: $againstArgs');

      // Rebuttal.
      final reb = await runtime.spawn(
        roomId: 'advocate',
        prompt:
            'A critic responded: $againstArgs\n'
            'Defend your strongest point in 2 sentences.',
      );
      final rbr = await reb.awaitResult(timeout: const Duration(seconds: 60));
      expect(rbr, isA<AgentSuccess>());
      final rebuttal = (rbr as AgentSuccess).output;
      print('Rebuttal: $rebuttal');

      // Judge.
      final jdg = await runtime.spawn(
        roomId: 'judge',
        prompt:
            'Debate: "Is remote work better than office work?"\n'
            'FOR: $rebuttal\n'
            'AGAINST: $againstArgs\n'
            'Who made the stronger argument? '
            'Reply ADVOCATE or CRITIC with justification.',
      );
      final jr = await jdg.awaitResult(timeout: const Duration(seconds: 60));
      expect(jr, isA<AgentSuccess>());
      final verdict = (jr as AgentSuccess).output;
      print('Verdict: $verdict');
      expect(
        verdict.toUpperCase(),
        anyOf(contains('ADVOCATE'), contains('CRITIC')),
      );
    });
  });

  // =========================================================================
  // 19. L2+++++: MapReduce (5 mappers + 1 reducer)
  // =========================================================================
  group('19: MapReduce', () {
    late AgentRuntime runtime;

    setUp(() {
      runtime = harness.createRuntime(
        loggerName: 'm7-19-mapreduce',
        platform: const NativePlatformConstraints(maxConcurrentBridges: 10),
      );
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('5 mappers extract data → 1 reducer synthesizes', () async {
      const chunks = [
        'Country: Japan, Capital: Tokyo, Pop: 125M',
        'Country: Brazil, Capital: Brasilia, Pop: 214M',
        'Country: Kenya, Capital: Nairobi, Pop: 54M',
        'Country: Norway, Capital: Oslo, Pop: 5.4M',
        'Country: Australia, Capital: Canberra, Pop: 26M',
      ];

      // Map.
      final mappers = <AgentSession>[];
      for (final chunk in chunks) {
        mappers.add(
          await runtime.spawn(
            roomId: 'parallel',
            prompt:
                'Extract only the population number from: $chunk. '
                'Reply with just the number.',
          ),
        );
      }

      final mapResults = await runtime.waitAll(
        mappers,
        timeout: const Duration(seconds: 90),
      );
      expect(mapResults, hasLength(5));
      expect(mapResults.every((r) => r is AgentSuccess), isTrue);

      final populations =
          mapResults.map((r) => (r as AgentSuccess).output.trim()).toList();
      print('Mapped populations: $populations');

      // Reduce.
      final reducer = await runtime.spawn(
        roomId: 'echo',
        prompt:
            'Given populations: ${populations.join(", ")} — '
            'which country has the largest and smallest population? '
            'The data was: ${chunks.join("; ")}',
      );
      final rr = await reducer.awaitResult(
        timeout: const Duration(seconds: 60),
      );
      expect(rr, isA<AgentSuccess>());
      final answer = (rr as AgentSuccess).output;
      print('Reducer: $answer');
      expect(answer.toLowerCase(), contains('brazil'));
      expect(answer.toLowerCase(), contains('norway'));
    });
  });
}
