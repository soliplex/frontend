import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
          _Ring(label: 'Uploading', value: progress),
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
              ? const SizedBox.square(
                  dimension: FileRowAction.extent,
                  child: Center(child: _Ring(label: 'Deleting')),
                )
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

/// A progress ring in a 16 px icon slot, drawn the size of an icon's shape
/// rather than its box, so it weighs as much as the icons beside it, and
/// named by [label] to a screen reader. Indeterminate when [value] is null.
class _Ring extends StatelessWidget {
  const _Ring({required this.label, this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final ring = SizedBox.square(
      dimension: 16,
      child: Center(
        child: SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
            semanticsLabel: label,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (value != null) return ring;
    // A status, which a browser announces; a spinner's own role carries the
    // label to no reader there.
    return Semantics(
      container: true,
      role: SemanticsRole.status,
      label: label,
      excludeSemantics: true,
      child: ring,
    );
  }
}
