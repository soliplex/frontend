import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import '../../../design/design.dart';
import 'workdir_preview/code_extensions.dart';
import 'workdir_preview/code_preview.dart';
import 'workdir_preview/json_preview.dart';
import 'workdir_preview/preview_kind.dart';
import 'workdir_preview/svg_preview.dart';
import 'workdir_preview/text_preview.dart';
import 'workdir_preview/too_large_preview.dart';

typedef FetchWorkdirFiles = Future<List<WorkdirFile>> Function(String runId);

enum DownloadOutcome { success, cancelled, failed }

typedef DownloadWorkdirFile = Future<DownloadOutcome> Function(
  String runId,
  WorkdirFile file,
);

typedef FetchWorkdirFileBytes = Future<Uint8List> Function(
  String runId,
  WorkdirFile file,
);

/// Files larger than this stay as a download — decoding a 50 MB log or
/// a 25 MB PDF in the chat scroller is a guaranteed jank/OOM source.
const previewSizeCapBytes = 5 * 1024 * 1024;

bool _canPreview(String filename) {
  final kind = detectPreviewKind(filename);
  // PDFs need a renderer this app deliberately doesn't pull in — fall
  // through to download. Unknown extensions have nowhere useful to go.
  return kind != PreviewKind.unknown && kind != PreviewKind.pdf;
}

IconData _leadingIconFor(PreviewKind kind) => switch (kind) {
      PreviewKind.image => Icons.image_outlined,
      PreviewKind.svg => Icons.image_outlined,
      PreviewKind.markdown => Icons.article_outlined,
      PreviewKind.code => Icons.code,
      PreviewKind.text => Icons.description_outlined,
      PreviewKind.html => Icons.code,
      PreviewKind.csv => Icons.table_chart_outlined,
      PreviewKind.json => Icons.data_object,
      PreviewKind.pdf => Icons.picture_as_pdf_outlined,
      PreviewKind.unknown => Icons.insert_drive_file_outlined,
    };

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

  /// When non-null, previewable files render an eye icon that opens a
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
          padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: SoliplexSpacing.s1, horizontal: SoliplexSpacing.s2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(soliplexRadii.md),
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
    final kind = detectPreviewKind(widget.file.filename);
    final canPreview =
        widget.onPreview != null && _canPreview(widget.file.filename);
    // Row icon shows the kind only when the row can actually preview —
    // a kind-specific icon on a row that downloads would over-promise.
    final leadingIcon =
        canPreview ? _leadingIconFor(kind) : Icons.insert_drive_file_outlined;
    final downloadEnabled = _feedback == _DownloadFeedback.idle;
    return InkWell(
      onTap: canPreview
          ? () => _openPreview(context, kind)
          : (downloadEnabled ? _handleTap : null),
      borderRadius: BorderRadius.circular(soliplexRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: SoliplexSpacing.s1, horizontal: SoliplexSpacing.s1),
        child: Row(
          children: [
            Icon(
              leadingIcon,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: SoliplexSpacing.s2),
            Expanded(
              child: _FilenameText(
                filename: widget.file.filename,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (canPreview) ...[
              InkWell(
                onTap: () => _openPreview(context, kind),
                borderRadius: BorderRadius.circular(soliplexRadii.sm),
                child: Padding(
                  padding: const EdgeInsets.all(SoliplexSpacing.s1),
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
              const SizedBox(width: SoliplexSpacing.s2),
            ],
            InkWell(
              onTap: downloadEnabled ? _handleTap : null,
              borderRadius: BorderRadius.circular(soliplexRadii.sm),
              child: Padding(
                padding: const EdgeInsets.all(SoliplexSpacing.s1),
                child: Tooltip(
                  message: tooltip,
                  child: Icon(icon, size: 16, color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPreview(BuildContext context, PreviewKind kind) {
    final fetch = widget.onPreview;
    if (fetch == null) return;
    WorkdirPreviewPage.show(
      context: context,
      filename: widget.file.filename,
      kind: kind,
      fetchBytes: fetch,
      onDownload: widget.onTap,
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

/// Full-screen preview for workdir artifacts. Fetches the bytes lazily
/// via [fetchBytes] so the bytes are not pulled until the user actually
/// opens the preview, then dispatches to a kind-specific body widget.
class WorkdirPreviewPage extends StatefulWidget {
  const WorkdirPreviewPage({
    super.key,
    required this.filename,
    required this.kind,
    required this.fetchBytes,
    required this.onDownload,
    required this.useDialogLayout,
  });

  final String filename;
  final PreviewKind kind;
  final Future<Uint8List> Function() fetchBytes;
  final Future<DownloadOutcome> Function() onDownload;
  final bool useDialogLayout;

  static Future<void> show({
    required BuildContext context,
    required String filename,
    required PreviewKind kind,
    required Future<Uint8List> Function() fetchBytes,
    required Future<DownloadOutcome> Function() onDownload,
  }) {
    final useDialog =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
    final child = WorkdirPreviewPage(
      filename: filename,
      kind: kind,
      fetchBytes: fetchBytes,
      onDownload: onDownload,
      useDialogLayout: useDialog,
    );
    if (useDialog) {
      // Zero-duration transition — showDialog's default fade adds a
      // visible flash when the user is expecting an immediate jump to
      // the preview.
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        barrierColor: Colors.black54,
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => child,
      );
    }
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => child,
      ),
    );
  }

  @override
  State<WorkdirPreviewPage> createState() => _WorkdirPreviewPageState();
}

class _WorkdirPreviewPageState extends State<WorkdirPreviewPage> {
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

  Widget _cannotPreview() => _CannotPreview(onDownload: widget.onDownload);

  Widget _buildContent(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!);
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _cannotPreview();
        }
        if (bytes.length > previewSizeCapBytes) {
          return TooLargePreview(
            byteSize: bytes.length,
            capBytes: previewSizeCapBytes,
            onDownload: widget.onDownload,
          );
        }
        return _PreviewBody(
          bytes: bytes,
          kind: widget.kind,
          filename: widget.filename,
          fallback: _cannotPreview(),
        );
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: SoliplexSpacing.s3),
            Text(
              'File no longer exists',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            "Couldn't load preview",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s4),
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
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s3,
        SoliplexSpacing.s2,
        SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.filename,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        insetPadding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 800,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        title: Text(
          widget.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
      body: _buildContent(context),
    );
  }
}

/// Routes [bytes] to the kind-specific renderer. The image renderer
/// keeps its decode-failure fallback (the only kind that needs one in
/// practice — bad image bytes are common, bad code/text/json bytes
/// just render as garbled characters).
class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.bytes,
    required this.kind,
    required this.filename,
    required this.fallback,
  });

  final Uint8List bytes;
  final PreviewKind kind;
  final String filename;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      PreviewKind.image => _ImageOrFallback(bytes: bytes, fallback: fallback),
      PreviewKind.svg => SvgPreview(bytes: bytes, fallback: fallback),
      PreviewKind.markdown => TextPreview(bytes: bytes),
      PreviewKind.text => TextPreview(bytes: bytes),
      PreviewKind.code => CodePreview(
          bytes: bytes,
          language: languageForExtension(_extensionOf(filename) ?? ''),
        ),
      PreviewKind.html => CodePreview(bytes: bytes, language: 'xml'),
      PreviewKind.csv => CodePreview(bytes: bytes, language: 'plaintext'),
      PreviewKind.json => JsonPreview(bytes: bytes),
      // Unreachable: pdf and unknown rows can't be opened — they
      // bypass _openPreview entirely.
      PreviewKind.pdf || PreviewKind.unknown => fallback,
    };
  }
}

String? _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) return null;
  return filename.substring(dot + 1);
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
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) {
            _markFailed();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Rendered when the bytes can't be displayed — empty payload,
/// decode failure, or an unknown/PDF kind that fell through. Sits as a
/// peer of the actual preview body, not a descendant, so its Download
/// button is not pannable/zoomable. Mirrors the file-row download
/// feedback pattern (icon swap, no SnackBar).
class _CannotPreview extends StatefulWidget {
  const _CannotPreview({required this.onDownload});

  final Future<DownloadOutcome> Function() onDownload;

  @override
  State<_CannotPreview> createState() => _CannotPreviewState();
}

class _CannotPreviewState extends State<_CannotPreview> {
  _DownloadFeedback _feedback = _DownloadFeedback.idle;
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
      outcome = DownloadOutcome.failed;
    } finally {
      _inFlight = false;
    }
    if (!mounted) return;
    if (outcome == DownloadOutcome.cancelled) return;
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
    final (icon, label) = switch (_feedback) {
      _DownloadFeedback.idle => (Icons.download_outlined, 'Download'),
      _DownloadFeedback.success => (Icons.check, 'Saved'),
      _DownloadFeedback.error => (Icons.error_outline, "Couldn't save"),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            "Can't preview this file",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          FilledButton.icon(
            onPressed:
                _feedback == _DownloadFeedback.idle ? _handleDownload : null,
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
