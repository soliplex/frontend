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
      PendingUpload(:final progress) => (_Ring(value: progress), null),
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
      PendingUpload(:final id) => FileRowAction(
          icon: Icons.close,
          tooltip: 'Cancel upload',
          onTap: () => onCancel(id),
        ),
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
          // The full name, which a cut name hides. On touch its long press
          // shows the name rather than selecting a word of it. Left out of
          // semantics: the text already reads the name.
          Tooltip(
            message: entry.filename,
            waitDuration: const Duration(milliseconds: 500),
            excludeFromSemantics: true,
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
              // A status, which a browser announces; a spinner's own role
              // carries the label to no reader there.
              ? Semantics(
                  container: true,
                  role: SemanticsRole.status,
                  label: 'Deleting',
                  excludeSemantics: true,
                  child: const SizedBox.square(
                    dimension: FileRowAction.extent,
                    child: Center(child: _Ring()),
                  ),
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
/// rather than its box, so it weighs as much as the icons beside it.
/// Indeterminate when [value] is null.
class _Ring extends StatelessWidget {
  const _Ring({this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 16,
      child: Center(
        child: SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
