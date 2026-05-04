import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// A capability bound to the lifecycle of an [AgentSession].
///
/// Extensions provide tools and resources that are created when the
/// session starts and disposed when the session ends.
///
/// Subclass via `extends SessionExtension` to inherit the default
/// [namespace] and [priority]. Mix in `StatefulSessionExtension` to
/// add a typed reactive-state signal.
abstract class SessionExtension {
  /// Unique identifier for this extension type.
  ///
  /// The coordinator validates uniqueness across all extensions in a session
  /// when the namespace is non-empty. Use the default empty string for
  /// extensions that do not need cross-extension discovery.
  String get namespace => '';

  /// Attach priority. Higher values attach first and dispose last.
  int get priority => 0;

  /// Called after session creation, before the run starts.
  ///
  /// Receives the [session] for context access (e.g. spawning children,
  /// emitting events, or accessing other extensions).
  Future<void> onAttach(AgentSession session);

  /// Tools this extension provides.
  ///
  /// Returned tools are merged into the session's [ToolRegistry] during
  /// [onAttach]. The list must be stable after [onAttach] completes.
  List<ClientTool> get tools;

  /// Called when the session is disposed. Must be idempotent.
  ///
  /// May be invoked even if [onAttach] did not complete (e.g. a sibling
  /// extension threw mid-attach). Implementations must tolerate being
  /// called from any partially-initialized state.
  void onDispose();
}

/// Factory that creates extensions for each new session.
typedef SessionExtensionFactory = Future<List<SessionExtension>> Function();
