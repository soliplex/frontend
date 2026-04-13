import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/scripting/scripting_state.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// Session-scoped scripting environment providing client-side tools and
/// reactive interpreter lifecycle state.
///
/// Implementations own interpreter resources (bridge, registries) and
/// expose them as [ClientTool]s. The owning `AgentSession` calls
/// [onAttach] once the session is ready, then [dispose] when it tears down.
///
/// The runtime is completely agnostic about the interpreter technology
/// (WASM, Python subprocess, etc.) — it only sees [tools] and [scriptingState].
abstract interface class ScriptEnvironment {
  /// Client-side tools this environment provides (e.g., `execute_python`).
  List<ClientTool> get tools;

  /// Reactive interpreter lifecycle state.
  ///
  /// Transitions: [ScriptingState.idle] → [ScriptingState.executing] →
  /// [ScriptingState.idle] on each script run.
  /// Reaches [ScriptingState.disposed] after [dispose] is called.
  ///
  /// Observe this in Flutter widgets via `Watch` to show "Python running"
  /// indicators without polling.
  ReadonlySignal<ScriptingState> get scriptingState;

  /// Called once after the parent [AgentSession] is fully initialised,
  /// before the first run starts.
  ///
  /// Use to store the session reference for [AgentSession.emitEvent] calls
  /// inside tool executors.
  Future<void> onAttach(AgentSession session);

  /// Releases interpreter resources (bridge, registries).
  ///
  /// Called once by `AgentSession.dispose()`. Must be idempotent.
  void dispose();
}

/// Factory that creates a fresh [ScriptEnvironment] per session.
///
/// The closure captures app-level dependencies (server connections,
/// OS provider, etc.) so callers only need to invoke it.
typedef ScriptEnvironmentFactory = Future<ScriptEnvironment> Function();

/// Adapter that wraps a [ScriptEnvironment] as a [SessionExtension].
///
/// Exposes [scriptingState] directly so Flutter widgets can bind to the
/// interpreter lifecycle without accessing [ScriptEnvironment] directly.
class ScriptEnvironmentExtension implements SessionExtension {
  /// Creates an extension that wraps the given [ScriptEnvironment].
  ScriptEnvironmentExtension(this._environment);

  final ScriptEnvironment _environment;

  /// Reactive interpreter state — subscribe in Flutter for "Python running" UI.
  ///
  /// Delegates to [ScriptEnvironment.scriptingState].
  ReadonlySignal<ScriptingState> get scriptingState =>
      _environment.scriptingState;

  @override
  Future<void> onAttach(AgentSession session) => _environment.onAttach(session);

  @override
  List<ClientTool> get tools => _environment.tools;

  @override
  void onDispose() => _environment.dispose();
}

/// Converts a [ScriptEnvironmentFactory] into a [SessionExtensionFactory].
///
/// Each invocation creates a single [ScriptEnvironmentExtension] wrapping
/// the environment produced by [factory].
SessionExtensionFactory wrapScriptEnvironmentFactory(
  ScriptEnvironmentFactory factory,
) {
  return () async {
    final env = await factory();
    return [ScriptEnvironmentExtension(env)];
  };
}
