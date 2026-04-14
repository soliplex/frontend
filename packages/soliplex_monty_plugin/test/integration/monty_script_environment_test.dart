// Integration tests — require the dart_monty Python runtime (FFI or WASM).
// Run with:
//   dart test test/integration/monty_script_environment_test.dart -p vm
//   dart test test/integration/monty_script_environment_test.dart -p chrome
@Tags(['monty'])
library;

import 'dart:convert';

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
    env = MontyScriptEnvironment();
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

    test(
      'execute_python error messages must not leak Rust interpreter internals',
      () async {
        // Bubble sort uses subscript tuple-swap:
        //   arr[j], arr[j+1] = arr[j+1], arr[j]
        // Monty does not support subscript targets in tuple unpacking.
        // The error must be a Python-level SyntaxError, NOT a raw Rust
        // Debug dump leaking ExprSubscript, NodeIndex, etc.
        final code = jsonEncode({
          'code': 'def bubble_sort(arr):\n'
              '    n = len(arr)\n'
              '    for i in range(n):\n'
              '        for j in range(0, n-i-1):\n'
              '            if arr[j] > arr[j+1]:\n'
              '                arr[j], arr[j+1] = arr[j+1], arr[j]\n'
              '    return arr\n'
              '\n'
              'bubble_sort([3, 1, 2])',
        });

        await expectLater(
          () => env.tools.first.executor(
            ToolCallInfo(id: 'tc-5', name: 'execute_python', arguments: code),
            _StubContext(),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'error message must be human-readable, not Rust Debug output',
              allOf([
                contains('Python error'),
                isNot(contains('NodeIndex')),
                isNot(contains('ExprSubscript')),
                isNot(contains('ExprName')),
                isNot(contains('node_index:')),
              ]),
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
