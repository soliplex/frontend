import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Shows a modal dialog requesting HITL approval for a tool call.
///
/// Returns [AllowOnce], [AllowSession], or [Deny] based on the user's choice.
/// Dismissing the dialog (back button / tap outside) is treated as [Deny].
Future<ApprovalResult> showToolApprovalDialog(
  BuildContext context, {
  required String toolName,
  required Map<String, dynamic> arguments,
  required String rationale,
}) async {
  final result = await showDialog<ApprovalResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ToolApprovalDialog(
      toolName: toolName,
      arguments: arguments,
      rationale: rationale,
    ),
  );
  return result ?? const Deny();
}

class _ToolApprovalDialog extends StatelessWidget {
  const _ToolApprovalDialog({
    required this.toolName,
    required this.arguments,
    required this.rationale,
  });

  final String toolName;
  final Map<String, dynamic> arguments;
  final String rationale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Allow "$toolName"?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rationale, style: theme.textTheme.bodyMedium),
          if (arguments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Arguments:', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            _ArgumentsView(arguments: arguments),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const Deny()),
          child: const Text('Deny'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(const AllowOnce()),
          child: const Text('Allow once'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(const AllowSession()),
          child: const Text('Allow for session'),
        ),
      ],
    );
  }
}

class _ArgumentsView extends StatelessWidget {
  const _ArgumentsView({required this.arguments});
  final Map<String, dynamic> arguments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in arguments.entries)
            Text(
              '${entry.key}: ${entry.value}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}
