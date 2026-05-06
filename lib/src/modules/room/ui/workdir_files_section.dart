import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

typedef FetchWorkdirFiles = Future<List<WorkdirFile>> Function(String runId);

enum DownloadOutcome { success, cancelled, failed }

typedef DownloadWorkdirFile = Future<DownloadOutcome> Function(
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

class _WorkdirFileRow extends StatefulWidget {
  const _WorkdirFileRow({required this.file, required this.onTap});

  final WorkdirFile file;
  final Future<DownloadOutcome> Function() onTap;

  @override
  State<_WorkdirFileRow> createState() => _WorkdirFileRowState();
}

enum _DownloadFeedback { idle, success, error }

class _WorkdirFileRowState extends State<_WorkdirFileRow> {
  _DownloadFeedback _feedback = _DownloadFeedback.idle;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    DownloadOutcome outcome;
    try {
      outcome = await widget.onTap();
    } catch (_) {
      // The contract is `Future<DownloadOutcome>`, but defend against an
      // implementation that throws so the row doesn't get stuck in idle.
      outcome = DownloadOutcome.failed;
    }
    if (!mounted) return;
    if (outcome == DownloadOutcome.cancelled) {
      // User dismissed the save dialog deliberately — that isn't an error
      // and doesn't warrant feedback. Stay idle.
      return;
    }
    setState(() {
      _feedback = outcome == DownloadOutcome.success
          ? _DownloadFeedback.success
          : _DownloadFeedback.error;
    });
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = _DownloadFeedback.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, tooltip) = switch (_feedback) {
      _DownloadFeedback.idle => (
          Icons.download_outlined,
          theme.colorScheme.primary,
          'Download',
        ),
      _DownloadFeedback.success => (
          Icons.check,
          theme.colorScheme.onSurfaceVariant,
          'Saved',
        ),
      _DownloadFeedback.error => (
          Icons.error_outline,
          theme.colorScheme.error,
          "Couldn't save",
        ),
    };
    return InkWell(
      onTap: _feedback == _DownloadFeedback.idle ? _handleTap : null,
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
                widget.file.filename,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Tooltip(
              message: tooltip,
              child: Icon(icon, size: 16, color: color),
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
