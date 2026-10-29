import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/core/ui/confirm_dialog.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/preview_kind.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

/// One row of an upload list: the file's state or type, its name, why it
/// failed, and the action its state allows.
class UploadEntryRow extends StatelessWidget {
  const UploadEntryRow({
    super.key,
    required this.entry,
    required this.onCancel,
    required this.onDismiss,
    this.onDelete,
  });

  final DisplayUpload entry;
  final void Function(String entryId) onCancel;
  final void Function(String entryId) onDismiss;

  /// Deletes a stored room upload by filename, once the user confirms. Null
  /// where the row offers no delete.
  final void Function(String filename)? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = entry is FailedUpload;
    final (icon, color, errorMessage) = switch (entry) {
      PersistedUpload(:final filename) => (
          PreviewKind.from(filename).rowIcon,
          theme.colorScheme.onSurfaceVariant,
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
          if (entry case PersistedUpload(:final filename, :final isDeleting)
              when onDelete != null)
            isDeleting
                // A status, which a browser announces; a spinner's own role
                // carries the label to no reader there.
                ? Semantics(
                    container: true,
                    role: SemanticsRole.status,
                    label: 'Deleting',
                    excludeSemantics: true,
                    child: const Padding(
                      padding: EdgeInsets.all(SoliplexSpacing.s1),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _DeleteButton(onTap: () => _confirmDelete(context, filename)),
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

  Future<void> _confirmDelete(BuildContext context, String filename) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete file?',
      message: 'Delete "$filename" for everyone in this room? '
          "This can't be undone.",
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed) onDelete?.call(filename);
  }
}

/// Drawn like the workspace rows' trailing actions, and named once: the
/// tooltip is left out of semantics so the label is not read twice. Its own
/// semantics node, so a card that merges its children's semantics does not
/// absorb it and become a button itself.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: 'Delete',
      child: Tooltip(
        message: 'Delete',
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.radii.sm),
          child: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s1),
            child: Icon(
              Icons.delete_outline,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
