import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// An extension that can respond to tool approval requests.
///
/// Subclass this in the application layer (e.g. `HumanApprovalExtension`) to
/// intercept calls to `AgentSession.requestApproval` and surface them as
/// reactive state that the UI can observe and respond to.
///
/// All subclasses share the [namespace] `tool_approval`. A session has at
/// most one: if a flavor registers two, `SessionCoordinator` keeps the
/// first-registered, drops the rest at construction, and logs an error
/// naming each dropped class. When no extension is registered,
/// `AgentSession.requestApproval` returns `false`.
abstract class ToolApprovalExtension extends SessionExtension {
  @override
  @nonVirtual
  String get namespace => 'tool_approval';

  @override
  List<ClientTool> get tools => const [];

  /// Requests user consent for the given tool call.
  ///
  /// Returns `true` to proceed with execution, `false` to deny. The session
  /// uses a synchronous cancel-token check before delegating here; the
  /// extension is responsible for resolving any pending request to `false`
  /// when the session is cancelled mid-request (typically via a
  /// `cancelToken.whenCancelled` listener registered in [onAttach]).
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  });
}
