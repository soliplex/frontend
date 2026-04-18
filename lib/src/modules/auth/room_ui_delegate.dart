import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../room/ui/tool_approval_dialog.dart';

/// Flutter [AgentUiDelegate] implementation.
///
/// Presents a [ToolApprovalDialog] for each HITL request. The dialog
/// offers three choices: Allow Once, Allow Session, and Deny.
class RoomUiDelegate implements AgentUiDelegate {
  /// Creates a [RoomUiDelegate] backed by [navigatorKey].
  const RoomUiDelegate({required this.navigatorKey});

  /// The navigator key used to show the approval dialog.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<ApprovalResult> requestToolApproval({
    required AgentSession session,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return const Deny();
    return showToolApprovalDialog(
      context,
      toolName: toolName,
      arguments: arguments,
      rationale: rationale,
    );
  }
}
