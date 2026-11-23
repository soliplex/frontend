import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/core/ui/confirm_dialog.dart';
import 'package:soliplex_client/soliplex_client.dart' show SoliplexApi;
import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';
import 'package:soliplex_frontend/src/modules/room/file_source.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_list_row.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_row_download_action.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart'
    show FileName, FilePreviewPage;
import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/preview_kind.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';
import 'package:soliplex_frontend/src/shared/file_size.dart';

/// One row of an upload list: the file's state or type, its name, its time
/// and size or why it failed, and the actions its state allows. A stored
/// file, unless it is being deleted, opens its preview when tapped and
/// offers its download.
class UploadEntryRow extends StatelessWidget {
  const UploadEntryRow({
    super.key,
    required this.entry,
    required this.onCancel,
    required this.onDismiss,
    required this.downloads,
    required this.onOpenPreview,
    this.onDelete,
  });

  final DisplayUpload entry;
  final void Function(String entryId) onCancel;
  final void Function(String entryId) onDismiss;

  /// Where a stored file's download action reads its download and starts it.
  final FileDownloads downloads;

  /// Opens the preview at a stored file: tapping its row invokes it, and so
  /// does the eye icon a previewable file shows.
  final void Function(PersistedUpload entry) onOpenPreview;

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

    final details = switch (entry) {
      PersistedUpload(:final file) => DetailsLine.file(
          modifiedAt: file.modifiedAt,
          sizeBytes: file.sizeBytes,
        ),
      // Holds the line a stored file shows, so the row keeps its height
      // when the upload lands on a server that reports a time or a size.
      // Only the size is spoken: the ring's label already says Uploading.
      PendingUpload(:final totalBytes) => DetailsLine(
          text: 'Uploading · ${formatFileSize(totalBytes)}',
          spoken: spokenFileSize(totalBytes),
        ),
      FailedUpload() => null,
    };

    final available = switch (entry) {
      final PersistedUpload stored when !stored.isDeleting => stored,
      _ => null,
    };

    final row = FileListRow(
      isFailed: isFailed,
      details: details,
      leading: leading,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FullNameTooltip(
            name: entry.filename,
            child: FileName(
              entry.filename,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isFailed ? theme.colorScheme.onErrorContainer : null,
              ),
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
        if (available != null) ...[
          if (PreviewKind.from(available.filename).canRender)
            FileRowAction(
              icon: Icons.visibility_outlined,
              tooltip: 'Preview',
              onTap: () => onOpenPreview(available),
            ),
          FileRowDownloadAction(file: available.file, downloads: downloads),
        ],
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
    if (available == null) return row;
    return InkWell(
      onTap: () => onOpenPreview(available),
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: row,
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

/// Opens the preview at [opened], paging through the stored, not-deleting
/// files of [rows] in the order they show, fetched from [source].
Future<void> showUploadPreview({
  required BuildContext context,
  required List<DisplayUpload> rows,
  required PersistedUpload opened,
  required SoliplexApi api,
  required FileSource source,
  required FileDownloads downloads,
}) {
  final files = [
    for (final row in rows)
      if (row case PersistedUpload(isDeleting: false)) row.file,
  ];
  return FilePreviewPage.show(
    context: context,
    files: files,
    initialIndex: files.indexWhere((f) => f.filename == opened.filename),
    fetchBytes: (file) => fetchFileBytes(api, source, file),
    downloads: downloads,
  );
}
