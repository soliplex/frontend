import 'dart:async';

import 'package:meta/meta.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// An in-flight tool approval request waiting for a user decision.
@immutable
class ApprovalRequest {
  const ApprovalRequest({
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
    required this.rationale,
  });

  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String rationale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApprovalRequest &&
          toolCallId == other.toolCallId &&
          toolName == other.toolName &&
          rationale == other.rationale;

  @override
  int get hashCode => Object.hash(toolCallId, toolName, rationale);
}

/// A [ToolApprovalExtension] that surfaces tool approval requests as reactive
/// state so the UI can respond without an [AgentUiDelegate].
///
/// When [AgentSession.requestApproval] fires, [stateSignal] is set to the
/// pending [ApprovalRequest]. The UI watches the signal, shows an approval
/// dialog, then calls [respond] with the user's decision. Calling [respond]
/// clears the signal back to `null` and resolves the session's future.
///
/// If the session is cancelled or the extension is disposed while an approval
/// is pending, the request is automatically denied.
class HumanApprovalExtension extends ToolApprovalExtension
    with StatefulSessionExtension<ApprovalRequest?> {
  HumanApprovalExtension() {
    setInitialState(null);
  }

  Completer<bool>? _pending;

  @override
  String get namespace => 'human_approval';

  @override
  int get priority => 30;

  @override
  List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void onDispose() {
    _pending?.complete(false);
    _pending = null;
    super.onDispose();
  }

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) {
    // Deny any stale pending request before starting a new one.
    _pending?.complete(false);
    final completer = Completer<bool>();
    _pending = completer;
    state = ApprovalRequest(
      toolCallId: toolCallId,
      toolName: toolName,
      arguments: arguments,
      rationale: rationale,
    );
    return completer.future;
  }

  /// Resolves the pending approval request with [approved].
  ///
  /// No-op if there is no pending request.
  void respond(bool approved) {
    _pending?.complete(approved);
    _pending = null;
    state = null;
  }
}
