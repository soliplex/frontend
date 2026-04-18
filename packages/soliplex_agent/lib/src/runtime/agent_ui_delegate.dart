import 'package:soliplex_agent/src/runtime/agent_session.dart';

/// Result of a HITL tool approval request.
sealed class ApprovalResult {
  const ApprovalResult();
}

/// User approved this invocation only. Next call will re-prompt.
class AllowOnce extends ApprovalResult {
  const AllowOnce();
}

/// User approved for the remainder of the session.
///
/// The caller is responsible for recording this grant so subsequent
/// invocations of the same tool are not re-prompted.
class AllowSession extends ApprovalResult {
  const AllowSession();
}

/// User denied the request. The agent session should be cancelled — do NOT
/// feed an error string back to the LLM as it will retry unconditionally.
class Deny extends ApprovalResult {
  const Deny();
}

/// Callback interface for UI-side tool approval decisions.
///
/// Both Flutter and TUI implement this interface to control how tool
/// execution approval is presented to the user. When no delegate is
/// provided to `AgentRuntime`, tools are **denied by default** for
/// safety. Pass [AutoApproveUiDelegate] to opt into headless
/// auto-approval.
///
/// ```dart
/// class MyUiDelegate implements AgentUiDelegate {
///   @override
///   Future<ApprovalResult> requestToolApproval({
///     required AgentSession session,
///     required String toolName,
///     required Map<String, dynamic> arguments,
///     required String rationale,
///   }) async {
///     // Show dialog, return user's decision
///     return showApprovalDialog(toolName, rationale);
///   }
/// }
/// ```
abstract interface class AgentUiDelegate {
  /// Suspends the tool loop until the user approves or rejects.
  ///
  /// [session] identifies which session is requesting approval, allowing
  /// multi-tab UIs to route the prompt to the correct view.
  ///
  /// Returns [AllowOnce] or [AllowSession] to proceed, [Deny] to block.
  /// On [Deny] the caller MUST cancel the agent session rather than
  /// returning an error string to the LLM.
  Future<ApprovalResult> requestToolApproval({
    required AgentSession session,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  });
}

/// Delegate that auto-approves all tool requests.
///
/// Use explicitly in headless/CI mode when you trust the prompt source.
/// Pass to `AgentRuntime(uiDelegate: AutoApproveUiDelegate())`.
class AutoApproveUiDelegate implements AgentUiDelegate {
  /// Creates an auto-approve delegate.
  const AutoApproveUiDelegate();

  @override
  Future<ApprovalResult> requestToolApproval({
    required AgentSession session,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async =>
      const AllowOnce();
}
