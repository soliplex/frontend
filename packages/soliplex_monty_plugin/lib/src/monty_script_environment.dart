import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart' as dm;
import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _log = LogManager.instance.getLogger('MontyScriptEnvironment');

// ---------------------------------------------------------------------------
// MontyScriptEnvironment
// ---------------------------------------------------------------------------

/// Concrete [ScriptEnvironment] backed by a `dm.AgentSession`.
///
/// Registers `MontyPlugin` host functions on the bridge, then projects
/// the bridge's schema registry to [ClientTool]s visible to the
/// server-side LLM. An `execute_python` tool is also exposed for
/// general-purpose Python scripting.
///
/// ```dart
/// final env = MontyScriptEnvironment(
///   plugins: [SoliplexPlugin(connections: {'demo': myConnection})],
/// );
/// ```
class MontyScriptEnvironment implements ScriptEnvironment {
  /// Creates a [MontyScriptEnvironment] with the given [plugins].
  ///
  /// Each plugin's host functions are registered on the dart_monty bridge
  /// and projected as direct [ClientTool]s so the server LLM can call
  /// them without going through Python.
  ///
  /// [os] is an optional OS provider for the Python interpreter.
  /// [executionTimeout] caps each `execute_python` call; defaults to 30 s.
  MontyScriptEnvironment({
    List<dm.MontyPlugin> plugins = const [],
    dm.OsProvider? os,
    Duration executionTimeout = const Duration(seconds: 30),
  })  : _plugins = List.unmodifiable(plugins),
        _montySession = dm.AgentSession(os: os),
        _executionTimeout = executionTimeout {
    _registerPlugins();
  }

  /// Creates a [MontyScriptEnvironment] with an explicit [session].
  ///
  /// Only for testing. Avoids loading the Python runtime.
  /// [plugins] can be provided to register host functions on the session.
  /// [executionTimeout] defaults to 2 s so tests don't wait 30 s on
  /// a hanging mock.
  @visibleForTesting
  MontyScriptEnvironment.forTest(
    dm.AgentSession session, {
    List<dm.MontyPlugin> plugins = const [],
    Duration executionTimeout = const Duration(seconds: 2),
  })  : _plugins = List.unmodifiable(plugins),
        _montySession = session,
        _executionTimeout = executionTimeout {
    _registerPlugins();
  }

  final List<dm.MontyPlugin> _plugins;
  final dm.AgentSession _montySession;

  final Signal<ScriptingState> _stateSignal = signal(ScriptingState.idle);
  bool _disposed = false;

  /// Maximum wall-clock time allowed for a single `execute_python` call.
  ///
  /// If `_montySession.execute()` does not return within this duration a
  /// [TimeoutException] is thrown and the mutex is released so subsequent
  /// calls can proceed.
  final Duration _executionTimeout;

  /// Direct handler lookup — avoids routing Dart invocations through Python.
  final Map<String, dm.HostFunctionHandler> _handlers = {};

  /// Serialises concurrent `execute()` calls on the dart_monty bridge.
  ///
  /// A single `AgentSession` owns one Python interpreter (Dart Isolate on FFI,
  /// Web Worker on WASM). Concurrent `execute()` calls on the same session
  /// interleave variable mutations inside that interpreter. The mutex ensures
  /// only one `execute()` runs at a time so Python state is never stomped by a
  /// racing call.
  final Mutex _executeMutex = Mutex();

  List<ClientTool>? _tools;

  @override
  List<ClientTool> get tools => _tools ??= [
        _buildRunScriptTool(),
        _buildReplPythonTool(),
        ..._montySession.schemas
            .where((s) => !s.name.startsWith('_'))
            .map(_projectToClientTool),
      ];

  @override
  ReadonlySignal<ScriptingState> get scriptingState => _stateSignal.readonly();

  @override
  Future<void> onAttach(AgentSession session) => Future.value();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSignal
      ..set(ScriptingState.disposed)
      ..dispose();
    // Drain the execute mutex before tearing down: any in-flight execute()
    // holds the mutex; we queue dispose behind it. Plugins are disposed after
    // the Python session so they outlive any in-flight Python calls.
    unawaited(
      _executeMutex.protect(() async {
        await _montySession.dispose();
        for (final plugin in _plugins) {
          await plugin.onDispose();
        }
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Plugin registration
  // ---------------------------------------------------------------------------

  void _registerPlugins() {
    for (final plugin in _plugins) {
      for (final fn in plugin.functions) {
        _handlers[fn.schema.name] = fn.handler;
        _montySession.register(fn);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ClientTool projection
  // ---------------------------------------------------------------------------

  /// Projects a [dm.HostFunctionSchema] to a [ClientTool] that invokes the
  /// registered Dart handler directly (no Python hop).
  ClientTool _projectToClientTool(dm.HostFunctionSchema schema) {
    return ClientTool(
      definition: Tool(
        name: schema.name,
        description: schema.description,
        parameters: Map<String, Object>.from(schema.toJsonSchema()),
      ),
      executor: (toolCall, context) async {
        if (_disposed) {
          throw StateError('MontyScriptEnvironment has been disposed');
        }
        if (context.cancelToken.isCancelled) return '';

        final rawArgs = toolCall.arguments;
        final args = rawArgs.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(rawArgs) as Map<String, dynamic>)
                .cast<String, Object?>();

        _stateSignal.set(ScriptingState.executing);
        try {
          final result = await _handlers[schema.name]!(args);

          return switch (result) {
            null => '',
            final String s => s,
            _ => jsonEncode(result),
          };
        } finally {
          if (!_disposed) _stateSignal.set(ScriptingState.idle);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Python tools
  // ---------------------------------------------------------------------------

  /// One-shot script execution.
  ///
  /// Use this when the task can be expressed as a complete, self-contained
  /// program. Write all logic in a single call; do not rely on variables
  /// from previous calls. The interpreter is shared with [_buildReplPythonTool]
  /// so prior state is technically accessible, but callers should treat each
  /// invocation as if the namespace were fresh.
  ClientTool _buildRunScriptTool() {
    return ClientTool(
      definition: const Tool(
        name: 'run_script',
        description:
            'Run a complete, self-contained Python script in a sandboxed '
            'interpreter. Write all logic — setup, computation, output — in '
            'one call. Do not rely on variables from previous calls. '
            'Returns combined print() output and the last-expression value. '
            'Sandbox limits: subscript unpacking is not supported '
            '(`a[i], a[j] = a[j], a[i]` raises SyntaxError). '
            'Use a temp variable instead: '
            '`tmp = a[i]; a[i] = a[j]; a[j] = tmp`.',
        parameters: {
          'type': 'object',
          'properties': {
            'code': {
              'type': 'string',
              'description': 'Complete Python script to run.',
            },
          },
          'required': ['code'],
        },
      ),
      executor: _executePython,
      requiresApproval: true,
    );
  }

  /// Persistent REPL — feed snippets to a live interpreter.
  ///
  /// Variables, functions, and imports from previous calls remain in scope.
  /// Use this for multi-step exploration where each step builds on the last
  /// (e.g. load data → transform → inspect → visualise).
  ClientTool _buildReplPythonTool() {
    return ClientTool(
      definition: const Tool(
        name: 'repl_python',
        description:
            'Feed a snippet to the persistent Python REPL. Variables and '
            'functions from previous calls are still in scope — use this for '
            'multi-step exploration where each step builds on the last. '
            'Returns combined print() output and the last-expression value. '
            'Sandbox limits: subscript unpacking is not supported '
            '(`a[i], a[j] = a[j], a[i]` raises SyntaxError). '
            'Use a temp variable instead: '
            '`tmp = a[i]; a[i] = a[j]; a[j] = tmp`.',
        parameters: {
          'type': 'object',
          'properties': {
            'code': {
              'type': 'string',
              'description': 'Python snippet to feed to the REPL.',
            },
          },
          'required': ['code'],
        },
      ),
      executor: _executePython,
      requiresApproval: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Startup validation
  // ---------------------------------------------------------------------------

  /// Runs a trivial Python expression to verify the interpreter is loaded.
  ///
  /// Executes `1 + 1` and checks the result equals `2`. Throws if the
  /// interpreter fails to start, times out, or returns an unexpected value.
  /// Call once at app startup (fire-and-forget or awaited) to detect broken
  /// runtime early.
  Future<void> probe() async {
    if (_disposed) throw StateError('MontyScriptEnvironment has been disposed');

    final result = await _executeMutex.protect(
      () => _montySession.execute('1 + 1').timeout(
            _executionTimeout,
            onTimeout: () => throw TimeoutException(
              'Python runtime probe timed out after $_executionTimeout',
              _executionTimeout,
            ),
          ),
    );

    final err = result.error;
    if (err != null) {
      throw Exception('Python runtime probe failed: ${err.message}');
    }
    final value = result.value.dartValue?.toString();
    if (value != '2') {
      throw Exception(
        'Python runtime probe returned unexpected value: $value',
      );
    }
  }

  Future<String> _executePython(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    if (_disposed) throw StateError('MontyScriptEnvironment has been disposed');

    final rawArgs = toolCall.arguments;
    final args = (rawArgs.isEmpty ? <String, dynamic>{} : jsonDecode(rawArgs))
        as Map<String, dynamic>;
    final code = args['code'] as String? ?? '';
    final callId = toolCall.id;

    _log.debug(
      '[$callId] python queued '
      '(mutex locked=${_executeMutex.isLocked})',
    );

    if (context.cancelToken.isCancelled) return '';

    _stateSignal.set(ScriptingState.executing);
    try {
      final result = await _executeMutex.protect(() {
        // Re-check after acquiring the mutex: dispose() may have been called
        // while this request was queued. Calling execute() on a disposed
        // dm.AgentSession is unsafe, so we bail out here instead.
        if (_disposed) {
          throw StateError('MontyScriptEnvironment has been disposed');
        }

        _log.debug(
          '[$callId] python mutex acquired, calling execute()',
        );
        return _montySession.execute(code).timeout(
              _executionTimeout,
              onTimeout: () => throw TimeoutException(
                'python timed out after $_executionTimeout',
                _executionTimeout,
              ),
            );
      });

      _log.debug(
        '[$callId] python completed '
        '(error=${result.error?.message}, '
        'printOutput=${result.printOutput})',
      );

      // Capture output before checking for errors so print() lines emitted
      // before a crash are included in the result.
      final printOut = result.printOutput;
      final returnVal = result.value.dartValue?.toString();
      if (printOut != null && printOut.isNotEmpty) {
        _log.debug('[$callId] Python print output: $printOut');
      }

      final pythonError = result.error;
      if (pythonError != null) {
        // Python-level error: return it as tool output rather than throwing.
        // Throwing would mark the tool as failed (status: failed), causing the
        // LLM to retry unconditionally. Returning it as output gives the LLM
        // the error message so it can decide whether to fix and retry, without
        // triggering the automatic retry that a failed-status tool causes.
        // Also include any print() output that occurred before the error.
        final errorMsg = 'Error: ${pythonError.message}';
        _log.debug('[$callId] Python error (returned as output): $errorMsg');
        final parts = [
          if (printOut != null && printOut.isNotEmpty) printOut,
          errorMsg,
        ];
        return parts.join('\n');
      }

      // Return print() output and/or the last-expression value.
      // When neither is present the code ran but produced no output (e.g.
      // arr.sort() returns None). Return "None" so the LLM knows execution
      // succeeded rather than seeing '' and retrying.
      final parts = [
        if (printOut != null && printOut.isNotEmpty) printOut,
        if (returnVal != null && returnVal.isNotEmpty) returnVal,
      ];
      return parts.isEmpty ? 'None' : parts.join('\n');
    } catch (e, st) {
      _log.warning(
        '[$callId] python threw: $e',
        error: e,
        stackTrace: st,
      );
      rethrow;
    } finally {
      _log.debug(
        '[$callId] python finally '
        '(disposed=$_disposed, mutex locked=${_executeMutex.isLocked})',
      );
      if (!_disposed) {
        _stateSignal.set(ScriptingState.idle);
      }
    }
  }
}
