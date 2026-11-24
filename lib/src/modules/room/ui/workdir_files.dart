import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import '../file_downloads.dart';
import 'file_list_row.dart';
import 'file_name.dart';
import 'file_preview/preview_kind.dart';
import 'file_row_download_action.dart';

class WorkdirFileRow extends StatelessWidget {
  const WorkdirFileRow({
    super.key,
    required this.file,
    required this.directory,
    required this.downloads,
    required this.onOpenPreview,
  });

  final WorkdirFile file;

  /// The directory the row shows after [file]'s name, or `null` to show
  /// none, as every row under Folders does.
  final String? directory;

  /// Where the row's download action reads [file]'s download and starts it.
  final FileDownloads downloads;

  /// Opens the preview at [file]: tapping the row invokes it, and so does
  /// the eye icon a previewable file shows (the parent opens the multi-file
  /// pager on the files of the row's group, so they are reachable via
  /// swipe). A file that cannot preview opens at its "Can't preview" page,
  /// which offers the download.
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = PreviewKind.from(file.filename);
    final canPreview = kind.opensInViewer;
    // Rows that can't preview show the generic file icon so the leading
    // icon doesn't imply their content can be shown.
    final leadingIcon =
        canPreview ? kind.rowIcon : Icons.insert_drive_file_outlined;
    final nameStyle = theme.textTheme.bodySmall;
    return InkWell(
      onTap: onOpenPreview,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: FileListRow(
        details: DetailsLine.file(
          modifiedAt: file.modifiedAt,
          sizeBytes: file.sizeBytes,
        ),
        leading: Icon(
          leadingIcon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        content: NameAndDirectory(
          path: file.filename,
          name: FileName(file.basename, style: nameStyle),
          directory: directory,
          style: nameStyle,
        ),
        actions: [
          if (canPreview)
            FileRowAction(
              icon: Icons.visibility_outlined,
              tooltip: 'Preview',
              onTap: onOpenPreview,
            ),
          FileRowDownloadAction(file: file, downloads: downloads),
        ],
      ),
    );
  }
}

class WorkdirErrorRow extends StatelessWidget {
  const WorkdirErrorRow({
    super.key,
    required this.onRetry,
    required this.isRetrying,
    required this.reason,
  });

  final VoidCallback onRetry;

  /// Whether a retry is in flight; the Retry button turns into a disabled one
  /// showing a spinner, so the row keeps its size and cannot queue another
  /// retry.
  final bool isRetrying;

  /// Why the list failed, shown after the fixed message; text that is safe to
  /// show.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Shared by the Retry icon and the spinner that replaces it, so the row
    // keeps its height while a retry is in flight.
    const retryGlyphSize = 16.0;
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: SoliplexSpacing.s1, horizontal: SoliplexSpacing.s1),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              "Couldn't load files — $reason",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          IconButton(
            onPressed: isRetrying ? null : onRetry,
            // Without ExcludeSemantics the spinner's loading-spinner role
            // merges into the button, and the web announces it in place of
            // the button's.
            icon: isRetrying
                ? const ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: retryGlyphSize,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.refresh),
            iconSize: retryGlyphSize,
            tooltip: isRetrying ? 'Retrying' : 'Retry',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
