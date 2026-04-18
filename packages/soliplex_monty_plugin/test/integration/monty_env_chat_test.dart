// Integration tests — print is intentional for live-test output.
// ignore_for_file: avoid_print
@Tags(['integration'])
library;

import 'dart:async' show Timer;

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

/// Base URL for the Soliplex demo server.
///
/// Override at test-run time with:
///   dart test --define=SOLIPLEX_TEST_URL=http://localhost:8000
const _demoUrl = String.fromEnvironment(
  'SOLIPLEX_TEST_URL',
  defaultValue: 'https://demo.toughserv.com',
);

final Logger _logger = LogManager.instance.getLogger('monty_env_chat_test');

ServerConnection _conn(String serverId) => ServerConnection.create(
      serverId: serverId,
      serverUrl: _demoUrl,
      httpClient: createAgentHttpClient(),
    );

AgentRuntime _runtime({SessionExtensionFactory? extensionFactory}) =>
    AgentRuntime(
      connection: _conn('demo'),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      platform: const WebPlatformConstraints(),
      logger: _logger,
      extensionFactory: extensionFactory,
    );

Future<String> _secretNumber(ToolCallInfo _, ToolExecutionContext __) async =>
    '42';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // T0 — AG-UI client tool callback (no dart_monty)
  //
  // Proves the chat room LLM sees client-side tools AND calls them back.
  // Uses a secret_number tool whose answer (42) is unknowable without a real
  // callback — if the LLM returns "42" it must have called the tool.
  // Fails fast if the server strips client tools or the callback path is
  // broken before introducing any Monty complexity.
  // ──────────────────────────────────────────────────────────────────────────

  group('T0: AG-UI client tool callback (no Monty)', () {
    late AgentRuntime runtime;

    const secretTool = ClientTool(
      definition: Tool(
        name: 'secret_number',
        description: 'Returns the secret number. '
            'Always call this tool when asked for the secret number.',
        parameters: {'type': 'object', 'properties': <String, Object>{}},
      ),
      executor: _secretNumber,
    );

    setUp(() {
      runtime = AgentRuntime(
        connection: _conn('demo'),
        toolRegistryResolver: (_) async =>
            const ToolRegistry().register(secretTool),
        platform: const WebPlatformConstraints(),
        logger: _logger,
      );
    });

    tearDown(() async => runtime.dispose());

    test(
      'chat LLM calls secret_number tool and returns its result',
      () async {
        final session = await runtime.spawn(
          roomId: 'chat',
          prompt: 'What is the secret number? '
              'You must call the secret_number tool to find out.',
          ephemeral: true,
          autoDispose: true,
        );
        final result = await session.awaitResult(
          timeout: const Duration(seconds: 45),
        );
        final output = (result as AgentSuccess).output;
        print('  T0 → $output');
        expect(output, contains('42'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Fire-and-forget — fresh MontyScriptEnvironment per AgentRuntime.spawn().
  //
  // extensionFactory creates a NEW MontyScriptEnvironment per session.
  // autoDispose: true so each session disposes its own env when done.
  // No shared Python state between sessions.
  // ──────────────────────────────────────────────────────────────────────────

  group('fire-and-forget (fresh interpreter per session)', () {
    late AgentRuntime runtime;

    setUpAll(() {
      runtime = _runtime(
        extensionFactory: toOwnedFactory(
          (ctx) async {
            final innerConn = _conn('inner');
            final soliplexConn = SoliplexConnection.fromServerConnection(
              innerConn,
              alias: 'inner',
              serverUrl: _demoUrl,
            );
            return MontyScriptEnvironment(
              tools: buildSoliplexTools(ctx, () => {'inner': soliplexConn}),
            );
          },
        ),
      );
    });

    tearDownAll(() async => runtime.dispose());

    Future<String> ask(String prompt) async {
      final session = await runtime.spawn(
        roomId: 'chat',
        prompt: prompt,
        ephemeral: true,
        autoDispose: true,
      );
      return switch (await session.awaitResult(
        timeout: const Duration(seconds: 60),
      )) {
        AgentSuccess(:final output) => output,
        final r => throw StateError('Session did not succeed: $r'),
      };
    }

    test(
      'T1: Python tool appears in server LLM tool list',
      () async {
        // Soliplex host functions are Python-callable (host functions on the
        // dart_monty bridge) — not ClientTools. The server LLM sees only the
        // execute_python ClientTool; Soliplex APIs are reached from Python.
        final output = await ask(
          'List every tool name you have access to. '
          'Reply with only a comma-separated list of tool names.',
        );
        print('  T1 → $output');
        expect(output, contains('execute_python'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'T2: LLM calls execute_python and returns computed result',
      () async {
        final output = await ask(
          'Use your execute_python tool to compute 6 * 7. '
          'Reply with only the numeric result.',
        );
        print('  T2 → $output');
        expect(output, contains('42'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'T7: each fire-and-forget session has isolated Python state',
      () async {
        // Session 1: set a distinctive marker and confirm the value.
        final s1 = await ask(
          'Use execute_python to run this code and reply with ONLY the '
          'number it returns: isolation_marker = 7777; isolation_marker',
        );
        print('  T7-s1 → "$s1"');
        expect(s1, contains('7777'));

        // Session 2 is a fresh interpreter — isolation_marker must not exist.
        // vars().get() returns 'absent' without raising NameError.
        final s2 = await ask(
          'Use execute_python to run this code and reply with ONLY the '
          "word it returns: vars().get('isolation_marker', 'absent')",
        );
        print('  T7-s2 → "$s2"');
        // Must not see 7777 — that would mean state leaked from session 1.
        expect(
          s2,
          isNot(contains('7777')),
          reason: 'Python variable from session 1 visible in session 2 — '
              'interpreters are not isolated',
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Stateful — single MontyScriptEnvironment shared across sessions.
  //
  // toSharedFactory wraps the env WITHOUT taking ownership:
  // dispose() is a no-op, so the shared env survives each session ending.
  // tearDownAll owns env.dispose().  autoDispose defaults to false so the
  // session does not attempt to dispose extensions on completion.
  // ──────────────────────────────────────────────────────────────────────────

  group('stateful (persistent Python interpreter)', () {
    late AgentRuntime runtime;
    late MontyScriptEnvironment env;

    setUpAll(() {
      final innerConn = _conn('inner');
      final soliplexConn = SoliplexConnection.fromServerConnection(
        innerConn,
        alias: 'inner',
        serverUrl: _demoUrl,
      );
      env = MontyScriptEnvironment(
        tools: buildSoliplexTools(
          const SessionContext(serverId: 'inner', roomId: 'chat'),
          () => {'inner': soliplexConn},
        ),
      );
      // toSharedFactory: env is NOT disposed when a session ends.
      // Caller (tearDownAll) owns env.dispose().
      runtime = _runtime(
        extensionFactory: toSharedFactory(env),
      );
    });

    tearDownAll(() async {
      env.dispose();
      await runtime.dispose();
    });

    Future<String> ask(String prompt) async {
      // autoDispose defaults to false — env stays alive between test calls.
      final session = await runtime.spawn(
        roomId: 'chat',
        prompt: prompt,
        ephemeral: true,
      );
      return switch (await session.awaitResult(
        timeout: const Duration(seconds: 60),
      )) {
        AgentSuccess(:final output) => output,
        final r => throw StateError('Session did not succeed: $r'),
      };
    }

    test(
      'T3: execute_python state persists across tool calls within a session',
      () async {
        // Two execute_python calls in a single spawn() — the LLM has context
        // of the first call when making the second. Tests AgentSession
        // _sessionState persistence between execute() calls.
        final output = await ask(
          'Make exactly two calls to execute_python: '
          'first with code `x = 100`, then with code `x + 23`. '
          'Reply only with the result of the second call.',
        );
        print('  T3 → $output');
        expect(output, contains('123'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'T4: scriptingState transitions idle→executing→idle during tool call',
      () async {
        final states = <ScriptingState>[];
        final unsub = env.scriptingState.subscribe(states.add);
        addTearDown(unsub);

        await ask(
          'Use execute_python to compute 2 + 2. Reply with only the number.',
        );

        expect(
          states,
          containsAllInOrder([
            ScriptingState.idle,
            ScriptingState.executing,
            ScriptingState.idle,
          ]),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'T5: Dart event loop is not blocked during Python execution',
      () async {
        // Regression guard for the dart_monty background-thread guarantee.
        // dm.AgentSession.execute() offloads Python to a Dart Isolate (FFI)
        // or Web Worker (WASM) — the calling event loop must remain free.
        //
        // A Timer.periodic at 100ms fires on the Dart/JS event loop.
        // ask() takes ~20-60s total (LLM + Python + LLM).  If the event loop
        // were blocked for >100ms at any point, the heartbeat count would be
        // far below what a fully-free event loop would accumulate.
        var heartbeatCount = 0;
        final timer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => heartbeatCount++,
        );
        addTearDown(timer.cancel);

        final output = await ask(
          'Use execute_python to compute '
          'sum(i * i for i in range(5000000)). '
          'Reply only with the numeric result.',
        );
        print('  T5 → $output (heartbeats: $heartbeatCount)');

        // A 100ms heartbeat fires once per event-loop cycle. ask() takes at
        // least ~1s in any network environment.  Requiring >5 heartbeats means
        // the event loop ran at least 6 times — conclusive proof it was not
        // blocked. (A blocked isolate would deliver 0 heartbeats until after
        // execute() returned.)
        expect(
          heartbeatCount,
          greaterThan(5),
          reason: 'Event loop was starved — dart_monty may be blocking the '
              'calling thread instead of using a background Isolate/Worker',
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
