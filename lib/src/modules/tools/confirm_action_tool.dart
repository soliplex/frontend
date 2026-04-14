import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';

/// A [ClientTool] that requires explicit user approval before proceeding.
///
/// `requiresApproval: true` suspends execution and emits a
/// `PendingApprovalRequest` on `AgentSession.pendingApproval`. The UI
/// renders a banner with Allow / Deny buttons; the action string from the
/// model is shown in the code preview area.
///
/// Example model call:
/// ```json
/// {"action": "Delete all uploaded files"}
/// ```
///
/// After approval the tool returns a confirmation string so the model knows
/// the user consented and can continue.
ClientTool buildConfirmActionTool() => ClientTool.simple(
      name: 'confirm_action',
      description: 'Ask the user to approve an action before it is taken. '
          'Describe the action clearly in the `action` argument so the user '
          'can make an informed decision.',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': 'Human-readable description of the action '
                'the user must approve.',
          },
        },
        'required': ['action'],
      },
      executor: (toolCall, context) async {
        final args = toolCall.arguments.isEmpty
            ? <String, dynamic>{}
            : (jsonDecode(toolCall.arguments) as Map<String, dynamic>);
        final action = args['action'] as String? ?? '(no action specified)';
        return 'User approved: $action';
      },
      requiresApproval: true,
    );
