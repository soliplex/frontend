import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// Session-scoped scripting environment providing client-side tools.
///
/// Implementations own interpreter resources (bridge, registries) and
/// expose them as [ClientTool]s. The owning `AgentSession` calls
/// [dispose] when it tears down, cascading resource cleanup.
///
/// The runtime is completely agnostic about the interpreter technology
/// (WASM, Python subprocess, etc.) — it only sees [tools].
abstract interface class ScriptEnvironment {
  /// Client-side tools this environment provides (e.g., `execute_python`).
  List<ClientTool> get tools;

  /// Releases interpreter resources (bridge, registries).
  ///
  /// Called once by `AgentSession.dispose()`. Must be idempotent.
  void dispose();
}

/// Factory that creates a fresh [ScriptEnvironment] per session.
///
/// The closure captures app-level dependencies (HostApi, AgentApi,
/// MontyLimits, etc.) so callers only need to invoke it.
typedef ScriptEnvironmentFactory = Future<ScriptEnvironment> Function();

/// Exposes a [ScriptEnvironment] as a [SessionExtension] so its tools
/// and dispose hook participate in normal session lifecycle.
class ScriptEnvironmentExtension extends SessionExtension {
  /// Creates an extension that wraps the given [ScriptEnvironment].
  ScriptEnvironmentExtension(this._environment);

  final ScriptEnvironment _environment;

  @override
  Future<void> onAttach(AgentSession session) async {}

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
