import 'package:meta/meta.dart';

/// A tool call suspended pending user approval.
///
/// Emitted on `AgentSession.pendingApproval` when the session encounters
/// a `ClientTool` with `requiresApproval` set to `true`.
///
/// Resolve by calling `AgentSession.approveToolCall` or
/// `AgentSession.denyToolCall` with the matching [toolCallId].
///
/// The session's tool execution loop is suspended until one of those methods
/// is called, or the session is cancelled (which auto-denies).
@immutable
class PendingApprovalRequest {
  /// Creates a pending approval request.
  const PendingApprovalRequest({
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
  });

  /// The tool call ID — pass back to `AgentSession.approveToolCall` or
  /// `AgentSession.denyToolCall`.
  final String toolCallId;

  /// Human-readable tool name for display in the approval UI.
  final String toolName;

  /// Parsed tool arguments for display in the approval UI.
  final Map<String, dynamic> arguments;
}
