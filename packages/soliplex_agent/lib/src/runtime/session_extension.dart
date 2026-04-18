import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_context.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

export 'package:soliplex_agent/src/runtime/session_context.dart';

/// A capability bound to the lifecycle of an [AgentSession].
///
/// Extensions provide tools and resources that are created when the
/// session starts and disposed when the session ends. The session
/// cascades dispose to all extensions.
abstract interface class SessionExtension {
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
  void dispose();
}

/// Factory that creates extensions for each new session.
typedef SessionExtensionFactory =
    Future<List<SessionExtension>> Function(SessionContext ctx);
