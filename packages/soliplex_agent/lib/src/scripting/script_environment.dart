import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_context.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/scripting/scripting_state.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// Session-scoped scripting environment providing client-side tools and
/// reactive interpreter lifecycle state.
///
/// `ScriptEnvironment` extends [SessionExtension] directly: it already
/// satisfies `onAttach`, `tools`, and `dispose`, and adds `scriptingState`
/// for interpreter lifecycle observability.
///
/// Implementations own interpreter resources (bridge, registries) and
/// expose them as [ClientTool]s. The owning `AgentSession` calls
/// [onAttach] once the session is ready, then [dispose] when it tears down.
///
/// The runtime is completely agnostic about the interpreter technology
/// (WASM, Python subprocess, etc.) — it only sees [tools] and
/// [scriptingState].
abstract interface class ScriptEnvironment implements SessionExtension {
  /// Client-side tools this environment provides (e.g., `execute_python`).
  @override
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

  /// Called once after the parent `AgentSession` is fully initialised,
  /// before the first run starts.
  ///
  /// Use to store the session reference for `AgentSession.emitEvent` calls
  /// inside tool executors.
  @override
  Future<void> onAttach(AgentSession session);

  /// Releases interpreter resources (bridge, registries).
  ///
  /// Called once by `AgentSession.dispose()`. Must be idempotent.
  @override
  void dispose();
}

/// Factory that creates a fresh [ScriptEnvironment] per session.
///
/// The closure captures app-level dependencies (server connections,
/// OS provider, etc.) so callers only need to invoke it.
typedef ScriptEnvironmentFactory =
    Future<ScriptEnvironment> Function(SessionContext ctx);

/// Wraps a [ScriptEnvironmentFactory] as a [SessionExtensionFactory].
///
/// Each session gets an **owned** [ScriptEnvironment]: the factory is
/// invoked once per session and the environment is disposed when the
/// session ends.
///
/// Use this for fire-and-forget sessions that each get an isolated
/// interpreter. For a shared, long-lived environment see [toSharedFactory].
SessionExtensionFactory toOwnedFactory(ScriptEnvironmentFactory factory) {
  return (ctx) async => [await factory(ctx)];
}

/// Wraps a **shared** [ScriptEnvironment] as a [SessionExtensionFactory].
///
/// Unlike [toOwnedFactory], the environment is **not disposed** when a
/// session ends — the caller retains ownership and must call
/// [ScriptEnvironment.dispose] at shutdown.
///
/// Use this when sharing one interpreter across many sessions (e.g. a
/// persistent Python state across all turns for one room). Sessions must
/// be spawned with `autoDispose: false` (the default) so the shared
/// environment is not irrevocably destroyed when any individual session
/// completes.
///
/// Example:
/// ```dart
/// final env = MontyScriptEnvironment(plugins: [SoliplexPlugin(...)]);
/// final runtime = AgentRuntime(
///   extensionFactory: toSharedFactory(env),
///   // ...
/// );
/// // At shutdown:
/// env.dispose();
/// await runtime.dispose();
/// ```
SessionExtensionFactory toSharedFactory(ScriptEnvironment env) {
  return (_) async => [SharedScriptEnvironmentProxy(env)];
}

/// Wraps a [ScriptEnvironment] as a [SessionExtension] without taking
/// ownership. [dispose] is intentionally a no-op — lifecycle is managed
/// by whoever created the environment.
class SharedScriptEnvironmentProxy implements SessionExtension {
  SharedScriptEnvironmentProxy(this._env);

  final ScriptEnvironment _env;

  @override
  List<ClientTool> get tools => _env.tools;

  @override
  Future<void> onAttach(AgentSession session) => _env.onAttach(session);

  @override
  void dispose() {
    // Shared environment — lifecycle owned by the caller, not this session.
  }
}
