// Integration tests — print is intentional for live-test output.
// ignore_for_file: avoid_print
@Tags(['integration'])
library;

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
      final innerConn = _conn('inner');
      runtime = _runtime(
        extensionFactory: wrapScriptEnvironmentFactory(
          () async => MontyScriptEnvironment(
            connections: {
              'demo': SoliplexConnection.fromServerConnection(innerConn),
            },
          ),
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
      'T1: Soliplex host functions appear in server LLM tool list',
      () async {
        final output = await ask(
          'List every tool name you have access to. '
          'Reply with only a comma-separated list of tool names.',
        );
        print('  T1 → $output');
        expect(output, contains('soliplex_new_thread'));
        expect(output, contains('soliplex_list_rooms'));
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
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Stateful — single MontyScriptEnvironment shared across sessions.
  //
  // extensionFactory always returns a ScriptEnvironmentExtension wrapping
  // the same env instance.  autoDispose: false so onDispose() is not called
  // between tests — only when tearDownAll disposes the runtime.  Multiple
  // extensions wrapping the same env all call env.dispose() at teardown,
  // which is safe because MontyScriptEnvironment.dispose() is idempotent.
  // ──────────────────────────────────────────────────────────────────────────

  group('stateful (persistent Python interpreter)', () {
    late AgentRuntime runtime;
    late MontyScriptEnvironment env;

    setUpAll(() {
      env = MontyScriptEnvironment(
        connections: {
          'demo': SoliplexConnection.fromServerConnection(_conn('inner')),
        },
      );
      runtime = _runtime(
        extensionFactory: wrapScriptEnvironmentFactory(() async => env),
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
  });
}
