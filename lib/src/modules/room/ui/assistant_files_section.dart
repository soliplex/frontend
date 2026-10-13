import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;

import '../workdir_files_status.dart';
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

/// The files panel's list of what the assistant wrote to the thread's
/// sandbox workspace. Renders nothing while loading or when empty.
class AssistantFilesSection extends StatelessWidget {
  const AssistantFilesSection({
    super.key,
    required this.status,
    required this.onDownload,
    required this.onFetchBytes,
    required this.onRetry,
  });

  final WorkdirFilesStatus status;
  final Future<DownloadOutcome> Function(WorkdirFile file) onDownload;
  final Future<Uint8List> Function(WorkdirFile file) onFetchBytes;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      WorkdirFilesLoading() => const SizedBox.shrink(),
      WorkdirFilesLoaded(:final files) when files.isEmpty =>
        const SizedBox.shrink(),
      WorkdirFilesLoaded(:final files, :final unseen) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const FilePanelSectionLabel('From the assistant'),
            for (var i = 0; i < files.length; i++)
              WorkdirFileRow(
                file: files[i],
                isNew: unseen.contains(files[i].filename),
                onTap: () => onDownload(files[i]),
                onOpenPreview: () => WorkdirPreviewPage.show(
                  context: context,
                  files: files,
                  initialIndex: i,
                  fetchBytes: onFetchBytes,
                  onDownload: onDownload,
                ),
              ),
          ],
        ),
      WorkdirFilesFailed(:final error, :final retrying) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const FilePanelSectionLabel('From the assistant'),
            WorkdirErrorRow(
              onRetry: onRetry,
              isRetrying: retrying,
              reason: workdirErrorMessage(error),
            ),
          ],
        ),
    };
  }
}
