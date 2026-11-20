import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/content/code_view.dart';
import '../../../../shared/content/content_frame.dart';
import '../../../../shared/zoomable_view.dart';
import '../../svg_styles.dart';
import '../markdown/log_source.dart';
import 'browser_svg_picture.dart';
import 'svg_attempts.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.svg_body');

const _notice = "Couldn't render this SVG.";

/// Overrides whether [SvgBody] has a browser to draw SVGs in, which is
/// [canDrawSvgInBrowser] otherwise.
@visibleForTesting
bool? debugSvgInBrowserOverride;

/// Whether [content] is a whole SVG: it ends with `</svg>`.
bool _isWhole(String content) => content.trimRight().endsWith('</svg>');

/// An SVG under the shared header, with a Preview / Source switch.
///
/// Inline ([fill] false), the picture is capped in height. Once streaming
/// ends, a tap opens the content in a zoomable dialog, which draws it afresh
/// in the same order and shows the inline failure if every attempt fails
/// there. Filling, the picture is zoomable in the height it is given. When
/// the SVG fails to render, the Preview shows the
/// failure (inline, a broken-image icon beside the notice text; filling, the
/// notice above the source, with no switch) unless [isStreaming], when the
/// content may still be incomplete: the Preview stays empty and the failure is
/// logged only once streaming ends. Once the content is a whole SVG (it ends
/// with `</svg>`) or streaming ends, the picture is drawn in the order
/// [SvgAttempts] gives: in a browser, by the browser as written (see
/// [BrowserSvgPicture]); then by flutter_svg with the `<style>` rules inlined
/// (see [inlineSvgStyles]); then by flutter_svg as written. Before then it
/// is drawn by flutter_svg as written. Copy and Source always show the
/// content as written.
class SvgBody extends StatefulWidget {
  const SvgBody({
    super.key,
    required this.content,
    required this.fill,
    required this.isStreaming,
    required this.selectable,
  }) : _zoomSnapshot = false;

  const SvgBody._zoom(this.content)
      : fill = true,
        isStreaming = false,
        selectable = false,
        _zoomSnapshot = true;

  final bool _zoomSnapshot;

  final String content;
  final bool fill;
  final bool isStreaming;
  final bool selectable;

  @override
  State<SvgBody> createState() => _SvgBodyState();
}

class _SvgBodyState extends State<SvgBody> {
  ContentView _view = ContentView.rendered;
  late SvgAttempts _attempts = _attemptsForContent();

  @override
  void didUpdateWidget(SvgBody old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _attempts = _attemptsForContent();
    } else if (old.isStreaming && !widget.isStreaming) {
      // A whole SVG got its attempts while streaming, and they are the ones
      // it would get now; only one that was not yet whole gets new ones.
      final attempts =
          _isWhole(widget.content) ? _attempts : _attemptsForContent();
      if (attempts.current != _attempts.current) {
        // Streaming drew the SVG as written with flutter_svg, so any failure
        // recorded is that attempt's own; the new attempts are tried in turn.
        _attempts = attempts;
      } else if (_attempts.failure case final failure?) {
        _logFailure(failure);
      }
    }
  }

  // Streaming content is drawn as written until it is a whole SVG: before
  // that it can change on every chunk, and both the browser's image and
  // inlining take the whole document each time. A whole one gets all its
  // attempts at once, so the picture is not swapped, and reloaded, when
  // streaming ends.
  SvgAttempts _attemptsForContent() {
    final content = widget.content;
    return SvgAttempts(
      content,
      inBrowser: debugSvgInBrowserOverride ?? canDrawSvgInBrowser,
      partial: widget.isStreaming && !_isWhole(content),
      inlineStyles: _inlineStyles,
    );
  }

  String _inlineStyles(String content) {
    try {
      return inlineSvgStyles(content);
    } catch (error, stackTrace) {
      // Caught whole: csslib's failures on a sheet it cannot read are crashes
      // inside its parser, not a documented set, and any other failure while
      // inlining is better drawn as written than not drawn. What can reach
      // here carries a number token (csslib's FormatException or
      // RangeError), type names (a TypeError), csslib's fixed text (a
      // StateError) or a stack overflow's fixed text (deeply nested elements
      // or parentheses); none is a credential, so the error is logged as it
      // is.
      logFailedSourceOnce(
        _logger,
        'svg styles could not be inlined',
        'svg-styles:$content',
        error: error,
        stackTrace: stackTrace,
        attributes: {'contentLength': content.length},
      );
      return content;
    }
  }

  // flutter_svg's error builder runs during build, on every rebuild while
  // the failed picture is mounted, so its failure is handled after the frame.
  Widget _onSvgPictureError(
    SvgAttempts owner,
    SvgAttempt attempt,
    Object error,
    StackTrace? stackTrace,
  ) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onAttemptFailed(owner, attempt, error, stackTrace),
    );
    return const SizedBox.shrink();
  }

  // Move on once per attempt, ignoring callbacks from replaced content.
  void _onAttemptFailed(
    SvgAttempts owner,
    SvgAttempt attempt,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (!mounted || !identical(owner, _attempts)) return;
    switch (_attempts.fail(attempt, error, stackTrace)) {
      case SvgFailureOutcome.alreadyHandled:
        return;
      case SvgFailureOutcome.nextAttempt:
        setState(() {});
        switch (attempt.renderer) {
          case SvgRenderer.browser:
            _logBrowserFailure(error, stackTrace);
          // Only the inlined SVG has a flutter_svg attempt after it. It
          // failed, whether on a value inlined from its sheet or on the SVG
          // itself, and the SVG as written, which flutter_svg draws without
          // its sheet, is drawn instead.
          case SvgRenderer.flutterSvg:
            _logInlinedFailure(error, stackTrace);
        }
      case SvgFailureOutcome.allFailed:
        setState(() {});
        if (!widget.isStreaming) {
          _logFailure((error: error, stackTrace: stackTrace));
        }
    }
  }

  // What reaches here is the browser picture's SvgImageRejected: fixed text,
  // no part of the SVG (the browser gives no reason; a policy that blocked
  // the image is named in its console). It is logged whole, because
  // describeFailure would reduce it to its type name, which a release build
  // minifies.
  void _logBrowserFailure(Object error, StackTrace? stackTrace) {
    logFailedSourceOnce(
      _logger,
      'svg failed to render in the browser; drawing it with flutter_svg',
      'svg-browser:${widget.content}',
      error: error,
      stackTrace: stackTrace,
      attributes: {'contentLength': widget.content.length},
    );
  }

  // flutter_svg's errors put SVG text in their messages, so `error:` is not
  // passed; see _logFailure.
  void _logInlinedFailure(Object error, StackTrace? stackTrace) {
    logFailedSourceOnce(
      _logger,
      'svg failed to render with its styles inlined; drawing it as written',
      'svg-styles-drawn:${widget.content}',
      stackTrace: stackTrace,
      attributes: {
        'contentLength': widget.content.length,
        'failure': describeFailure(error),
      },
    );
  }

  void _logFailure(SvgFailure failure) {
    // xml's parse errors carry a window of the source and
    // vector_graphics_compiler's put SVG text in their messages (a transform,
    // a colour, a data: href), so `error:` is never passed. describeFailure
    // drops the source window, so the SVG text itself is not logged, but a
    // message can still quote a fragment of it (a tag name, one attribute
    // value).
    logFailedSourceOnce(
      _logger,
      'svg content failed to render',
      'svg:${widget.content}',
      stackTrace: failure.stackTrace,
      attributes: {
        'contentLength': widget.content.length,
        'failure': describeFailure(failure.error),
      },
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'SVG image',
        child: _buildContent(context),
      );

  Widget _buildContent(BuildContext context) {
    final failed = _attempts.failure != null;
    if (widget._zoomSnapshot) {
      return failed
          ? Padding(
              padding: const EdgeInsets.all(SoliplexSpacing.s4),
              child: Center(child: _inlineFailure(context)),
            )
          : _zoomable();
    }
    final showsFailure =
        _view == ContentView.rendered && failed && !widget.isStreaming;
    final rendersPicture = _view == ContentView.rendered && !failed;
    return ContentFrame(
      header: ContentHeader(
        label: 'svg',
        copyText: widget.content,
        copyTooltip: 'Copy SVG',
        selectable: widget.selectable,
        // Filling, a failure's Preview already is the source under the
        // notice, so a switch would offer the same view twice.
        view: showsFailure && widget.fill ? null : _view,
        renderedLabel: 'Preview',
        onViewChanged: (view) => setState(() => _view = view),
      ),
      notice: showsFailure && widget.fill
          ? const RenderFailureNotice(message: _notice)
          : null,
      fill: widget.fill,
      scrollBody: !(widget.fill && rendersPicture),
      body: switch (_view) {
        ContentView.source => _source(),
        ContentView.rendered when showsFailure =>
          widget.fill ? _source() : _inlineFailure(context),
        ContentView.rendered when failed => const SizedBox.shrink(),
        ContentView.rendered => widget.fill ? _zoomable() : _inlinePicture(),
      },
    );
  }

  // Keyed by the attempt it draws so each gets a fresh picture: a reused one
  // keeps showing the previous rendering when a new load fails, and reports
  // a late failure of a previous load against the current attempt.
  Widget _picture(SvgAttempts owner, SvgAttempt attempt) {
    final key = ValueKey((owner, attempt));
    return switch (attempt.renderer) {
      SvgRenderer.browser => BrowserSvgPicture(
          attempt.svg,
          key: key,
          onFailed: (error, stackTrace) =>
              _onAttemptFailed(owner, attempt, error, stackTrace),
        ),
      SvgRenderer.flutterSvg => SvgPicture.string(
          attempt.svg,
          key: key,
          placeholderBuilder: (_) => const SizedBox.shrink(),
          errorBuilder: (_, error, stackTrace) =>
              _onSvgPictureError(owner, attempt, error, stackTrace),
        ),
    };
  }

  Widget _zoomable() =>
      ZoomableView(child: _picture(_attempts, _attempts.current));

  Widget _inlinePicture() {
    final canZoom = !widget.isStreaming;
    return MouseRegion(
      cursor: canZoom ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        // The whole picture's box, also while the browser's image loads.
        behavior: HitTestBehavior.opaque,
        onTap: canZoom ? _openFullSize : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: _picture(_attempts, _attempts.current),
        ),
      ),
    );
  }

  void _openFullSize() {
    showZoomableMediaDialog(
      context,
      viewer: SvgBody._zoom(widget.content),
    );
  }

  Widget _inlineFailure(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.broken_image,
          size: 48,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: SoliplexSpacing.s2),
        Expanded(
          child: Text(
            _notice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _source() => CodeView(
        code: widget.content,
        language: 'xml',
        selectable: widget.selectable,
      );
}
