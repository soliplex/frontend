import 'dart:async';

import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart' as dm;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _MockDmAgentSession extends Mock implements dm.AgentSession {}

class _MockAgentSession extends Mock implements AgentSession {}

class _StubCancelToken extends CancelToken {}

class _StubContext implements ToolExecutionContext {
  _StubContext({CancelToken? cancelToken})
      : cancelToken = cancelToken ?? _StubCancelToken();

  @override
  final CancelToken cancelToken;

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

const _zeroUsage = MontyResourceUsage(
  memoryBytesUsed: 0,
  timeElapsedMs: 0,
  stackDepthUsed: 0,
);

MontyResult _resultOf(MontyValue value) =>
    MontyResult(usage: _zeroUsage, value: value);

MontyResult _errorResult(String message) => MontyResult(
      usage: _zeroUsage,
      value: const MontyNull(),
      error: MontyException(message: message),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockDmAgentSession mockSession;
  late MontyScriptEnvironment env;

  setUp(() {
    mockSession = _MockDmAgentSession();
    when(() => mockSession.dispose()).thenAnswer((_) async {});
    env = MontyScriptEnvironment.forTest(mockSession);
  });

  tearDown(() => env.dispose());

  group('MontyScriptEnvironment', () {
    group('tools', () {
      test('exposes exactly one tool', () {
        expect(env.tools, hasLength(1));
      });

      test('tool name is execute_python', () {
        expect(env.tools.first.definition.name, equals('execute_python'));
      });

      test('tool has code parameter', () {
        final params =
            env.tools.first.definition.parameters as Map<String, dynamic>;
        final props = params['properties'] as Map<String, dynamic>;
        expect(props.keys, contains('code'));
      });

      test('tools list is stable across calls', () {
        expect(identical(env.tools, env.tools), isTrue);
      });
    });

    group('scriptingState', () {
      test('starts idle', () {
        expect(env.scriptingState.value, equals(ScriptingState.idle));
      });

      test('transitions to disposed after dispose', () {
        env.dispose();

        expect(env.scriptingState.value, equals(ScriptingState.disposed));
      });
    });

    group('onAttach', () {
      test('stores the agent session', () async {
        final session = _MockAgentSession();
        await env.onAttach(session);

        // dispose doesn't throw — session reference accepted
        env.dispose();
      });
    });

    group('dispose', () {
      test('sets state to disposed', () {
        env.dispose();

        expect(env.scriptingState.value, equals(ScriptingState.disposed));
      });

      test('is idempotent', () {
        env
          ..dispose()
          ..dispose(); // must not throw
      });

      test('calls dm.AgentSession.dispose() once', () {
        env
          ..dispose()
          ..dispose(); // second call must be no-op

        verify(() => mockSession.dispose()).called(1);
      });
    });

    group('execute_python tool', () {
      const toolCall = ToolCallInfo(
        id: 'tc-1',
        name: 'execute_python',
        arguments: r'{"code": "x = 42\nx"}',
      );

      test('returns string representation of value', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyInt(42)));

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, _StubContext());

        expect(result, equals('42'));
      });

      test('throws on Python error', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _errorResult('NameError: x'));

        final executor = env.tools.first.executor;
        expect(
          () => executor(toolCall, _StubContext()),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('NameError: x'),
            ),
          ),
        );
      });

      test('returns empty string when result is None', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyNull()));

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, _StubContext());

        expect(result, equals(''));
      });

      test('returns empty string on cancellation before execute', () async {
        final cancelledToken = CancelToken()..cancel('test');
        final ctx = _StubContext(cancelToken: cancelledToken);

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, ctx);

        expect(result, equals(''));
        verifyNever(() => mockSession.execute(any()));
      });

      test('transitions state idle → executing → idle', () async {
        final states = <ScriptingState>[];
        final sub = env.scriptingState.subscribe(states.add);

        when(() => mockSession.execute(any())).thenAnswer((_) async {
          // Capture state while executing
          states.add(env.scriptingState.value);
          return _resultOf(const MontyNull());
        });

        final executor = env.tools.first.executor;
        await executor(toolCall, _StubContext());

        sub(); // unsubscribe

        expect(
          states,
          containsAllInOrder([
            ScriptingState.idle, // initial subscribe emission
            ScriptingState.executing, // captured inside execute mock
            ScriptingState.idle, // restored in finally
          ]),
        );
      });

      test('restores idle even when execute throws', () async {
        when(() => mockSession.execute(any())).thenThrow(Exception('boom'));

        final executor = env.tools.first.executor;
        await expectLater(
          () => executor(toolCall, _StubContext()),
          throwsA(isA<Exception>()),
        );

        expect(env.scriptingState.value, equals(ScriptingState.idle));
      });

      test('handles empty arguments gracefully', () async {
        const emptyArgs = ToolCallInfo(
          id: 'tc-2',
          name: 'execute_python',
        );
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyNull()));

        final executor = env.tools.first.executor;
        final result = await executor(emptyArgs, _StubContext());

        expect(result, equals(''));
      });

      test('throws StateError when disposed', () async {
        env.dispose();

        final executor = env.tools.first.executor;
        expect(
          () => executor(toolCall, _StubContext()),
          throwsA(isA<StateError>()),
        );
      });

      test('does not restore idle when disposed during execute', () async {
        when(() => mockSession.execute(any())).thenAnswer((_) async {
          env.dispose(); // dispose mid-execution
          return _resultOf(const MontyNull());
        });

        final executor = env.tools.first.executor;
        await executor(
          const ToolCallInfo(
            id: 'tc-3',
            name: 'execute_python',
            arguments: '{"code": "pass"}',
          ),
          _StubContext(),
        );

        expect(env.scriptingState.value, equals(ScriptingState.disposed));
      });
    });
  });
}
