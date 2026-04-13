import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart' as dm;
import 'package:meta/meta.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_monty_plugin/src/soliplex_connection.dart';
import 'package:soliplex_monty_plugin/src/soliplex_plugin.dart';

/// Concrete [ScriptEnvironment] backed by a [dm.AgentSession].
///
/// Owns the Python interpreter via a sandboxed [dm.AgentSession] with a
/// [SoliplexPlugin]. Receives the parent [AgentSession] via [onAttach]
/// for event emission.
///
/// ```dart
/// final env = MontyScriptEnvironment(
///   connections: {'demo': myConnection},
/// );
/// ```
class MontyScriptEnvironment implements ScriptEnvironment {
  /// Creates a [MontyScriptEnvironment] with the given server [connections].
  ///
  /// [connections] are forwarded to an internal [SoliplexPlugin].
  /// [os] is an optional OS provider for the Python interpreter.
  ///
  /// Uses the default (shared) interpreter mode.
  MontyScriptEnvironment({
    required Map<String, SoliplexConnection> connections,
    dm.OsProvider? os,
  }) : _montySession = dm.AgentSession(
          os: os,
          plugins: [SoliplexPlugin(connections: connections)],
        );

  /// Creates a [MontyScriptEnvironment] with an explicit [session].
  ///
  /// Only for testing. Avoids loading the Python runtime.
  @visibleForTesting
  MontyScriptEnvironment.forTest(dm.AgentSession session)
      : _montySession = session;

  final dm.AgentSession _montySession;

  final Signal<ScriptingState> _stateSignal = signal(ScriptingState.idle);

  bool _disposed = false;

  late final List<ClientTool> _tools = [_buildExecutePythonTool()];

  @override
  List<ClientTool> get tools => _tools;

  @override
  ReadonlySignal<ScriptingState> get scriptingState => _stateSignal.readonly();

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSignal.set(ScriptingState.disposed);
    unawaited(_montySession.dispose());
  }

  // ---------------------------------------------------------------------------
  // Tool builder
  // ---------------------------------------------------------------------------

  ClientTool _buildExecutePythonTool() {
    return ClientTool(
      definition: const Tool(
        name: 'execute_python',
        description: 'Execute Python code in a sandboxed interpreter. '
            'Variables persist across calls. '
            'Returns the last expression value as a string.',
        parameters: {
          'type': 'object',
          'properties': {
            'code': {
              'type': 'string',
              'description': 'Python code to execute.',
            },
          },
          'required': ['code'],
        },
      ),
      executor: _executePython,
    );
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

    if (context.cancelToken.isCancelled) return '';

    _stateSignal.set(ScriptingState.executing);
    try {
      final result = await _montySession.execute(code);

      if (result.error != null) {
        throw Exception('Python error: ${result.error!.message}');
      }

      return result.value?.dartValue?.toString() ?? '';
    } finally {
      if (!_disposed) {
        _stateSignal.set(ScriptingState.idle);
      }
    }
  }
}
