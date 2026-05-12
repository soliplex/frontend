import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

typedef FetchWorkdirFiles = Future<List<WorkdirFile>> Function(String runId);

enum DownloadOutcome { success, cancelled, failed }

typedef DownloadWorkdirFile =
    Future<DownloadOutcome> Function(String runId, WorkdirFile file);

typedef FetchWorkdirFileBytes =
    Future<Uint8List> Function(String runId, WorkdirFile file);

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

bool _isPreviewableImage(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) return false;
  return _imageExtensions.contains(filename.substring(dot).toLowerCase());
}

class WorkdirFilesSection extends StatefulWidget {
  const WorkdirFilesSection({
    super.key,
    required this.runId,
    required this.fetchFiles,
    required this.onDownload,
    this.onPreview,
  });

  final String runId;
  final FetchWorkdirFiles fetchFiles;
  final DownloadWorkdirFile onDownload;

  /// When non-null, image files render an eye icon that opens a
  /// full-screen preview backed by bytes from this callback.
  final FetchWorkdirFileBytes? onPreview;

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
          padding: const .only(top: 8),
          child: Container(
            padding: const .symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: .circular(12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    for (final file in files)
                      _WorkdirFileRow(
                        file: file,
                        onTap: () => widget.onDownload(widget.runId, file),
                        onPreview: widget.onPreview == null
                            ? null
                            : () => widget.onPreview!(widget.runId, file),
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
  const _WorkdirFileRow({
    required this.file,
    required this.onTap,
    this.onPreview,
  });

  final WorkdirFile file;
  final Future<DownloadOutcome> Function() onTap;
  final Future<Uint8List> Function()? onPreview;

  @override
  State<_WorkdirFileRow> createState() => _WorkdirFileRowState();
}

enum _DownloadFeedback { idle, success, error }

class _WorkdirFileRowState extends State<_WorkdirFileRow> {
  _DownloadFeedback _feedback = .idle;
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
      outcome = .failed;
    } finally {
      _isInFlight = false;
    }
    if (!mounted) return;
    if (outcome == .cancelled) {
      // User dismissed the save dialog deliberately — that isn't an error
      // and doesn't warrant feedback. Stay idle.
      return;
    }
    setState(() {
      _feedback = outcome == .success ? .success : .error;
    });
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = .idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, tooltip) = switch (_feedback) {
      .idle => (Icons.download_outlined, theme.colorScheme.primary, 'Download'),
      .success => (Icons.check, theme.colorScheme.onSurfaceVariant, 'Saved'),
      .error => (Icons.error_outline, theme.colorScheme.error, "Couldn't save"),
    };
    final canPreview =
        widget.onPreview != null && _isPreviewableImage(widget.file.filename);
    return InkWell(
      onTap: _feedback == .idle ? _handleTap : null,
      borderRadius: .circular(6),
      child: Padding(
        padding: const .symmetric(vertical: 4, horizontal: 4),
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
            if (canPreview) ...[
              InkWell(
                onTap: () => _openPreview(context),
                borderRadius: .circular(6),
                child: Padding(
                  padding: const .all(2),
                  child: Tooltip(
                    message: 'Preview',
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Tooltip(
              message: tooltip,
              child: Icon(icon, size: 16, color: color),
            ),
          ],
        ),
      ),
    );
  }

  void _openPreview(BuildContext context) {
    final fetch = widget.onPreview;
    if (fetch == null) return;
    WorkdirImagePreviewPage.show(
      context: context,
      filename: widget.file.filename,
      fetchBytes: fetch,
      cannotPreview: _CannotPreview(onDownload: widget.onTap),
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
            child: Text(display, style: style, maxLines: 1, softWrap: false),
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
    textDirection: .ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// Full-screen image preview for workdir artifacts. Fetches the bytes
/// lazily via [fetchBytes] so the bytes are not pulled until the user
/// actually opens the preview.
class WorkdirImagePreviewPage extends StatefulWidget {
  const WorkdirImagePreviewPage({
    super.key,
    required this.filename,
    required this.fetchBytes,
    required this.cannotPreview,
    required this.useDialogLayout,
  });

  final String filename;
  final Future<Uint8List> Function() fetchBytes;

  /// Rendered when the fetched bytes aren't a decodable image — empty
  /// body, HTML error page, truncated download, etc. The caller owns the
  /// affordance (typically a download button); this page just renders it
  /// as a peer of the viewer.
  final Widget cannotPreview;

  final bool useDialogLayout;

  static Future<void> show({
    required BuildContext context,
    required String filename,
    required Future<Uint8List> Function() fetchBytes,
    required Widget cannotPreview,
  }) {
    final useDialog = MediaQuery.sizeOf(context).width >= 600;
    final child = WorkdirImagePreviewPage(
      filename: filename,
      fetchBytes: fetchBytes,
      cannotPreview: cannotPreview,
      useDialogLayout: useDialog,
    );
    if (useDialog) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => child,
      );
    }
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => child));
  }

  @override
  State<WorkdirImagePreviewPage> createState() =>
      _WorkdirImagePreviewPageState();
}

class _WorkdirImagePreviewPageState extends State<WorkdirImagePreviewPage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchBytes();
  }

  void _retry() {
    setState(() {
      _future = widget.fetchBytes();
    });
  }

  Widget _buildContent(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != .done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!);
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return widget.cannotPreview;
        }
        return _ImageOrFallback(bytes: bytes, fallback: widget.cannotPreview);
      },
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final theme = Theme.of(context);
    // 404 is permanent for this session — the file is gone between list
    // and preview. Retrying just refetches the same 404, so we show a
    // dedicated "gone" state without a Retry button. The dialog's
    // titlebar X is the way out.
    if (error is NotFoundException) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('File no longer exists', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text("Couldn't load preview", style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.filename,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useDialogLayout) {
      return Dialog(
        insetPadding: const .all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 800,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: .min,
            children: [
              _buildTitleBar(context),
              Expanded(child: _buildContent(context)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filename, maxLines: 1, overflow: .ellipsis),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
      body: _buildContent(context),
    );
  }
}

/// Renders [bytes] in an [InteractiveViewer]. If [Image.memory]'s
/// decoder rejects the bytes, swaps in [fallback] as a peer of (not a
/// descendant of) the viewer so its controls aren't pannable/zoomable.
///
/// Decode-failure state is owned here, not on the parent, so that a
/// fresh widget instance (different bytes) starts clean.
class _ImageOrFallback extends StatefulWidget {
  const _ImageOrFallback({required this.bytes, required this.fallback});

  final Uint8List bytes;
  final Widget fallback;

  @override
  State<_ImageOrFallback> createState() => _ImageOrFallbackState();
}

class _ImageOrFallbackState extends State<_ImageOrFallback> {
  bool _failed = false;

  @override
  void didUpdateWidget(_ImageOrFallback old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _failed = false;
    }
  }

  void _markFailed() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    return Center(
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 4.0,
        child: Image.memory(
          widget.bytes,
          fit: .contain,
          errorBuilder: (_, _, _) {
            _markFailed();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Rendered when the bytes can't be displayed as an image — empty
/// payload or post-fetch decode failure. Sits as a peer of
/// [InteractiveViewer], not a descendant, so its Download button is not
/// pannable/zoomable. Mirrors the file-row download feedback pattern
/// (icon swap, no SnackBar).
class _CannotPreview extends StatefulWidget {
  const _CannotPreview({required this.onDownload});

  final Future<DownloadOutcome> Function() onDownload;

  @override
  State<_CannotPreview> createState() => _CannotPreviewState();
}

class _CannotPreviewState extends State<_CannotPreview> {
  _DownloadFeedback _feedback = .idle;
  bool _inFlight = false;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleDownload() async {
    if (_inFlight) return;
    _inFlight = true;
    DownloadOutcome outcome;
    try {
      outcome = await widget.onDownload();
    } catch (_) {
      outcome = .failed;
    } finally {
      _inFlight = false;
    }
    if (!mounted) return;
    if (outcome == .cancelled) return;
    setState(() {
      _feedback = outcome == .success ? .success : .error;
    });
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = .idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = switch (_feedback) {
      .idle => (Icons.download_outlined, 'Download'),
      .success => (Icons.check, 'Saved'),
      .error => (Icons.error_outline, "Couldn't save"),
    };
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text("Can't preview this file", style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _feedback == .idle ? _handleDownload : null,
            icon: Icon(icon),
            label: Text(label),
          ),
        ],
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
      padding: const .symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
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
            visualDensity: .compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
