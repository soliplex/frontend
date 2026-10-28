import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

/// One row of an upload list: the file's state, its name, why it failed, and
/// the action its state allows.
class UploadEntryRow extends StatelessWidget {
  const UploadEntryRow({
    super.key,
    required this.entry,
    required this.onCancel,
    required this.onDismiss,
  });

  final DisplayUpload entry;
  final void Function(String entryId) onCancel;
  final void Function(String entryId) onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = entry is FailedUpload;
    final (icon, color, errorMessage) = switch (entry) {
      PersistedUpload() => (
          Icons.check_circle_outline,
          context.success,
          null,
        ),
      PendingUpload() => (null, theme.colorScheme.primary, null),
      FailedUpload(message: final m) => (
          Icons.error_outline,
          theme.colorScheme.onErrorContainer,
          m,
        ),
    };

    final (closeTooltip, closeAction) = switch (entry) {
      PendingUpload(:final id) => ('Cancel upload', () => onCancel(id)),
      FailedUpload(:final id) => ('Dismiss', () => onDismiss(id)),
      _ => (null, null),
    };
    final closeColor = isFailed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.outline;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      padding: isFailed
          ? const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1)
          : const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s1, vertical: SoliplexSpacing.s1),
      decoration: isFailed
          ? BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(context.radii.sm),
            )
          : null,
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 16, color: color)
          else
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
                value: switch (entry) {
                  PendingUpload(:final progress) => progress,
                  _ => null,
                },
              ),
            ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.filename,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isFailed ? theme.colorScheme.onErrorContainer : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (errorMessage != null)
                  Text(
                    errorMessage,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (closeAction != null)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: closeColor,
              tooltip: closeTooltip,
              onPressed: closeAction,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
