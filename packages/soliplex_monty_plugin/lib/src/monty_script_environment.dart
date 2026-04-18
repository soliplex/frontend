import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart' as dm;
import 'package:dart_monty/dart_monty_bridge.dart'
    show
        HostFunction,
        HostFunctionSchema,
        HostParam,
        HostParamType,
        MontyPlugin;
import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_monty_plugin/src/soliplex_tool.dart';

final Logger _log = LogManager.instance.getLogger('MontyScriptEnvironment');

/// Concrete [ScriptEnvironment] backed by a `dm.AgentSession`.
///
/// Registers each [SoliplexTool] as a `HostFunction` on the dart_monty bridge
/// and also projects them as [ClientTool]s for the server-side LLM.
class MontyScriptEnvironment implements ScriptEnvironment {
  /// Creates a [MontyScriptEnvironment] with the given [tools].
  ///
  /// [os] is an optional OS call handler for the Python interpreter.
  /// [executionTimeout] caps each Python execution; defaults to 30 s.
  MontyScriptEnvironment({
    required List<SoliplexTool> tools,
    List<MontyPlugin> plugins = const [],
    dm.OsCallHandler? os,
    Duration executionTimeout = const Duration(seconds: 30),
  })  : _tools = List.unmodifiable(tools),
        _plugins = List.unmodifiable(plugins),
        _montySession = dm.AgentSession(os: os),
        _executionTimeout = executionTimeout {
    _registerTools();
  }

  /// Creates a [MontyScriptEnvironment] with an explicit [session].
  ///
  /// Only for testing. Avoids loading the Python runtime.
  @visibleForTesting
  MontyScriptEnvironment.forTest(
    dm.AgentSession session, {
    List<SoliplexTool> tools = const [],
    List<MontyPlugin> plugins = const [],
    Duration executionTimeout = const Duration(seconds: 2),
  })  : _tools = List.unmodifiable(tools),
        _plugins = List.unmodifiable(plugins),
        _montySession = session,
        _executionTimeout = executionTimeout {
    _registerTools();
  }

  final List<SoliplexTool> _tools;
  final List<MontyPlugin> _plugins;
  final dm.AgentSession _montySession;

  final Signal<ScriptingState> _stateSignal = signal(ScriptingState.idle);
  bool _disposed = false;

  final Duration _executionTimeout;

  /// Serialises concurrent `execute()` calls on the dart_monty bridge.
  final Mutex _executeMutex = Mutex();

  @override
  List<ClientTool> get tools => [
        _buildExecutePythonTool(),
        _buildReplPythonTool(),
      ];

  /// Executes Python [code] directly in the interpreter.
  ///
  /// Serialised by the internal mutex — safe to call concurrently.
  Future<dm.MontyResult> execute(String code) async {
    if (_disposed) throw StateError('MontyScriptEnvironment has been disposed');
    return _executeMutex.protect(() {
      if (_disposed) {
        throw StateError('MontyScriptEnvironment has been disposed');
      }
      return _montySession.execute(code).timeout(_executionTimeout);
    });
  }

  /// Executes Python [code] and returns a formatted output string.
  ///
  /// Combines print output and the last-expression value. Python errors are
  /// returned as `Error: …` strings rather than thrown. Sets [scriptingState]
  /// to [ScriptingState.executing] for the duration of the call.
  Future<String> executeFormatted(String code) async {
    if (_disposed) throw StateError('MontyScriptEnvironment has been disposed');
    _stateSignal.set(ScriptingState.executing);
    try {
      final result = await _executeMutex.protect(() {
        if (_disposed) {
          throw StateError('MontyScriptEnvironment has been disposed');
        }
        return _montySession.execute(code).timeout(_executionTimeout);
      });
      return _formatResult(result);
    } on TimeoutException {
      return 'Error: Python execution timed out after $_executionTimeout';
    } finally {
      if (!_disposed) _stateSignal.set(ScriptingState.idle);
    }
  }

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
    for (final plugin in _plugins) {
      unawaited(plugin.onDispose());
    }
    unawaited(
      _executeMutex.protect(() async {
        await _montySession.dispose();
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Tool registration
  // ---------------------------------------------------------------------------

  void _registerTools() {
    for (final tool in _tools) {
      _montySession.register(_toHostFunction(tool));
    }
    // Plugins register their host functions directly. PluginRegistry lifecycle
    // (onRegister, sibling lookups) is not used here — plugins must not call
    // sibling() or access registry in their handlers.
    for (final plugin in _plugins) {
      plugin.functions.forEach(_montySession.register);
    }
  }

  HostFunction _toHostFunction(SoliplexTool tool) {
    final props = tool.parameters['properties'] as Map<String, dynamic>? ?? {};
    final required = (tool.parameters['required'] as List<dynamic>? ?? [])
        .cast<String>()
        .toSet();
    return HostFunction(
      schema: HostFunctionSchema(
        name: tool.name,
        description: tool.description,
        params: props.entries.map((e) {
          final s = e.value as Map<String, dynamic>? ?? {};
          return HostParam(
            name: e.key,
            type: _jsonTypeToHostParamType(s['type'] as String?),
            isRequired: required.contains(e.key),
            description: s['description'] as String?,
          );
        }).toList(),
      ),
      handler: tool.handler,
    );
  }

  static HostParamType _jsonTypeToHostParamType(String? type) => switch (type) {
        'string' => HostParamType.string,
        'integer' => HostParamType.integer,
        'number' => HostParamType.number,
        'boolean' => HostParamType.boolean,
        'array' => HostParamType.list,
        'object' => HostParamType.map,
        _ => HostParamType.any,
      };

  // ---------------------------------------------------------------------------
  // ClientTool projection
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Python tools
  // ---------------------------------------------------------------------------

  ClientTool _buildExecutePythonTool() {
    return ClientTool(
      definition: const Tool(
        name: 'execute_python',
        description:
            'Run a Python snippet in the persistent REPL. Variables, '
            'functions, and state from previous calls remain in scope. '
            'Returns print() output and the last-expression value.\n\n'
            'LIMITATIONS (Monty subset of Python):\n'
            '- Every if/else/for/while block must have a body. '
            'Use `pass` for intentionally empty blocks.\n'
            '- No chained assignment: write `a=0; b=0` not `a=b=0`.\n'
            '- No str.format() or %% formatting. Use f-strings: '
            '`f"value={x}"`.\n'
            '- No imports. Standard library unavailable.\n'
            '- No classes, generators, decorators, or async/await.\n'
            '- Everything else works: f-strings, list/dict comprehensions, '
            'lambda, try/except, tuple unpacking, zip, sorted, sum, '
            'min, max, abs, int(), str(), split(), append(), etc.',
        parameters: {
          'type': 'object',
          'properties': {
            'code': {'type': 'string', 'description': 'Python script to run.'},
          },
          'required': ['code'],
        },
      ),
      executor: _executePython,
    );
  }

  ClientTool _buildReplPythonTool() {
    return ClientTool(
      definition: const Tool(
        name: 'repl_python',
        description:
            'Feed a snippet to the persistent Python REPL. Variables from '
            'previous calls remain in scope.\n\n'
            'LIMITATIONS (Monty subset of Python):\n'
            '- Every block must have a body (use pass if needed).\n'
            '- No chained assignment (`a=b=0`). '
            'No str.format()/%%—use f-strings.\n'
            '- No imports. No classes, generators, decorators, async/await.',
        parameters: {
          'type': 'object',
          'properties': {
            'code': {'type': 'string', 'description': 'Python snippet.'},
          },
          'required': ['code'],
        },
      ),
      executor: _executePython,
    );
  }

  // ---------------------------------------------------------------------------
  // Startup validation
  // ---------------------------------------------------------------------------

  /// Runs a trivial Python expression to verify the interpreter is loaded.
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

    if (context.cancelToken.isCancelled) return '';

    _stateSignal.set(ScriptingState.executing);
    try {
      final result = await _executeMutex.protect(() {
        if (_disposed) {
          throw StateError('MontyScriptEnvironment has been disposed');
        }
        return _montySession.execute(code).timeout(_executionTimeout);
      });

      if (result.error != null) {
        _log.debug('[$callId] Python error (returned as output): '
            '${result.error!.message}');
      }
      return _formatResult(result);
    } on TimeoutException {
      return 'Error: Python execution timed out after $_executionTimeout';
    } catch (e, st) {
      _log.warning('[$callId] Python threw: $e', error: e, stackTrace: st);
      rethrow;
    } finally {
      if (!_disposed) {
        _stateSignal.set(ScriptingState.idle);
      }
    }
  }

  static String _formatResult(dm.MontyResult result) {
    final printOut = result.printOutput;
    final returnVal = result.value.dartValue?.toString();
    final pythonError = result.error;
    if (pythonError != null) {
      final parts = [
        if (printOut != null && printOut.isNotEmpty) printOut,
        'Error: ${pythonError.message}',
      ];
      return parts.join('\n');
    }
    final parts = [
      if (printOut != null && printOut.isNotEmpty) printOut,
      if (returnVal != null && returnVal.isNotEmpty) returnVal,
    ];
    return parts.isEmpty ? 'None' : parts.join('\n');
  }
}

/// A [ScriptEnvironment] decorator that filters the visible tools list.
class ToolFilteredEnvironment implements ScriptEnvironment {
  /// Creates a [ToolFilteredEnvironment] wrapping the given environment.
  ToolFilteredEnvironment(
    this._env, {
    required Set<String> allowedTools,
  }) : _allowedTools = allowedTools;

  final ScriptEnvironment _env;
  final Set<String> _allowedTools;

  @override
  List<ClientTool> get tools => _env.tools
      .where((t) => _allowedTools.contains(t.definition.name))
      .toList();

  @override
  ReadonlySignal<ScriptingState> get scriptingState => _env.scriptingState;

  @override
  Future<void> onAttach(AgentSession session) => _env.onAttach(session);

  @override
  void dispose() => _env.dispose();
}
