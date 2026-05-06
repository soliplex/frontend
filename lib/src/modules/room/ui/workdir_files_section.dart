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
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final file in files)
                      _WorkdirFileRow(
                        file: file,
                        onTap: () => widget.onDownload(widget.runId, file),
                      ),
                  ],
                ),
              ),
            ),
          ),
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
  bool _isInFlight = false;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isInFlight) return;
    _isInFlight = true;
    DownloadOutcome outcome;
    try {
      outcome = await widget.onTap();
    } catch (_) {
      // The contract is `Future<DownloadOutcome>`, but defend against an
      // implementation that throws so the row doesn't get stuck in idle.
      outcome = DownloadOutcome.failed;
    } finally {
      _isInFlight = false;
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
              child: _FilenameText(
                filename: widget.file.filename,
                style: theme.textTheme.bodySmall,
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

/// Single-line filename that preserves the extension when truncating.
///
/// End-ellipsis on a long filename hides the extension, which is the
/// most informative byte for telling files apart. This widget keeps the
/// extension intact and ellipsizes the basename instead. Wraps in a
/// [Tooltip] so the full name is reachable on hover / long-press.
class _FilenameText extends StatelessWidget {
  const _FilenameText({required this.filename, this.style});

  final String filename;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final display = _fitFilename(filename, style, constraints.maxWidth);
        // Align lets the Text size to its content (instead of being stretched
        // by the parent Expanded), so the Tooltip anchors to the actual
        // painted text bounds and appears near the cursor.
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: filename,
            waitDuration: const Duration(milliseconds: 500),
            child: Text(
              display,
              style: style,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        );
      },
    );
  }
}

String _fitFilename(String name, TextStyle? style, double maxWidth) {
  if (_measure(name, style) <= maxWidth) return name;

  final dot = name.lastIndexOf('.');
  // Treat as no extension if name starts with a dot (e.g. ".bashrc"), or
  // the extension is long enough that preserving it isn't useful.
  final hasUsefulExtension = dot > 0 && name.length - dot - 1 <= 8;
  if (!hasUsefulExtension) {
    return _truncateWithEllipsis(name, '', style, maxWidth);
  }

  final basename = name.substring(0, dot);
  final extension = name.substring(dot);
  return _truncateWithEllipsis(basename, extension, style, maxWidth);
}

String _truncateWithEllipsis(
  String head,
  String tail,
  TextStyle? style,
  double maxWidth,
) {
  const ellipsis = '…';
  // Binary-search the largest prefix of [head] that still fits.
  var lo = 0;
  var hi = head.length;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    final candidate = '${head.substring(0, mid)}$ellipsis$tail';
    if (_measure(candidate, style) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return '${head.substring(0, lo)}$ellipsis$tail';
}

double _measure(String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
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
