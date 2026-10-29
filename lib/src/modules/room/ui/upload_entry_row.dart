import 'package:flutter/material.dart';

import 'package:soliplex_frontend/src/core/ui/confirm_dialog.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_list_row.dart';
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
    final (leading, errorMessage) = switch (entry) {
      PersistedUpload(:final filename) => (
          Icon(
            PreviewKind.from(filename).rowIcon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          null,
        ),
      PendingUpload(:final progress) => (
          ProgressRing(label: 'Uploading', value: progress),
          null,
        ),
      FailedUpload(message: final m) => (
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          m,
        ),
    };

    final close = switch (entry) {
      PendingUpload(:final id, allBytesSent: false) => FileRowAction(
          icon: Icons.close,
          tooltip: 'Cancel upload',
          onTap: () => onCancel(id),
        ),
      PendingUpload() => null,
      FailedUpload(:final id) => FileRowAction(
          icon: Icons.close,
          tooltip: 'Dismiss',
          onTap: () => onDismiss(id),
          color: theme.colorScheme.onErrorContainer,
        ),
      PersistedUpload() => null,
    };

    return FileListRow(
      isFailed: isFailed,
      leading: leading,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FullNameTooltip(
            name: entry.filename,
            child: Text(
              entry.filename,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isFailed ? theme.colorScheme.onErrorContainer : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
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
      actions: [
        if (entry case PersistedUpload(:final filename, :final isDeleting)
            when onDelete != null)
          isDeleting
              ? const FileRowActionProgress(label: 'Deleting')
              : FileRowAction(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  onTap: () => _confirmDelete(context, filename),
                ),
        if (close != null) close,
      ],
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
