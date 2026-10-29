import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/preview_icon_button.dart';
import '../../../shared/zoomable_image.dart';
import 'pager_dots.dart';
import 'workdir_preview/code_preview.dart';
import 'workdir_preview/download_feedback_button.dart';
import 'workdir_preview/download_outcome.dart';
import 'workdir_preview/json_preview.dart';
import 'workdir_preview/preview_kind.dart';
import 'workdir_preview/svg_preview.dart';
import 'workdir_preview/text_preview.dart';
import 'workdir_preview/too_large_preview.dart';

export 'workdir_preview/download_outcome.dart' show DownloadOutcome;

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.workdir_files');

/// Bytes fetched above this size route to the too-large fallback
/// instead of an in-pager renderer — decoding very large payloads in
/// the preview pager causes jank and OOMs.
const previewSizeCapBytes = 5 * 1024 * 1024;

class WorkdirFileRow extends StatelessWidget {
  const WorkdirFileRow({
    super.key,
    required this.file,
    required this.directory,
    required this.onTap,
    required this.onOpenPreview,
  });

  final WorkdirFile file;

  /// The part of [file]'s directory the row shows after its name, or `null`
  /// to show none. A row inside a folder group shows only what lies below
  /// that folder.
  final String? directory;

  final Future<DownloadOutcome> Function() onTap;

  /// Opens the preview of a previewable file: tapping the row or the eye
  /// icon invokes it (the parent opens the multi-file pager on the files of
  /// the row's group, so they are reachable via swipe). Ignored for files
  /// that cannot preview.
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = PreviewKind.from(file.filename);
    final canPreview = kind.canRender;
    // Download-only rows show the generic file icon so the leading
    // icon doesn't imply a preview is available.
    final leadingIcon =
        canPreview ? kind.rowIcon : Icons.insert_drive_file_outlined;
    return DownloadFeedbackButton(
      filename: file.filename,
      onDownload: onTap,
      logTag: 'row download callback threw',
      builder: (context, state, downloadTap) {
        final (icon, tooltip) = state.affordance;
        final color = switch (state) {
          DownloadFeedbackState.idle => theme.colorScheme.primary,
          DownloadFeedbackState.success => theme.colorScheme.onSurfaceVariant,
          DownloadFeedbackState.error => theme.colorScheme.error,
        };
        return InkWell(
          onTap: canPreview ? onOpenPreview : downloadTap,
          borderRadius: BorderRadius.circular(context.radii.sm),
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
                  child: _NameAndDirectory(
                    file: file,
                    directory: directory,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (canPreview) ...[
                  // The eye has no padding of its own, as the download
                  // button has, to keep a cut name off it.
                  const SizedBox(width: SoliplexSpacing.s1),
                  PreviewIconButton(onTap: onOpenPreview),
                  const SizedBox(width: SoliplexSpacing.s2),
                ],
                InkWell(
                  onTap: downloadTap,
                  borderRadius: BorderRadius.circular(context.radii.sm),
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
      },
    );
  }
}

/// A file's basename on one line, followed by [directory] in muted text,
/// ending in `/` so it reads as a folder rather than a label.
///
/// The basename is what a reader scans the list for, so the directory gives
/// way first: it is end-ellipsized into whatever width the basename leaves,
/// and gets none once the basename fills the row. Wraps in a [Tooltip] so the
/// full path is reachable on hover / long-press.
class _NameAndDirectory extends StatelessWidget {
  const _NameAndDirectory({
    required this.file,
    required this.directory,
    this.style,
  });

  final WorkdirFile file;
  final String? directory;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final directory = this.directory;
    final directoryStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Align lets the row size to its content (instead of being stretched
        // by the parent Expanded), so the Tooltip anchors to the painted name
        // and directory and appears near the cursor.
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: file.filename,
            waitDuration: const Duration(milliseconds: 500),
            // The label announces the full path once: the tooltip would
            // announce it a second time, and the texts would read the
            // basename, then the directory apart from it.
            excludeFromSemantics: true,
            child: Semantics(
              label: file.filename,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      // A Row leaves an inflexible child's width unbounded;
                      // the basename may take the whole row, but no more.
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: FileName(file.basename, style: style),
                    ),
                    if (directory != null)
                      Flexible(
                        child: Padding(
                          padding:
                              const EdgeInsets.only(left: SoliplexSpacing.s2),
                          child: Text(
                            '$directory/',
                            style: directoryStyle,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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

/// A file name on one line that, when cut, shortens its stem before its
/// extension.
///
/// The extension is the most informative part of a cut name, so a short one
/// (see [splitExtension]) stays whole while it fits:
/// `quarterly_report_final.xlsx` reads `quarterly_rep….xlsx`. Flutter lays
/// out and ellipsizes both parts, so the cut follows the text scale and
/// bold-text settings. Announces the whole name to a screen reader.
class FileName extends StatelessWidget {
  FileName(this.name, {super.key, this.style})
      : assert(!name.contains('/'), 'FileName takes a basename, not a path');

  /// A basename, not a path: a dot in a directory segment would be taken for
  /// the extension.
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (stem, extension) = splitExtension(name);
    return Semantics(
      label: name,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _line(stem)),
              ConstrainedBox(
                // A slot narrower than the extension cuts it rather than
                // overflowing.
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: _line(extension),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Text _line(String text) => Text(
        text,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
}

/// Splits the basename [name] into its stem and its extension, dot included.
///
/// A name with no extension (see [extensionOf]), or with one of more than 8
/// characters, which is not worth keeping whole, yields the name as the stem
/// and an empty extension.
(String, String) splitExtension(String name) {
  final extension = extensionOf(name);
  if (extension == null || extension.length > 8) return (name, '');
  final dot = name.length - extension.length - 1;
  return (name.substring(0, dot), name.substring(dot));
}

/// Full-screen preview for workdir artifacts. Fetches the bytes lazily
/// via [fetchBytes] so the bytes are not pulled until the user actually
/// opens the preview, then dispatches to a kind-specific body widget.
class WorkdirPreviewPage extends StatefulWidget {
  WorkdirPreviewPage({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.fetchBytes,
    required this.onDownload,
  })  : assert(
            files.isNotEmpty, 'WorkdirPreviewPage requires at least one file'),
        assert(initialIndex >= 0 && initialIndex < files.length,
            'initialIndex out of range');

  final List<WorkdirFile> files;
  final int initialIndex;
  final Future<Uint8List> Function(WorkdirFile file) fetchBytes;
  final Future<DownloadOutcome> Function(WorkdirFile file) onDownload;

  static Future<void> show({
    required BuildContext context,
    required List<WorkdirFile> files,
    required int initialIndex,
    required Future<Uint8List> Function(WorkdirFile file) fetchBytes,
    required Future<DownloadOutcome> Function(WorkdirFile file) onDownload,
  }) {
    assert(
        files.isNotEmpty, 'WorkdirPreviewPage.show requires non-empty files');
    final clampedIndex = initialIndex.clamp(0, files.length - 1);
    final useDialog =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
    final child = WorkdirPreviewPage(
      files: files,
      initialIndex: clampedIndex,
      fetchBytes: fetchBytes,
      onDownload: onDownload,
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
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;
  final _focusNode = FocusNode();

  /// Per-file Future cache. Keyed by [WorkdirFile] (which implements
  /// `==` / `hashCode`) so swiping or re-ordering never aliases bytes
  /// across files. Lives only for this widget's lifetime, so closing
  /// the preview frees every fetched buffer; no LRU needed.
  final _bytesCache = <WorkdirFile, Future<Uint8List>>{};

  /// Per-file retry generations so [_retry] can replace the cached
  /// future when the user hits Retry on a failed slide.
  final _retryTokens = <WorkdirFile, int>{};

  /// Per-file image rotation in quarter turns. Keyed by [WorkdirFile] so
  /// rotation persists while paging between files.
  final _rotations = <WorkdirFile, int>{};

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<Uint8List> _bytesFor(WorkdirFile file) {
    return _bytesCache.putIfAbsent(file, () => widget.fetchBytes(file));
  }

  void _retry(WorkdirFile file) {
    setState(() {
      _bytesCache.remove(file);
      _retryTokens[file] = (_retryTokens[file] ?? 0) + 1;
    });
  }

  void _rotate(WorkdirFile file) {
    setState(() {
      _rotations[file] = ((_rotations[file] ?? 0) + 1) % 4;
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.files.length) return;
    if (index == _currentIndex) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_currentIndex - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_currentIndex + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _slideFor(BuildContext context, int index) {
    final file = widget.files[index];
    final kind = PreviewKind.from(file.filename);
    final cannot = _CannotPreview(
      filename: file.filename,
      onDownload: () => widget.onDownload(file),
    );
    if (!kind.canRender) return cannot;
    return FutureBuilder<Uint8List>(
      // Bumping the retry token re-keys the FutureBuilder so it sees a
      // brand-new future after [_retry] drops the cache entry.
      key: ValueKey<int>(_retryTokens[file] ?? 0),
      future: _bytesFor(file),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!, file);
        }
        final bytes = snapshot.data!;
        if (bytes.isEmpty) {
          _logger.debug(
            'preview bytes empty',
            attributes: {'filename': file.filename},
          );
          return _CannotPreview(
            filename: file.filename,
            onDownload: () => widget.onDownload(file),
            icon: Icons.description_outlined,
            message: 'File is empty',
          );
        }
        if (bytes.length > previewSizeCapBytes) {
          _logger.debug(
            'preview bytes exceed size cap',
            attributes: {
              'filename': file.filename,
              'byteLength': bytes.length,
              'capBytes': previewSizeCapBytes,
            },
          );
          return TooLargePreview(
            filename: file.filename,
            byteSize: bytes.length,
            capBytes: previewSizeCapBytes,
            onDownload: () => widget.onDownload(file),
          );
        }
        return _PreviewBody(
          bytes: bytes,
          kind: kind,
          filename: file.filename,
          onDownload: () => widget.onDownload(file),
          rotationQuarterTurns: _rotations[file] ?? 0,
          onRotate: () => _rotate(file),
        );
      },
    );
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    WorkdirFile file,
  ) {
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
          SoliplexButton.filled(
            onPressed: () => _retry(file),
            icon: const Icon(Icons.refresh),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.files[_currentIndex];
    // The position leads so that a long directory, not the position, is
    // what the ellipsis cuts.
    final subtitle = [
      if (widget.files.length > 1)
        '${_currentIndex + 1} / ${widget.files.length}',
      if (file.directory case final directory?) '$directory/',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s2,
        SoliplexSpacing.s1,
        SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FileName(file.basename, style: theme.textTheme.titleMedium),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
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

  /// Bottom navigation strip: prev chevron, dot indicators (when the
  /// file count fits), next chevron. Hidden entirely when there is
  /// only one file — there's nowhere to go.
  Widget _buildNavBar(BuildContext context) {
    if (widget.files.length <= 1) return const SizedBox.shrink();
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < widget.files.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous',
            onPressed: hasPrev ? () => _goTo(_currentIndex - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
            child: PagerDots(
              itemCount: widget.files.length,
              currentIndex: _currentIndex,
              onGoTo: _goTo,
              labelForIndex: (i) => widget.files[i].filename,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next',
            onPressed: hasNext ? () => _goTo(_currentIndex + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPager(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: widget.files.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: _slideFor,
    );
  }

  Widget _buildShellBody(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTitleBar(context),
          Expanded(child: _buildPager(context)),
          _buildNavBar(context),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width >= SoliplexBreakpoints.tablet) {
      return Dialog(
        insetPadding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 800,
            maxHeight: size.height * 0.85,
          ),
          child: _buildShellBody(context),
        ),
      );
    }
    return Scaffold(body: SafeArea(child: _buildShellBody(context)));
  }
}

/// Routes [bytes] to the kind-specific renderer. The image branch
/// hands the raw `Uint8List` to [_ImageOrFallback]; every other
/// renderable kind is text-shaped, so we decode UTF-8 strictly here and
/// hand a `String` to the leaf widget. A strict decode failure on a
/// text-shaped extension almost always means the file is binary under
/// a misleading name — we route to a dedicated fallback rather than
/// rendering U+FFFD mojibake.
class _PreviewBody extends StatelessWidget {
  _PreviewBody({
    required this.bytes,
    required this.kind,
    required this.filename,
    required this.onDownload,
    required this.rotationQuarterTurns,
    required this.onRotate,
  }) : assert(kind.canRender, 'pdf/unknown must be guarded before this point');

  final Uint8List bytes;
  final PreviewKind kind;
  final String filename;
  final Future<DownloadOutcome> Function() onDownload;
  final int rotationQuarterTurns;
  final VoidCallback onRotate;

  Widget _fallback({required IconData icon, required String message}) =>
      _CannotPreview(
        filename: filename,
        onDownload: onDownload,
        icon: icon,
        message: message,
      );

  @override
  Widget build(BuildContext context) {
    if (kind == PreviewKind.image) {
      return ZoomableImage.controlledRotation(
        bytes: bytes,
        rotationQuarterTurns: rotationQuarterTurns,
        onRotate: onRotate,
        decodeFailureChild: _fallback(
          icon: Icons.broken_image_outlined,
          message: 'This image looks corrupt',
        ),
      );
    }
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException catch (error, stack) {
      _logger.warning(
        'text-shaped file failed strict utf8 decode',
        error: error,
        stackTrace: stack,
        attributes: {
          'filename': filename,
          'byteLength': bytes.length,
          'errorType': error.runtimeType.toString(),
        },
      );
      return _fallback(
        icon: Icons.data_object_outlined,
        message: 'This file looks binary',
      );
    }
    return switch (kind) {
      PreviewKind.svg => SvgPreview(
          content: content,
          fallback: _fallback(
            icon: Icons.broken_image_outlined,
            message: 'This SVG looks corrupt',
          ),
        ),
      PreviewKind.markdown || PreviewKind.text => TextPreview(content: content),
      PreviewKind.code || PreviewKind.html || PreviewKind.csv => CodePreview(
          content: content,
          language: kind.highlightLanguageFor(filename),
        ),
      PreviewKind.json => JsonPreview(content: content),
      PreviewKind.image || PreviewKind.pdf || PreviewKind.unknown => _fallback(
          icon: Icons.image_not_supported_outlined,
          message: "Can't preview this file",
        ),
    };
  }
}

/// Rendered when the bytes can't be displayed. [icon] and [message]
/// distinguish the cause — unsupported kind, corrupt bytes, binary
/// content under a text extension, or empty payload — so the user
/// isn't left guessing why the preview pane is showing a fallback. Sits
/// as a peer of the actual preview body, not a descendant, so its
/// Download button is not pannable/zoomable.
class _CannotPreview extends StatelessWidget {
  const _CannotPreview({
    required this.filename,
    required this.onDownload,
    this.icon = Icons.image_not_supported_outlined,
    this.message = "Can't preview this file",
  });

  final String filename;
  final Future<DownloadOutcome> Function() onDownload;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          DownloadFeedbackButton(
            filename: filename,
            onDownload: onDownload,
            logTag: 'preview-fallback download callback threw',
            builder: (context, state, onTap) {
              final (btnIcon, label) = state.affordance;
              return SoliplexButton.filled(
                onPressed: onTap,
                icon: Icon(btnIcon),
                child: Text(label),
              );
            },
          ),
        ],
      ),
    );
  }
}

class WorkdirErrorRow extends StatelessWidget {
  const WorkdirErrorRow({
    super.key,
    required this.onRetry,
    required this.isRetrying,
    required this.reason,
  });

  final VoidCallback onRetry;

  /// Whether a retry is in flight; the Retry button turns into a disabled one
  /// showing a spinner, so the row keeps its size and cannot queue another
  /// retry.
  final bool isRetrying;

  /// Why the list failed, shown after the fixed message; text that is safe to
  /// show.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Shared by the Retry icon and the spinner that replaces it, so the row
    // keeps its height while a retry is in flight.
    const retryGlyphSize = 16.0;
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
              "Couldn't load files — $reason",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          IconButton(
            onPressed: isRetrying ? null : onRetry,
            icon: isRetrying
                ? const SizedBox.square(
                    dimension: retryGlyphSize,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            iconSize: retryGlyphSize,
            tooltip: isRetrying ? 'Retrying' : 'Retry',
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
