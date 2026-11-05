import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_design/soliplex_design.dart';

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
        expanded: expanded,
        onTap: () => onFolderToggled(group.name, expanded: !expanded),
      ),
      if (expanded)
        Padding(
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

/// A first-level workspace folder: its name and file count. Tapping it opens
/// or closes the folder's files.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final countLabel = '$count ${count == 1 ? 'file' : 'files'}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: Semantics(
        button: true,
        expanded: expanded,
        label: '$name, $countLabel',
        child: ExcludeSemantics(
          child: FileListRow(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: muted,
                ),
                // With no gap, the folder icon lines up with the icons of
                // its files, which indent by s4.
                Icon(
                  expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                  size: 16,
                  color: muted,
                ),
              ],
            ),
            // The name gives way first; the muted count stays whole. It
            // follows the name rather than sitting at the row's end, where
            // it would line up with the file rows' action icons and read as
            // an action.
            content: Row(
              children: [
                Flexible(
                  child: FullNameTooltip(
                    name: name,
                    child: Text(
                      name,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Text(
                  countLabel,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
