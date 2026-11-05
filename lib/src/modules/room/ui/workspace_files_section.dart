import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/local_time_format.dart';
import '../../../shared/relative_time.dart';

import '../file_sort.dart';
import '../workdir_files_status.dart';
import '../workspace_groups.dart';
import 'file_list_row.dart';
import 'workdir_files.dart';

/// A section heading in the room's files panel.
class FilePanelSectionLabel extends StatelessWidget {
  const FilePanelSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// The files panel's list of the thread's sandbox workspace, in [sort]'s
/// order. Under folders: its root files, then one row per first-level folder
/// that opens and closes the folder's files. Under the other keys: every file
/// as a row of its own, showing its directory, with tooling files last.
/// Renders nothing while loading or when empty.
class WorkspaceFilesSection extends StatelessWidget {
  const WorkspaceFilesSection({
    super.key,
    required this.status,
    required this.sort,
    required this.onDownload,
    required this.onFetchBytes,
    required this.onRetry,
    required this.folderToggles,
    required this.onFolderToggled,
  });

  final WorkdirFilesStatus status;
  final FileSort sort;
  final Future<DownloadOutcome> Function(WorkdirFile file) onDownload;
  final Future<Uint8List> Function(WorkdirFile file) onFetchBytes;
  final VoidCallback onRetry;

  /// The folders the reader has opened or closed, mapped to whether each is
  /// open. A folder not in it is open unless it [startsCollapsed].
  final Map<String, bool> folderToggles;

  /// Called with a folder the reader opens or closes.
  final void Function(String folder, {required bool expanded}) onFolderToggled;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      WorkdirFilesLoading() => const SizedBox.shrink(),
      WorkdirFilesLoaded(:final files) when files.isEmpty =>
        const SizedBox.shrink(),
      WorkdirFilesLoaded(:final files) => _listing(context, files),
      WorkdirFilesFailed(:final error, :final retrying) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const FilePanelSectionLabel('Workspace'),
            WorkdirErrorRow(
              onRetry: onRetry,
              isRetrying: retrying,
              reason: workdirErrorMessage(error),
            ),
          ],
        ),
    };
  }

  Widget _listing(BuildContext context, List<WorkdirFile> listing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const FilePanelSectionLabel('Workspace'),
        if (sort.key == FileSortKey.folders)
          ..._grouped(context, listing)
        else
          ..._flat(context, listing),
      ],
    );
  }

  List<Widget> _grouped(BuildContext context, List<WorkdirFile> listing) {
    final grouped = groupByFirstFolder(listing, descending: sort.descending);
    return [
      ..._rows(context, grouped.files, directoryOf: (_) => null),
      for (final group in grouped.folders) ..._folder(context, group),
    ];
  }

  /// The real files, then the tooling files, each part paging its own
  /// previews, so paging from the last real file does not walk into tooling
  /// output.
  List<Widget> _flat(BuildContext context, List<WorkdirFile> listing) {
    final flat = flatWorkspace(listing, sort);
    return [
      ..._rows(context, flat.files, directoryOf: (f) => f.directory),
      ..._rows(context, flat.tooling, directoryOf: (f) => f.directory),
    ];
  }

  List<Widget> _folder(
    BuildContext context,
    ({String name, List<WorkdirFile> files}) group,
  ) {
    final expanded = isFolderExpanded(folderToggles, group.name);
    return [
      _FolderRow(
        name: group.name,
        count: group.files.length,
        latestChange: group.files
            .map((f) => f.modifiedAt)
            .nonNulls
            .fold<DateTime?>(
              null,
              (latest, t) => latest == null || t.isAfter(latest) ? t : latest,
            ),
        expanded: expanded,
        onTap: () => onFolderToggled(group.name, expanded: !expanded),
      ),
      if (expanded)
        // Keyed by the folder, so when the folders reorder its files' rows
        // move with it and keep their state, such as a download in progress.
        Padding(
          key: ValueKey(group.name),
          padding: const EdgeInsets.only(left: SoliplexSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _rows(
              context,
              group.files,
              directoryOf: (f) => directoryWithin(f, group.name),
            ),
          ),
        ),
    ];
  }

  /// Rows for one group of files, each showing [directoryOf] it after its
  /// name. The preview a row opens pages through that group only.
  List<Widget> _rows(
    BuildContext context,
    List<WorkdirFile> files, {
    required String? Function(WorkdirFile file) directoryOf,
  }) =>
      [
        for (var i = 0; i < files.length; i++)
          WorkdirFileRow(
            // A row holds its download's state, which belongs to the file:
            // keyed by it, the state follows the file as its group's list
            // reorders, and a file of another thread starts fresh (the
            // server's URL for it names the thread). A file the listing reports
            // with a different modified time or size starts fresh too, since
            // those are part of its equality.
            key: ValueKey(files[i]),
            file: files[i],
            directory: directoryOf(files[i]),
            onTap: () => onDownload(files[i]),
            onOpenPreview: () => WorkdirPreviewPage.show(
              context: context,
              files: files,
              initialIndex: i,
              fetchBytes: onFetchBytes,
              onDownload: onDownload,
            ),
          ),
      ];
}

/// A first-level workspace folder: its name, and under it the count of the
/// files below it at any depth and when the newest of them changed. Tapping
/// it opens or closes the folder's files.
///
/// Its icon lines up with the icons of the files at its level, and its
/// chevron sits in their download buttons' column.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.count,
    required this.latestChange,
    required this.expanded,
    required this.onTap,
  });

  final String name;
  final int count;

  /// When the most recently modified file below the folder changed; null
  /// when none has a time.
  final DateTime? latestChange;

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final countLabel = '$count ${count == 1 ? 'file' : 'files'}';
    final latestChange = this.latestChange;
    final details = latestChange == null
        ? DetailsLine(text: countLabel, spoken: countLabel)
        : DetailsLine(
            text: '$countLabel · ${formatRelativeTime(latestChange)}',
            spoken: '$countLabel, latest change '
                '${spokenRelativeTime(latestChange)}',
            tooltip: 'Latest change inside: '
                '${formatDateAndTime(latestChange.toLocal())}',
          );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: Semantics(
        button: true,
        expanded: expanded,
        label: '$name, ${details.spoken}',
        child: ExcludeSemantics(
          child: FileListRow(
            leading: Icon(
              expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
              size: 16,
              color: muted,
            ),
            content: FullNameTooltip(
              name: name,
              child: Text(
                name,
                // Muted as a tooling file's name is, and for the same reason.
                style: isToolingPath(name)
                    ? theme.textTheme.bodySmall?.copyWith(color: muted)
                    : theme.textTheme.bodySmall,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            details: details,
            // Not a FileRowAction: the whole row is the one button.
            actions: [
              SizedBox(
                width: FileRowAction.extent,
                child: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
