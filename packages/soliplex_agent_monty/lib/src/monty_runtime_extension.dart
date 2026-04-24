import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart' show MontyRuntime;
import 'package:dart_monty/dart_monty_bridge.dart' show ExtensionCoordinator;
import 'package:soliplex_agent/soliplex_agent.dart';
// ToolExecutionContext is not re-exported from soliplex_agent's public
// barrel; reach into src/ for the type annotation.
// ignore: implementation_imports
import 'package:soliplex_agent/src/tools/tool_execution_context.dart'
    show ToolExecutionContext;
import 'package:soliplex_agent_monty/src/monty_extension_set.dart';

/// Bridges a [MontyRuntime] into a soliplex [AgentSession].
///
/// Lifecycle:
/// - [onAttach] constructs the runtime with [MontyExtensionSet]'s
///   extensions, then subscribes to the inner
///   [ExtensionCoordinator.statefulObservations] and fans each
///   `(namespace, signal)` into the outer [state] map.
/// - [tools] exposes one [ClientTool] — `run_python_on_device` — that
///   runs arbitrary Python code via `runtime.execute(code)` and
///   returns `{value, output, error}` as a JSON string.
/// - [onDispose] cancels all subscriptions and disposes the runtime.
///
/// The [Signal] owned here is NOT the runtime's signal; it's an
/// aggregated map of every inner extension's current state, so the
/// debug panel / other consumers can observe everything through one
/// signal.
class MontyRuntimeExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, Object?>> {
  MontyRuntimeExtension({required MontyExtensionSet extensions})
      : _extensions = extensions {
    setInitialState(const <String, Object?>{});
  }

  final MontyExtensionSet _extensions;
  MontyRuntime? _runtime;
  final List<void Function()> _unsubs = [];

  @override
  String get namespace => 'monty';

  @override
  int get priority => 0;

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'run_python_on_device',
          description: "Runs Python on the user's device inside an embedded "
              'dart_monty interpreter. Use for quick computations on '
              'values already in the conversation, small transformations '
              'of text the user pasted, or logic the user explicitly '
              'asked to run locally (privacy, offline, no upload). No '
              'filesystem, no network, no subprocesses — pure '
              'in-process Python. Return values and print() output are '
              'both captured.',
          parameters: const {
            'type': 'object',
            'properties': {
              'code': {
                'type': 'string',
                'description': 'Python source to execute.',
              },
            },
            'required': ['code'],
          },
          executor: _runPythonOnDevice,
        ),
      ];

  @override
  Future<void> onAttach(AgentSession session) async {
    final runtime = MontyRuntime(extensions: _extensions.all);
    _runtime = runtime;

    // Fan each (namespace, signal) pair from the inner coordinator into
    // our aggregated state map. `coordinator` is null in sandbox mode —
    // we don't use sandbox mode here, but guard anyway.
    final coordinator = runtime.coordinator;
    if (coordinator != null) {
      for (final (ns, signal) in coordinator.statefulObservations()) {
        final unsub = signal.subscribe((value) {
          state = {...state, ns: value};
        });
        _unsubs.add(unsub);
      }
    }
  }

  @override
  void onDispose() {
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    unawaited(_runtime?.dispose());
    _runtime = null;
  }

  /// Executor for `run_python_on_device`. Always returns a JSON string.
  /// Python-level errors are returned in the payload — not thrown — so
  /// the LLM sees a completed tool call with an `error` field rather
  /// than retrying on `status: failed`.
  Future<String> _runPythonOnDevice(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final String code;
    try {
      final args = toolCall.arguments.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(toolCall.arguments) as Map<String, Object?>;
      final raw = args['code'];
      if (raw is! String) {
        return jsonEncode({
          'error': 'run_python_on_device: "code" argument must be a string',
        });
      }
      code = raw;
    } on Object catch (e) {
      return jsonEncode({
        'error': 'run_python_on_device: failed to parse arguments: $e',
      });
    }

    final runtime = _runtime;
    if (runtime == null) {
      return jsonEncode({
        'error': 'MontyRuntimeExtension is not attached to a session',
      });
    }

    try {
      final handle = runtime.execute(code);
      final result = await handle.result;
      return jsonEncode({
        'value': result.value.toJson(),
        'output': result.printOutput ?? '',
        if (result.error != null) 'error': result.error!.toJson(),
      });
    } on Object catch (e) {
      return jsonEncode({'error': 'run_python_on_device: $e'});
    }
  }
}
