import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/zoomable_image.dart';
import '../file_downloads.dart';
import 'file_list_row.dart';
import 'pager_dots.dart';
import 'workdir_preview/code_preview.dart';
import 'workdir_preview/download_feedback.dart';
import 'workdir_preview/json_preview.dart';
import 'workdir_preview/preview_kind.dart';
import 'workdir_preview/svg_preview.dart';
import 'workdir_preview/text_preview.dart';
import 'workdir_preview/too_large_preview.dart';

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
    required this.downloads,
    required this.onOpenPreview,
  });

  final WorkdirFile file;

  /// The directory the row shows after [file]'s name, or `null` to show
  /// none, as every row under Folders does.
  final String? directory;

  /// Where the row's download action reads [file]'s download and starts it.
  final FileDownloads downloads;

  /// Opens the preview at [file]: tapping the row invokes it, and so does
  /// the eye icon a previewable file shows (the parent opens the multi-file
  /// pager on the files of the row's group, so they are reachable via
  /// swipe). A file that cannot preview opens at its "Can't preview" page,
  /// which offers the download.
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = PreviewKind.from(file.filename);
    final canPreview = kind.canRender;
    // Rows that can't preview show the generic file icon so the leading
    // icon doesn't imply their content can be shown.
    final leadingIcon =
        canPreview ? kind.rowIcon : Icons.insert_drive_file_outlined;
    final nameStyle = theme.textTheme.bodySmall;
    return InkWell(
      onTap: onOpenPreview,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: FileListRow(
        details: DetailsLine.file(
          modifiedAt: file.modifiedAt,
          sizeBytes: file.sizeBytes,
        ),
        leading: Icon(
          leadingIcon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        content: NameAndDirectory(
          path: file.filename,
          name: FileName(file.basename, style: nameStyle),
          directory: directory,
          style: nameStyle,
        ),
        actions: [
          if (canPreview)
            FileRowAction(
              icon: Icons.visibility_outlined,
              tooltip: 'Preview',
              onTap: onOpenPreview,
            ),
          Watch((context) {
            final state = downloads.stateOf(file);
            final (icon, tooltip) = state.affordance;
            if (state is DownloadRunning) {
              return FileRowActionProgress(label: tooltip);
            }
            return FileRowAction(
              icon: icon,
              tooltip: tooltip,
              onTap:
                  downloads.canStart(file) ? () => downloads.start(file) : null,
              color: state.outcomeColor(theme.colorScheme) ??
                  theme.colorScheme.primary,
            );
          }),
        ],
      ),
    );
  }
}

/// A file's or folder's [name] on one line, followed by [directory] in
/// muted text, ending in `/` so it reads as a folder, not as a tag on the
/// name.
///
/// The name is what a reader scans the list for, so the directory gives
/// way first: it is cut into whatever width the name leaves, keeping its last
/// folder (see [FolderPath]), and gets none once the name fills the row.
/// Wraps in a
/// [FullNameTooltip], so the full [path] shows on hover or long press and
/// the text is not selectable.
class NameAndDirectory extends StatelessWidget {
  const NameAndDirectory({
    super.key,
    required this.path,
    required this.name,
    required this.directory,
    this.style,
  });

  /// The entry's path from the workspace root.
  final String path;

  /// The entry's name, which the caller keeps to one line and draws in
  /// [style].
  final Widget name;

  final String? directory;

  /// The name's style, which the directory takes muted.
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
          child: FullNameTooltip(
            name: path,
            // The label announces the full path once: the texts would read
            // the name, then the directory apart from it.
            child: Semantics(
              label: path,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      // A Row leaves an inflexible child's width unbounded;
                      // the name may take the whole row, but no more.
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: name,
                    ),
                    if (directory != null)
                      Flexible(
                        child: Padding(
                          padding:
                              const EdgeInsets.only(left: SoliplexSpacing.s2),
                          child: FolderPath(
                            directory,
                            endsWithSlash: true,
                            style: directoryStyle,
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

/// A file name on one line that, when cut, shortens its middle.
///
/// The end of a name is the most informative part of a cut one: names an
/// agent writes often differ only just before the extension, as dates and
/// versions do. So the end [splitForCut] keeps stays whole while it fits:
/// `quarterly_report_final.xlsx` reads `quarterly_r…_final.xlsx`. Flutter
/// lays out and ellipsizes both parts, so the cut follows the text scale and
/// bold-text settings. Announces the whole name to a screen reader.
class FileName extends StatelessWidget {
  FileName(this.name, {super.key, this.style})
      : assert(!name.contains('/'), 'FileName takes a basename, not a path');

  /// A basename, not a path: a row shows a file's directory apart from its
  /// name.
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (head, end) = splitForCut(name);
    return Semantics(
      label: name,
      child: ExcludeSemantics(
        child: _TwoPartLine(
          head: head,
          style: style,
          end: _cutLine(end, style),
        ),
      ),
    );
  }
}

/// A folder's path on one line that, when cut, keeps its last folder whole:
/// `project/src/core` reads `project/s…/core`, and `raw/archive/2023`
/// reads `raw/a…/2023`. A last folder too long alone loses its middle, as a
/// [FileName] does: `…/experiment_r…_11_05`. The folders above it give way
/// first, then the last folder's head (see [splitPathForCut]).
///
/// Leaves the path's announcement to its row, which names the whole path.
class FolderPath extends StatelessWidget {
  const FolderPath(
    this.path, {
    super.key,
    required this.endsWithSlash,
    this.style,
  });

  /// One folder's name, or a path of folders.
  final String path;

  /// Whether a `/` follows the last folder, so the path reads as the folder
  /// holding what comes before it on the row.
  final bool endsWithSlash;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (above, lastHead, lastTail) = splitPathForCut(path);
    return _TwoPartLine(
      head: above,
      style: style,
      end: _TwoPartLine(
        head: lastHead,
        style: style,
        end: _cutLine(endsWithSlash ? '$lastTail/' : lastTail, style),
      ),
    );
  }
}

/// [head] in [style], then [end], on one line: when the line is too narrow,
/// [head] is cut first, and [end] only once it alone is wider than the line.
/// A cut [head] keeps room for its first character and an ellipsis, so the
/// line shows it was cut rather than starting at [end]: a slot as wide as
/// the ellipsis alone paints nothing.
class _TwoPartLine extends StatelessWidget {
  const _TwoPartLine({
    required this.head,
    required this.style,
    required this.end,
  });

  final String head;
  final TextStyle? style;
  final Widget end;

  @override
  Widget build(BuildContext context) {
    final kept = head.isEmpty
        ? 0.0
        : _width(context, '${head.characters.first}\u2026', style);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: _cutLine(head, style)),
          ConstrainedBox(
            // A slot narrower than the end cuts it rather than overflowing.
            constraints: BoxConstraints(
              maxWidth: math.max(0, constraints.maxWidth - kept),
            ),
            child: end,
          ),
        ],
      ),
    );
  }
}

/// The width of [text] as a [Text] in [style] paints it here: with the
/// ambient style, text scale and bold-text setting it inherits.
double _width(BuildContext context, String text, TextStyle? style) {
  var effective = DefaultTextStyle.of(context).style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // Rounded up, so the head's slot is never a fraction short of the text.
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

Text _cutLine(String text, TextStyle? style) => Text(
      text,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      // As wide as the text it paints: a cut line would otherwise keep its
      // slot's width, leaving a gap between the ellipsis and the end.
      textWidthBasis: TextWidthBasis.longestLine,
    );

/// How many of a name's last characters a cut keeps, before any extension.
const _keptEndCharacters = 6;

/// Splits the basename [name] into the head a cut shortens and the end it
/// keeps: the last [_keptEndCharacters] characters of the stem, then the
/// extension (see [splitExtension]).
(String, String) splitForCut(String name) {
  final (stem, extension) = splitExtension(name);
  final (head, tail) = _splitEnd(stem);
  return (head, '$tail$extension');
}

/// Splits the folder path [path] into the parts a cut gives up in turn: the
/// folders above the last, then the last folder's head, while its last
/// [_keptEndCharacters] characters stay. A folder name has no extension to
/// split off: `v1.2` is a version. The `/` before the last folder starts
/// its head, or its kept end when the head is empty, so it shows whenever
/// the folders above it do.
(String, String, String) splitPathForCut(String path) {
  final slash = path.lastIndexOf('/');
  final (head, tail) = _splitEnd(path.substring(slash + 1));
  if (slash < 0) return ('', head, tail);
  final above = path.substring(0, slash);
  return head.isEmpty ? (above, '', '/$tail') : (above, '/$head', tail);
}

/// Splits [text] before its last [_keptEndCharacters] characters, counting
/// characters as a reader sees them, so no emoji or accented letter is split.
(String, String) _splitEnd(String text) {
  final characters = text.characters;
  return (
    characters.skipLast(_keptEndCharacters).string,
    characters.takeLast(_keptEndCharacters).string,
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
    required this.downloads,
  })  : assert(
            files.isNotEmpty, 'WorkdirPreviewPage requires at least one file'),
        assert(initialIndex >= 0 && initialIndex < files.length,
            'initialIndex out of range');

  final List<WorkdirFile> files;
  final int initialIndex;
  final Future<Uint8List> Function(WorkdirFile file) fetchBytes;

  /// Where the page's download affordances read each file's download and
  /// start it, shared with the file rows.
  final FileDownloads downloads;

  static Future<void> show({
    required BuildContext context,
    required List<WorkdirFile> files,
    required int initialIndex,
    required Future<Uint8List> Function(WorkdirFile file) fetchBytes,
    required FileDownloads downloads,
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
    final download = _DownloadButton(file: file, downloads: widget.downloads);
    final cannot = _CannotPreview(downloadButton: download);
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

  final WorkdirFile file;
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
              onPressed:
                  downloads.canStart(file) ? () => downloads.start(file) : null,
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

// Together these make the title bar's action buttons
// [kMinInteractiveDimension] square on every platform, which the title's
// least height matches: Material makes them smaller on desktop.
const _titleBarActionDensity = VisualDensity.standard;
const _titleBarActionTapTarget = MaterialTapTargetSize.padded;

/// The preview title bar's download action for [file], beside Close: its
/// outcome shows in the icon, as a row's does.
class _TitleBarDownload extends StatelessWidget {
  const _TitleBarDownload({required this.file, required this.downloads});

  final WorkdirFile file;
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
        onPressed:
            downloads.canStart(file) ? () => downloads.start(file) : null,
      );
    });
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
            // Without ExcludeSemantics the spinner's loading-spinner role
            // merges into the button, and the web announces it in place of
            // the button's.
            icon: isRetrying
                ? const ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: retryGlyphSize,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
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
