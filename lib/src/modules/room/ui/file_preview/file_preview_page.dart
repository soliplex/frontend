import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/selectable_content.dart';
import '../../../../shared/zoomable_image.dart';
import '../../file_downloads.dart';
import '../../file_source.dart' show fileFetchFailureReason;
import '../content_viewer/content_viewer.dart';
import '../file_list_row.dart';
import '../markdown/flutter_markdown_plus_renderer.dart';
import '../pager_dots.dart';
import '../start_download.dart';
import 'download_feedback.dart';
import 'preview_kind.dart';
import 'too_large_preview.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.file_preview');

/// A file listed, or fetched, above this size shows the too-large fallback
/// instead of an in-pager renderer — decoding very large payloads in
/// the preview pager causes jank and OOMs.
const previewSizeCapBytes = 5 * 1024 * 1024;

/// Full-screen preview of workspace files and uploads. Fetches the bytes
/// lazily via [fetchBytes] so the bytes are not pulled until the user
/// actually opens the preview, then dispatches to a kind-specific body
/// widget.
class FilePreviewPage extends StatefulWidget {
  FilePreviewPage({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.fetchBytes,
    required this.downloads,
  })  : assert(files.isNotEmpty, 'FilePreviewPage requires at least one file'),
        assert(initialIndex >= 0 && initialIndex < files.length,
            'initialIndex out of range');

  final List<ServedFile> files;
  final int initialIndex;
  final Future<Uint8List> Function(ServedFile file) fetchBytes;

  /// Where the page's download affordances read each file's download and
  /// start it, shared with the file rows.
  final FileDownloads downloads;

  static Future<void> show({
    required BuildContext context,
    required List<ServedFile> files,
    required int initialIndex,
    required Future<Uint8List> Function(ServedFile file) fetchBytes,
    required FileDownloads downloads,
  }) {
    assert(files.isNotEmpty, 'FilePreviewPage.show requires non-empty files');
    final clampedIndex = initialIndex.clamp(0, files.length - 1);
    final useDialog =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
    final child = FilePreviewPage(
      files: files,
      initialIndex: clampedIndex,
      fetchBytes: fetchBytes,
      downloads: downloads,
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
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;
  final _focusNode = FocusNode();

  /// Per-file Future cache. Keyed by the file ([WorkdirFile] and
  /// [FileUpload] both implement `==` / `hashCode`) so swiping or
  /// re-ordering never aliases bytes across files. Lives only for this
  /// widget's lifetime, so closing the preview frees every fetched buffer; no
  /// LRU needed.
  final _bytesCache = <ServedFile, Future<Uint8List>>{};

  /// Per-file retry generations so [_retry] can replace the cached
  /// future when the user hits Retry on a failed slide.
  final _retryTokens = <ServedFile, int>{};

  /// Per-file image rotation in quarter turns. Keyed by [ServedFile] so
  /// rotation persists while paging between files.
  final _rotations = <ServedFile, int>{};

  final _titleSelection = _TitleSelection();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _titleSelection.dispose();
    super.dispose();
  }

  Future<Uint8List> _bytesFor(ServedFile file) {
    return _bytesCache.putIfAbsent(file, () => widget.fetchBytes(file));
  }

  void _retry(ServedFile file) {
    setState(() {
      _bytesCache.remove(file);
      _retryTokens[file] = (_retryTokens[file] ?? 0) + 1;
    });
  }

  void _rotate(ServedFile file) {
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
    final download = _DownloadButton(file: file, downloads: widget.downloads);
    final cannot = _CannotPreview(downloadButton: download);
    if (!kind.canRender) return cannot;
    // A file listed over the cap is not fetched: the whole file would be
    // held in memory only to be refused. Any file fetched is checked against
    // the cap below, whatever its listed size.
    if (file.sizeBytes case final size? when size > previewSizeCapBytes) {
      return TooLargePreview(
        byteSize: size,
        capBytes: previewSizeCapBytes,
        downloadButton: download,
      );
    }
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
            downloadButton: download,
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
            byteSize: bytes.length,
            capBytes: previewSizeCapBytes,
            downloadButton: download,
          );
        }
        return _PreviewBody(
          bytes: bytes,
          kind: kind,
          filename: file.filename,
          downloadButton: download,
          rotationQuarterTurns: _rotations[file] ?? 0,
          onRotate: () => _rotate(file),
        );
      },
    );
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    ServedFile file,
  ) {
    final theme = Theme.of(context);
    final reason = fileFetchFailureReason(error);
    // A 404 or a 403 is permanent for this session: retrying refetches the
    // same answer, so it shows without a Retry button. The title bar's Close
    // is the way out.
    if (error is NotFoundException || error is PermissionDeniedException) {
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
            Text(reason, style: theme.textTheme.bodyMedium),
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
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            reason,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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

  /// The shown file's name, then its position and directory, both wrapping
  /// whole: this is where a name the list cuts is read in full. Taller than
  /// [maxTitleHeight], the two scroll there, so the file keeps the rest of
  /// the preview.
  Widget _buildTitleBar(
    BuildContext context, {
    required double maxTitleHeight,
  }) {
    final theme = Theme.of(context);
    final file = widget.files[_currentIndex];
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
        // A title of several lines keeps the actions at its top.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // At least as tall as the actions, so a short title is
            // centred on them.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: kMinInteractiveDimension,
                maxHeight: maxTitleHeight,
              ),
              // Its title's height, not the most the constraints allow.
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: SingleChildScrollView(
                  child: SelectableContent(
                    child: SelectionContainer(
                      delegate: _titleSelection,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _breakableAtSeparators(file.basename),
                            semanticsLabel: file.basename,
                            style: theme.textTheme.titleMedium,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              _breakableAtSeparators(subtitle),
                              semanticsLabel: subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _TitleBarDownload(file: file, downloads: widget.downloads),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            visualDensity: _titleBarActionDensity,
            style:
                IconButton.styleFrom(tapTargetSize: _titleBarActionTapTarget),
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
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(
              context,
              // A third of the preview, so even a name of hundreds of
              // characters leaves the file most of it.
              maxTitleHeight: math.max(
                kMinInteractiveDimension,
                constraints.maxHeight / 3,
              ),
            ),
            Expanded(child: _buildPager(context)),
            _buildNavBar(context),
          ],
        ),
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
    required this.downloadButton,
    required this.rotationQuarterTurns,
    required this.onRotate,
  }) : assert(kind.canRender, 'pdf/unknown must be guarded before this point');

  final Uint8List bytes;
  final PreviewKind kind;
  final String filename;
  final Widget downloadButton;
  final int rotationQuarterTurns;
  final VoidCallback onRotate;

  Widget _fallback({required IconData icon, required String message}) =>
      _CannotPreview(
        downloadButton: downloadButton,
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
      PreviewKind.markdown => SingleChildScrollView(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: FlutterMarkdownPlusRenderer(data: content),
        ),
      PreviewKind.svg ||
      PreviewKind.code ||
      PreviewKind.text ||
      PreviewKind.html ||
      PreviewKind.csv ||
      PreviewKind.json =>
        ContentViewer(
          language: languageForFilename(filename),
          content: content,
          fill: true,
        ),
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
    required this.downloadButton,
    this.icon = Icons.image_not_supported_outlined,
    this.message = "Can't preview this file",
  });

  final Widget downloadButton;
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
          downloadButton,
        ],
      ),
    );
  }
}

/// The labelled Download button of a preview page that cannot show [file],
/// showing [file]'s download in [downloads], and under it why a failed one
/// failed.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.file, required this.downloads});

  final ServedFile file;
  final FileDownloads downloads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Watch((context) {
      final state = downloads.stateOf(file);
      final (icon, label) = state.buttonAffordance;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Save a copy of ${file.basename}',
            // Above, so a pointer still over the button after a failed
            // download leaves the reason under it in view.
            preferBelow: false,
            child: SoliplexButton.filled(
              onPressed: downloads.canStart(file)
                  ? () => unawaited(startDownload(context, downloads, file))
                  : null,
              isLoading: state is DownloadRunning,
              icon: Icon(icon),
              child: Text(label),
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          // Always laid out, empty but for a failure, so the page around
          // it, centred, does not move when a reason comes and goes.
          Text(
            switch (state) {
              DownloadFailed(:final reason) => reason,
              DownloadIdle() || DownloadRunning() || DownloadSaved() => '',
            },
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      );
    });
  }
}

/// [text] with a place to break a line after each `_` and `.`, so a name too
/// long for its line breaks between its words where it can. The line breaker
/// already breaks after `-` and `/`.
String _breakableAtSeparators(String text) =>
    text.replaceAllMapped(RegExp('[_.]'), (m) => '${m[0]}\u200B');

/// The preview title's selection: a copy leaves out zero-width spaces, which
/// [_breakableAtSeparators] adds to the shown text.
class _TitleSelection extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content == null) return null;
    return SelectedContent(
      plainText: content.plainText.replaceAll('\u200B', ''),
    );
  }
}

// Together these make the title bar's action buttons
// [kMinInteractiveDimension] square on every platform, which the title's
// least height matches: Material makes them smaller on desktop.
const _titleBarActionDensity = VisualDensity.standard;
const _titleBarActionTapTarget = MaterialTapTargetSize.padded;

/// The preview title bar's download action for [file], beside Close: its
/// outcome shows in the icon, as a row's does.
class _TitleBarDownload extends StatelessWidget {
  const _TitleBarDownload({required this.file, required this.downloads});

  final ServedFile file;
  final FileDownloads downloads;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((context) {
      final state = downloads.stateOf(file);
      final (icon, label) = state.affordance;
      // Colored here, not by the button, so the outcome keeps its color
      // while the button is disabled.
      final color = state.outcomeColor(colorScheme);
      return IconButton(
        // A spinner in the button's place keeps the button's size, so Close
        // does not move; the button's tooltip already names it to a screen
        // reader.
        icon: state is DownloadRunning
            ? ExcludeSemantics(child: ProgressRing(label: label))
            : Icon(icon, color: color),
        tooltip: label,
        visualDensity: _titleBarActionDensity,
        style: IconButton.styleFrom(tapTargetSize: _titleBarActionTapTarget),
        onPressed: downloads.canStart(file)
            ? () => unawaited(startDownload(context, downloads, file))
            : null,
      );
    });
  }
}
