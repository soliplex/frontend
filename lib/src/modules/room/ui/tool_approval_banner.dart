import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Signal-aware slot that renders nothing when no approval is pending and
/// renders [ToolApprovalBanner] when one is.
///
/// Only this widget rebuilds when [pendingApproval] changes — the parent
/// column is unaffected.
class ToolApprovalSlot extends StatelessWidget {
  const ToolApprovalSlot({
    super.key,
    required this.pendingApproval,
    required this.onApprove,
    required this.onDeny,
  });

  final ReadonlySignal<PendingApprovalRequest?> pendingApproval;
  final void Function(String toolCallId) onApprove;
  final void Function(String toolCallId) onDeny;

  @override
  Widget build(BuildContext context) {
    final request = pendingApproval.watch(context);
    if (request == null) return const SizedBox.shrink();
    return ToolApprovalBanner(
      request: request,
      onApprove: () => onApprove(request.toolCallId),
      onDeny: () => onDeny(request.toolCallId),
    );
  }
}

/// Inline banner shown above the chat input when a tool call is
/// awaiting user approval.
///
/// Displays the tool name and the `code` argument (or a summary of
/// all arguments), then lets the user approve or deny.
class ToolApprovalBanner extends StatelessWidget {
  const ToolApprovalBanner({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onDeny,
  });

  final PendingApprovalRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  String get _preview {
    final code = request.arguments['code'];
    if (code is String) return code;
    return request.arguments.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Icon(
                  Icons.code,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Run ${request.toolName}?',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _preview,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDeny,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  child: const Text('Deny'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onApprove,
                  child: const Text('Allow'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
