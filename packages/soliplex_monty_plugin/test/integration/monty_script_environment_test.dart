// Integration tests — require the dart_monty Python runtime (FFI or WASM).
// Run with:
//   dart test test/integration/monty_script_environment_test.dart -p vm
//   dart test test/integration/monty_script_environment_test.dart -p chrome
@Tags(['monty'])
library;

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Stub context — no live Soliplex server needed.
// ---------------------------------------------------------------------------

class _StubContext implements ToolExecutionContext {
  @override
  CancelToken get cancelToken => CancelToken();

  @override
  Future<AgentSession> spawnChild({required String prompt, String? roomId}) =>
      throw UnimplementedError();

  @override
  void emitEvent(ExecutionEvent event) {}

  @override
  T? getExtension<T extends SessionExtension>() => null;

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async =>
      true;

  @override
  Future<String> delegateTask({
    required String prompt,
    String? roomId,
    Duration? timeout,
  }) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MontyScriptEnvironment env;

  setUp(() {
    env = MontyScriptEnvironment(connections: {});
  });

  tearDown(() => env.dispose());

  group('MontyScriptEnvironment integration', () {
    test(
      'execute_python returns result of last expression',
      () async {
        final executor = env.tools.first.executor;

        final result = await executor(
          const ToolCallInfo(
            id: 'tc-1',
            name: 'execute_python',
            arguments: r'{"code": "x = 42\nx"}',
          ),
          _StubContext(),
        );

        expect(result, equals('42'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'execute_python returns empty string for None',
      () async {
        final executor = env.tools.first.executor;

        final result = await executor(
          const ToolCallInfo(
            id: 'tc-2',
            name: 'execute_python',
            arguments: '{"code": "x = 1"}',
          ),
          _StubContext(),
        );

        expect(result, equals(''));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'scriptingState transitions idle → executing → idle',
      () async {
        final states = <ScriptingState>[];
        final sub = env.scriptingState.subscribe(states.add);
        addTearDown(sub);

        final executor = env.tools.first.executor;
        await executor(
          const ToolCallInfo(
            id: 'tc-3',
            name: 'execute_python',
            arguments: '{"code": "1 + 1"}',
          ),
          _StubContext(),
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
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'execute_python propagates Python errors as exceptions',
      () async {
        final executor = env.tools.first.executor;

        await expectLater(
          () => executor(
            const ToolCallInfo(
              id: 'tc-4',
              name: 'execute_python',
              arguments: r'{"code": "raise ValueError(\"test error\")"}',
            ),
            _StubContext(),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Python error'),
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
