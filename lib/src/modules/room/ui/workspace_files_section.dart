import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/local_time_format.dart';
import '../../../shared/relative_time.dart';

import '../file_downloads.dart';
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
/// order. Under folders: the workspace's folder tree, each folder a row that
/// opens and closes its files and folders, which sit indented below it, up
/// to four levels deep.
/// Under the other keys: every file as a row of its own, showing its
/// directory, with tooling files last. Renders nothing while loading or when
/// empty.
class WorkspaceFilesSection extends StatelessWidget {
  const WorkspaceFilesSection({
    super.key,
    required this.status,
    required this.sort,
    required this.downloads,
    required this.onFetchBytes,
    required this.onRetry,
    required this.folderToggles,
    required this.onFolderToggled,
  });

  final WorkdirFilesStatus status;
  final FileSort sort;

  /// Each file's download, which its row and its preview show and start.
  final FileDownloads downloads;
  final Future<Uint8List> Function(WorkdirFile file) onFetchBytes;
  final VoidCallback onRetry;

  /// The folders the reader has opened or closed, by path from the
  /// workspace root, mapped to whether each is open. A folder not in it
  /// shows its default (see [isFolderExpanded]).
  final Map<String, bool> folderToggles;

  /// Called with the path of a folder the reader opens or closes.
  final void Function(String folder, {required bool expanded}) onFolderToggled;

  /// The levels a folder's contents indent, past which they line up with
  /// the level above: each indent takes width from the names.
  static const _indentedLevels = 4;

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

  List<Widget> _grouped(BuildContext context, List<WorkdirFile> listing) =>
      _contents(
        context,
        workspaceTree(listing, descending: sort.descending),
        depth: 0,
      );

  /// [folder]'s files, then its folders, as rows with [depth] folder rows
  /// above them: a merged chain is one row.
  List<Widget> _contents(
    BuildContext context,
    WorkspaceFolder folder, {
    required int depth,
  }) =>
      [
        ..._rows(context, folder.files, directoryOf: (_) => null),
        for (final child in folder.folders)
          ..._folder(context, child, parent: folder, depth: depth),
      ];

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
    WorkspaceFolder folder, {
    required WorkspaceFolder parent,
    required int depth,
  }) {
    final expanded =
        isFolderExpanded(folderToggles, folder.path, topLevel: depth == 0);
    return [
      _FolderRow(
        name: folder.name,
        path: folder.path,
        // Past the last indent, a row's place no longer shows where it is.
        parentPath: depth > _indentedLevels ? parent.path : null,
        count: folder.fileCount,
        latestChange: folder.latestChange,
        expanded: expanded,
        onTap: () => onFolderToggled(folder.path, expanded: !expanded),
      ),
      if (expanded)
        Padding(
          padding: EdgeInsets.only(
            left: depth < _indentedLevels ? SoliplexSpacing.s4 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _contents(context, folder, depth: depth + 1),
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
            file: files[i],
            directory: directoryOf(files[i]),
            downloads: downloads,
            onOpenPreview: () => WorkdirPreviewPage.show(
              context: context,
              files: files,
              initialIndex: i,
              fetchBytes: onFetchBytes,
              downloads: downloads,
            ),
          ),
      ];
}

/// A workspace folder: its name, and under it the count of the files below
/// it at any depth and when the newest of them changed. Tapping it opens or
/// closes the folder.
///
/// Its icon lines up with the icons of the files at its level, and its
/// chevron sits in their download buttons' column.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.path,
    required this.parentPath,
    required this.count,
    required this.latestChange,
    required this.expanded,
    required this.onTap,
  });

  final String name;

  /// From the workspace root; shown in full on hover and to a screen reader.
  final String path;

  /// The path of the folder holding this one, shown after [name]; null to
  /// show none.
  final String? parentPath;

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
    // Muted as a tooling file's name is, and for the same reason.
    final nameStyle = isToolingPath(path)
        ? theme.textTheme.bodySmall?.copyWith(color: muted)
        : theme.textTheme.bodySmall;
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
        label: '$path, ${details.spoken}',
        child: ExcludeSemantics(
          child: FileListRow(
            leading: Icon(
              expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
              size: 16,
              color: muted,
            ),
            content: NameAndDirectory(
              path: path,
              name: Text(
                name,
                style: nameStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              directory: parentPath,
              style: nameStyle,
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
