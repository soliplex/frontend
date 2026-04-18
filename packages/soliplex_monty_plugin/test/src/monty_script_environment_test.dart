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

MontyResult _resultWithPrint(MontyValue value, String printOutput) =>
    MontyResult(usage: _zeroUsage, value: value, printOutput: printOutput);

MontyResult _errorResult(String message) => MontyResult(
      usage: _zeroUsage,
      value: const MontyNull(),
      error: MontyException(message: message),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Reused across multiple groups.
const toolCall = ToolCallInfo(
  id: 'tc-1',
  name: 'execute_python',
  arguments: r'{"code": "x = 42\nx"}',
);

void main() {
  late _MockDmAgentSession mockSession;
  late MontyScriptEnvironment env;

  setUp(() {
    mockSession = _MockDmAgentSession();
    when(() => mockSession.dispose()).thenAnswer((_) async {});
    // schemas is accessed when _tools is first read; return empty list so
    // the test env exposes only the execute_python tool.
    when(() => mockSession.schemas).thenReturn([]);
    env = MontyScriptEnvironment.forTest(mockSession);
  });

  tearDown(() => env.dispose());

  group('MontyScriptEnvironment', () {
    group('tools', () {
      test('exposes run_script and repl_python tools', () {
        expect(env.tools, hasLength(2));
        final names = env.tools.map((t) => t.definition.name).toList();
        expect(names, containsAll(['run_script', 'repl_python']));
      });

      test('each tool has code parameter', () {
        for (final tool in env.tools) {
          final params = tool.definition.parameters as Map<String, dynamic>;
          final props = params['properties'] as Map<String, dynamic>;
          expect(
            props.keys,
            contains('code'),
            reason: '${tool.definition.name} missing code param',
          );
        }
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

      test('calls dm.AgentSession.dispose() once', () async {
        env
          ..dispose()
          ..dispose(); // second call must be no-op

        // The drain is scheduled via _executeMutex.protect — pump the
        // event loop so it runs before we verify.
        await Future<void>.delayed(Duration.zero);
        verify(() => mockSession.dispose()).called(1);
      });
    });

    group('execute_python tool', () {
      test('returns string representation of value', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyInt(42)));

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, _StubContext());

        expect(result, equals('42'));
      });

      test('returns error string on Python error (does not throw)', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _errorResult('NameError: x'));

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, _StubContext());

        // Python errors are returned as output, not thrown — throwing would
        // set status:failed and cause the LLM to retry unconditionally.
        expect(result, contains('Error:'));
        expect(result, contains('NameError: x'));
      });

      test('Python error with prior print output includes both', () async {
        when(() => mockSession.execute(any())).thenAnswer(
          (_) async => const MontyResult(
            usage: _zeroUsage,
            value: MontyNull(),
            printOutput: 'step 1 done',
            error: MontyException(message: 'ZeroDivisionError'),
          ),
        );

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, _StubContext());

        expect(result, contains('step 1 done'));
        expect(result, contains('ZeroDivisionError'));
      });

      test('returns "None" when result is None and no print output', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyNull()));

        final executor = env.tools.first.executor;
        final result = await executor(toolCall, _StubContext());

        // None return with no print output → "None" so the LLM knows the
        // call succeeded (e.g. arr.sort()) rather than seeing '' and retrying.
        expect(result, equals('None'));
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

        expect(result, equals('None'));
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

    // -------------------------------------------------------------------------
    // Timeout
    //
    // Will FAIL until _executePython wraps execute() with Future.timeout().
    // -------------------------------------------------------------------------

    group('timeout', () {
      // Uses a short timeout env so tests don't wait 30 s.
      late _MockDmAgentSession timeoutMock;
      late MontyScriptEnvironment timeoutEnv;

      setUp(() {
        timeoutMock = _MockDmAgentSession();
        when(() => timeoutMock.dispose()).thenAnswer((_) async {});
        when(() => timeoutMock.schemas).thenReturn([]);
        timeoutEnv = MontyScriptEnvironment.forTest(
          timeoutMock,
          executionTimeout: const Duration(milliseconds: 500),
        );
      });

      tearDown(() => timeoutEnv.dispose());

      test(
        'throws TimeoutException when execute never completes',
        () async {
          when(() => timeoutMock.execute(any()))
              .thenAnswer((_) => Completer<MontyResult>().future);

          await expectLater(
            () => timeoutEnv.tools.first.executor(toolCall, _StubContext()),
            throwsA(isA<TimeoutException>()),
          );
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test(
        'restores idle state after timeout',
        () async {
          when(() => timeoutMock.execute(any()))
              .thenAnswer((_) => Completer<MontyResult>().future);

          await expectLater(
            () => timeoutEnv.tools.first.executor(toolCall, _StubContext()),
            throwsA(isA<TimeoutException>()),
          );

          expect(
            timeoutEnv.scriptingState.value,
            equals(ScriptingState.idle),
          );
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test(
        'second call succeeds after first times out',
        () async {
          // Ensures the mutex is released on timeout — not left locked.
          var callCount = 0;
          when(() => timeoutMock.execute(any())).thenAnswer((_) async {
            callCount++;
            if (callCount == 1) {
              return Completer<MontyResult>().future; // hangs
            }
            return _resultOf(const MontyInt(99));
          });

          await expectLater(
            () => timeoutEnv.tools.first.executor(toolCall, _StubContext()),
            throwsA(isA<TimeoutException>()),
          );

          final result = await timeoutEnv.tools.first.executor(
            toolCall,
            _StubContext(),
          );
          expect(result, equals('99'));
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );
    });

    // -------------------------------------------------------------------------
    // Concurrency — validates that the Mutex serialises concurrent execute()
    // calls and that exceptions/timeouts don't leave the mutex locked.
    // -------------------------------------------------------------------------

    group('concurrency', () {
      test('serialises concurrent execute() calls', () async {
        final callOrder = <String>[];

        when(() => mockSession.execute(any())).thenAnswer((_) async {
          callOrder.add('start');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          callOrder.add('end');
          return _resultOf(const MontyNull());
        });

        await Future.wait([
          env.tools.first.executor(toolCall, _StubContext()),
          env.tools.first.executor(toolCall, _StubContext()),
        ]);

        // Serialised: start, end, start, end (not start, start, end, end).
        expect(callOrder, hasLength(4));
        expect(callOrder[0], equals('start'));
        expect(callOrder[1], equals('end'));
        expect(callOrder[2], equals('start'));
        expect(callOrder[3], equals('end'));
      });

      test('exception in first call does not prevent second', () async {
        var callCount = 0;
        when(() => mockSession.execute(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) throw Exception('first call failed');
          return _resultOf(const MontyInt(42));
        });

        await expectLater(
          () => env.tools.first.executor(toolCall, _StubContext()),
          throwsA(isA<Exception>()),
        );

        final result = await env.tools.first.executor(toolCall, _StubContext());
        expect(result, equals('42'));
      });

      test('state returns to idle after each serialised call', () async {
        final states = <ScriptingState>[];
        final sub = env.scriptingState.subscribe(states.add);
        addTearDown(sub);

        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyNull()));

        await env.tools.first.executor(toolCall, _StubContext());
        await env.tools.first.executor(toolCall, _StubContext());

        // idle(initial), executing, idle, executing, idle
        expect(
          states,
          containsAllInOrder([
            ScriptingState.idle,
            ScriptingState.executing,
            ScriptingState.idle,
            ScriptingState.executing,
            ScriptingState.idle,
          ]),
        );
      });
    });

    // -------------------------------------------------------------------------
    // Dispose safety
    //
    // Will FAIL until dispose() drains _executeMutex before calling
    // _montySession.dispose(), and _executePython re-checks _disposed inside
    // the protected block.
    // -------------------------------------------------------------------------

    group('dispose safety', () {
      test(
        'waits for in-flight execute before calling session dispose',
        () async {
          final executeStarted = Completer<void>();
          final executeLatch = Completer<MontyResult>();
          final disposeCompleted = Completer<void>();

          when(() => mockSession.execute(any())).thenAnswer((_) async {
            executeStarted.complete();
            return executeLatch.future;
          });
          when(() => mockSession.dispose()).thenAnswer((_) async {
            disposeCompleted.complete();
          });

          // Start execute — it will block at executeLatch.
          final firstFuture =
              env.tools.first.executor(toolCall, _StubContext());
          await executeStarted.future;

          // Call dispose while execute is in flight.
          env.dispose();

          // session.dispose() must NOT have been called yet.
          verifyNever(() => mockSession.dispose());

          // Release the in-flight execute.
          executeLatch.complete(_resultOf(const MontyNull()));
          await firstFuture;

          // Now the drain should have run.
          await disposeCompleted.future;
          verify(() => mockSession.dispose()).called(1);
        },
      );

      test(
        'calls queued while dispose is pending throw StateError',
        () async {
          final executeStarted = Completer<void>();
          final executeLatch = Completer<MontyResult>();
          final disposeCompleted = Completer<void>();

          when(() => mockSession.execute(any())).thenAnswer((_) async {
            executeStarted.complete();
            return executeLatch.future;
          });
          when(() => mockSession.dispose()).thenAnswer((_) async {
            disposeCompleted.complete();
          });

          // First call holds the mutex.
          final firstFuture =
              env.tools.first.executor(toolCall, _StubContext());
          await executeStarted.future;

          // Second call is queued behind the mutex.
          final secondFuture =
              env.tools.first.executor(toolCall, _StubContext());

          // dispose() queues the drain after the second call.
          env.dispose();

          // Release first — second acquires mutex, must see _disposed=true.
          executeLatch.complete(_resultOf(const MontyNull()));
          await firstFuture;

          // Second call must be rejected.
          await expectLater(secondFuture, throwsA(isA<StateError>()));
          await disposeCompleted.future;
        },
      );
    });

    // -------------------------------------------------------------------------
    // Output formatting
    //
    // execute_python combines printOutput + return value so the LLM always
    // sees the full result. Missing either must not cause the LLM to retry.
    // -------------------------------------------------------------------------

    group('output formatting', () {
      test('print-only: returns print output when value is None', () async {
        when(() => mockSession.execute(any())).thenAnswer(
          (_) async =>
              _resultWithPrint(const MontyNull(), '[1, 2, 3]'),
        );

        final result =
            await env.tools.first.executor(toolCall, _StubContext());

        expect(result, equals('[1, 2, 3]'));
      });

      test('value-only: returns value when no print output', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyInt(42)));

        final result =
            await env.tools.first.executor(toolCall, _StubContext());

        expect(result, equals('42'));
      });

      test(
        'both: combines print output and value with newline',
        () async {
          when(() => mockSession.execute(any())).thenAnswer(
            (_) async => _resultWithPrint(const MontyInt(6), 'step done'),
          );

          final result =
              await env.tools.first.executor(toolCall, _StubContext());

          expect(result, equals('step done\n6'));
        },
      );

      test(
        'neither: returns "None" so LLM knows call succeeded',
        () async {
          // Simulates arr.sort() — in-place, returns None, no print.
          when(() => mockSession.execute(any()))
              .thenAnswer((_) async => _resultOf(const MontyNull()));

          final result =
              await env.tools.first.executor(toolCall, _StubContext());

          expect(result, equals('None'));
        },
      );

      test('empty print output is treated as absent', () async {
        when(() => mockSession.execute(any())).thenAnswer(
          (_) async => _resultWithPrint(const MontyNull(), ''),
        );

        final result =
            await env.tools.first.executor(toolCall, _StubContext());

        // Empty printOutput → falls through to None.
        expect(result, equals('None'));
      });
    });

    // -------------------------------------------------------------------------
    // State persistence across runs
    //
    // The Python interpreter is shared across all execute_python calls within
    // the same MontyScriptEnvironment. Variables assigned in one call are
    // visible in subsequent calls.
    // -------------------------------------------------------------------------

    group('state persistence across runs', () {
      test('variable set in first call is visible in second', () async {
        var callCount = 0;
        when(() => mockSession.execute(any())).thenAnswer((_) async {
          callCount++;
          // Simulates: first call sets x=10 (returns None), second reads it.
          return callCount == 1
              ? _resultOf(const MontyNull())
              : _resultOf(const MontyInt(10));
        });

        const setCall = ToolCallInfo(
          id: 'tc-set',
          name: 'execute_python',
          arguments: '{"code": "x = 10"}',
        );
        const getCall = ToolCallInfo(
          id: 'tc-get',
          name: 'execute_python',
          arguments: '{"code": "x"}',
        );

        await env.tools.first.executor(setCall, _StubContext());
        final result =
            await env.tools.first.executor(getCall, _StubContext());

        expect(result, equals('10'));
        expect(callCount, equals(2));
      });

      test('both calls go to the same dm.AgentSession', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyNull()));

        await env.tools.first.executor(toolCall, _StubContext());
        await env.tools.first.executor(toolCall, _StubContext());

        // Same session used for both — not two separate interpreters.
        verify(() => mockSession.execute(any())).called(2);
      });
    });

    // -------------------------------------------------------------------------
    // Isolation — deterministic unit-test replacement for the LLM-mediated T7.
    // -------------------------------------------------------------------------

    group('isolation', () {
      test('two environments have independent Python state', () async {
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyInt(7777)));

        const markerCall = ToolCallInfo(
          id: 'tc-7a',
          name: 'execute_python',
          arguments: r'{"code": "isolation_marker = 7777\nisolation_marker"}',
        );
        final result1 =
            await env.tools.first.executor(markerCall, _StubContext());
        expect(result1, equals('7777'));

        // env2 is a completely independent environment.
        final mock2 = _MockDmAgentSession();
        when(mock2.dispose).thenAnswer((_) async {});
        when(() => mock2.schemas).thenReturn([]);
        // Its session has no knowledge of isolation_marker.
        when(() => mock2.execute(any()))
            .thenAnswer((_) async => _resultOf(const MontyString('absent')));
        final env2 = MontyScriptEnvironment.forTest(mock2);
        addTearDown(env2.dispose);

        const checkCall = ToolCallInfo(
          id: 'tc-7b',
          name: 'execute_python',
          arguments: '''{"code": "vars().get('isolation_marker', 'absent')"}''',
        );
        final result2 =
            await env2.tools.first.executor(checkCall, _StubContext());

        expect(result2, isNot(contains('7777')));
        expect(result2, equals('absent'));
      });
    });

    // -------------------------------------------------------------------------
    // Corner cases
    // -------------------------------------------------------------------------

    group('corner cases', () {
      test('handles large string result without truncation', () async {
        final largeStr = 'x' * 10000;
        when(() => mockSession.execute(any()))
            .thenAnswer((_) async => _resultOf(MontyString(largeStr)));

        final result = await env.tools.first.executor(toolCall, _StubContext());

        expect(result.length, equals(10000));
        expect(result, equals(largeStr));
      });

      test('missing code key defaults to empty string', () async {
        const noCode = ToolCallInfo(
          id: 'tc-nc',
          name: 'execute_python',
          arguments: '{"not_code": "irrelevant"}',
        );
        when(() => mockSession.execute('')).thenAnswer(
          (_) async => _resultOf(const MontyNull()),
        );

        final result = await env.tools.first.executor(noCode, _StubContext());

        expect(result, equals('None'));
        verify(() => mockSession.execute('')).called(1);
      });

      test(
        'mid-flight cancel is not observed — documents current design',
        () async {
          // Cancellation is only checked once, before the mutex.
          // An execute() in progress runs to completion even if the token
          // is cancelled partway through.
          final cancelToken = CancelToken();
          final ctx = _StubContext(cancelToken: cancelToken);

          when(() => mockSession.execute(any())).thenAnswer((_) async {
            cancelToken.cancel('cancelled mid-flight');
            return _resultOf(const MontyInt(1));
          });

          final result = await env.tools.first.executor(toolCall, ctx);

          // Result is returned, not ''. Mid-flight cancel is intentionally
          // ignored — the Python execution is already in the background thread.
          expect(result, equals('1'));
        },
      );
    });
  });
}
