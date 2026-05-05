import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

typedef FetchWorkdirFiles = Future<List<WorkdirFile>> Function(String runId);

typedef DownloadWorkdirFile = Future<void> Function(
  String runId,
  WorkdirFile file,
);

class WorkdirFilesSection extends StatefulWidget {
  const WorkdirFilesSection({
    super.key,
    required this.runId,
    required this.fetchFiles,
    required this.onDownload,
  });

  final String runId;
  final FetchWorkdirFiles fetchFiles;
  final DownloadWorkdirFile onDownload;

  @override
  State<WorkdirFilesSection> createState() => _WorkdirFilesSectionState();
}

class _WorkdirFilesSectionState extends State<WorkdirFilesSection> {
  late Future<List<WorkdirFile>> _future = widget.fetchFiles(widget.runId);

  void _retry() {
    setState(() {
      _future = widget.fetchFiles(widget.runId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkdirFile>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _WorkdirErrorRow(onRetry: _retry);
        }
        final files = snapshot.data;
        if (files == null || files.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            for (final file in files)
              _WorkdirFileRow(
                file: file,
                onTap: () => widget.onDownload(widget.runId, file),
              ),
          ],
        );
      },
    );
  }
}

class _WorkdirFileRow extends StatelessWidget {
  const _WorkdirFileRow({required this.file, required this.onTap});

  final WorkdirFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.filename,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.download_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkdirErrorRow extends StatelessWidget {
  const _WorkdirErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't load files",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          IconButton(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            iconSize: 16,
            tooltip: 'Retry',
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
