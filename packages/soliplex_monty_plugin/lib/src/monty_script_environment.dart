import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart' as dm;
import 'package:dart_monty/dart_monty_bridge.dart'
    show HostFunction, HostFunctionSchema, HostParam, HostParamType;
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
    dm.OsCallHandler? os,
    Duration executionTimeout = const Duration(seconds: 30),
  })  : _tools = List.unmodifiable(tools),
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
    Duration executionTimeout = const Duration(seconds: 2),
  })  : _tools = List.unmodifiable(tools),
        _montySession = session,
        _executionTimeout = executionTimeout {
    _registerTools();
  }

  final List<SoliplexTool> _tools;
  final dm.AgentSession _montySession;

  final Signal<ScriptingState> _stateSignal = signal(ScriptingState.idle);
  bool _disposed = false;

  final Duration _executionTimeout;

  /// Serialises concurrent `execute()` calls on the dart_monty bridge.
  final Mutex _executeMutex = Mutex();

  List<ClientTool>? _clientTools;

  @override
  List<ClientTool> get tools => _clientTools ??= [
        _buildRunScriptTool(),
        _buildReplPythonTool(),
        ..._tools.map(_projectToClientTool),
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

  ClientTool _projectToClientTool(SoliplexTool tool) {
    return ClientTool(
      definition: Tool(
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters,
      ),
      executor: (toolCall, context) async {
        if (_disposed) {
          throw StateError('MontyScriptEnvironment has been disposed');
        }
        if (context.cancelToken.isCancelled) return '';

        final args = toolCall.arguments.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(toolCall.arguments) as Map<String, dynamic>)
                .cast<String, Object?>();

        _stateSignal.set(ScriptingState.executing);
        try {
          final result = await tool.handler(args);
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

  ClientTool _buildRunScriptTool() {
    return ClientTool(
      definition: const Tool(
        name: 'run_script',
        description:
            'Run a complete, self-contained Python script in a sandboxed '
            'interpreter. Write all logic in one call. Returns print() '
            'output and the last-expression value.\n\n'
            'LIMITATIONS (Monty subset of Python):\n'
            '- No tuple unpacking in for-loops. Use indexing instead: '
            '`for pair in items: a, b = pair[0], pair[1]`\n'
            '- No imports. Standard library unavailable.\n'
            '- No classes, generators, decorators, or async/await.\n'
            '- Arithmetic, lists, dicts, strings, if/else, for/while, '
            'functions (def), and closures all work.',
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
            '- No tuple unpacking in for-loops. Use indexing: '
            '`for pair in items: a, b = pair[0], pair[1]`\n'
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

      final printOut = result.printOutput;
      final returnVal = result.value.dartValue?.toString();

      final pythonError = result.error;
      if (pythonError != null) {
        final errorMsg = 'Error: ${pythonError.message}';
        _log.debug('[$callId] Python error (returned as output): $errorMsg');
        final parts = [
          if (printOut != null && printOut.isNotEmpty) printOut,
          errorMsg,
        ];
        return parts.join('\n');
      }

      final parts = [
        if (printOut != null && printOut.isNotEmpty) printOut,
        if (returnVal != null && returnVal.isNotEmpty) returnVal,
      ];
      return parts.isEmpty ? 'None' : parts.join('\n');
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
