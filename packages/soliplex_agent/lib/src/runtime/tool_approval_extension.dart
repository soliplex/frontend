import 'package:soliplex_agent/src/runtime/session_extension.dart';

/// An extension that can respond to tool approval requests.
///
/// Subclass this in the application layer (e.g. `HumanApprovalExtension`) to
/// intercept calls to `AgentSession.requestApproval` and surface them as
/// reactive state that the UI can observe and respond to.
///
/// When an instance of this extension is registered with a session,
/// `AgentSession.requestApproval` delegates to [requestApproval]. When no
/// extension is registered, `AgentSession.requestApproval` returns `false`
/// (deny by default). Only one `ToolApprovalExtension` may be registered
/// per session (enforced by the namespace uniqueness check in
/// `SessionCoordinator`).
abstract class ToolApprovalExtension extends SessionExtension {
  /// Requests user consent for the given tool call.
  ///
  /// Returns `true` to proceed with execution, `false` to deny.
  /// The session races this future against its cancel token —
  /// cancellation automatically produces `false`.
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  });
}
