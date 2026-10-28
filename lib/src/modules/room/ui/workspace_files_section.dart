import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_design/soliplex_design.dart';

import '../workdir_files_status.dart';
import '../workspace_groups.dart';
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

/// The files panel's list of the thread's sandbox workspace: its root files,
/// then one row per first-level folder that opens and closes the folder's
/// files. Renders nothing while loading or when empty.
class WorkspaceFilesSection extends StatelessWidget {
  const WorkspaceFilesSection({
    super.key,
    required this.status,
    required this.onDownload,
    required this.onFetchBytes,
    required this.onRetry,
    required this.folderToggles,
    required this.onFolderToggled,
  });

  final WorkdirFilesStatus status;
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
    final grouped = groupByFirstFolder(listing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const FilePanelSectionLabel('Workspace'),
        ..._rows(context, grouped.files, folder: null),
        for (final group in grouped.folders) ..._folder(context, group),
      ],
    );
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
            children: _rows(context, group.files, folder: group.name),
          ),
        ),
    ];
  }

  /// Rows for one group of files: the root files, or one folder's. The
  /// preview a row opens pages through that group only.
  List<Widget> _rows(
    BuildContext context,
    List<WorkdirFile> files, {
    required String? folder,
  }) =>
      [
        for (var i = 0; i < files.length; i++)
          WorkdirFileRow(
            file: files[i],
            directory:
                folder == null ? null : directoryWithin(files[i], folder),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: Semantics(
        button: true,
        expanded: expanded,
        label: '$name, $count ${count == 1 ? 'file' : 'files'}',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s1),
            child: Row(
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
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoliplexSpacing.s1,
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
