import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/content/code_view.dart';
import '../../../../shared/content/content_frame.dart';
import '../../../../shared/zoomable_view.dart';
import '../../svg_styles.dart';
import '../markdown/log_source.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.svg_body');

const _notice = "Couldn't render this SVG.";

/// Whether [content] is a whole SVG: it ends with `</svg>`.
bool _isWhole(String content) => content.trimRight().endsWith('</svg>');

/// An SVG under the shared header, with a Preview / Source switch.
///
/// Inline ([fill] false), the picture is capped in height and a tap opens it
/// full size in a zoomable dialog. Filling, the picture is zoomable in the
/// height it is given. When the SVG fails to render, the Preview shows the
/// failure (inline, a broken-image icon beside the notice text; filling, the
/// notice above the source, with no switch) unless [isStreaming], when the
/// content may still be incomplete: the Preview stays empty and the failure is
/// logged only once streaming ends. Once the content is a whole SVG (it ends
/// with `</svg>`) or streaming ends, the picture is drawn from the content
/// with its `<style>` rules inlined (see [inlineSvgStyles]), or as written
/// when they cannot be inlined or the inlined SVG cannot be drawn; Copy and
/// Source always show the content as written.
class SvgBody extends StatefulWidget {
  const SvgBody({
    super.key,
    required this.content,
    required this.fill,
    required this.isStreaming,
    required this.selectable,
  });

  final String content;
  final bool fill;
  final bool isStreaming;
  final bool selectable;

  @override
  State<SvgBody> createState() => _SvgBodyState();
}

class _SvgBodyState extends State<SvgBody> {
  ContentView _view = ContentView.rendered;
  late String _pictured = _picturedContent();
  bool _failed = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void didUpdateWidget(SvgBody old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _pictured = _picturedContent();
      _failed = false;
      _error = null;
      _stackTrace = null;
    } else if (old.isStreaming && !widget.isStreaming) {
      // A whole SVG was inlined while streaming, and inlining it again would
      // give the same picture; only one that was not yet whole is inlined.
      final pictured =
          _isWhole(widget.content) ? _pictured : _picturedContent();
      if (pictured != _pictured) {
        // Streaming drew the SVG as written, so any failure recorded is its
        // own; the inlined SVG is tried and falls back to the written one if
        // it fails.
        _pictured = pictured;
        _failed = false;
        _error = null;
        _stackTrace = null;
      } else if (_failed) {
        _logFailure();
      }
    }
  }

  // Streaming content is drawn as written until it is a whole SVG: before
  // that it can change on every chunk, and inlining re-reads the whole
  // document each time. A whole one is inlined at once, so the picture is not
  // swapped, and reloaded, when streaming ends.
  String _picturedContent() {
    final content = widget.content;
    if (widget.isStreaming && !_isWhole(content)) return content;
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

  // flutter_svg calls the error builder during build, on every rebuild while
  // the failed picture is mounted, so the failure is recorded once and the
  // state flips after the frame.
  Widget _onRenderError(Object error, StackTrace stackTrace) {
    final pictured = _pictured;
    if (pictured != widget.content) {
      // The inlined SVG failed, whether on a value inlined from its sheet or
      // on the SVG itself. The SVG as written, which flutter_svg draws
      // without its sheet, is drawn instead, and only its own failure is
      // reported as the SVG's.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pictured != pictured) return;
        setState(() => _pictured = widget.content);
        _logInlinedFailure(error, stackTrace);
      });
      return const SizedBox.shrink();
    }
    if (_error == null) {
      _error = error;
      _stackTrace = stackTrace;
      final content = widget.content;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.content != content) return;
        setState(() => _failed = true);
        if (!widget.isStreaming) _logFailure();
      });
    }
    return const SizedBox.shrink();
  }

  // flutter_svg's errors put SVG text in their messages, so `error:` is not
  // passed; see _logFailure.
  void _logInlinedFailure(Object error, StackTrace stackTrace) {
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

  void _logFailure() {
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
      stackTrace: _stackTrace,
      attributes: {
        'contentLength': widget.content.length,
        'failure': describeFailure(_error!),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showsFailure =
        _view == ContentView.rendered && _failed && !widget.isStreaming;
    final rendersPicture = _view == ContentView.rendered && !_failed;
    return ContentFrame(
      header: ContentHeader(
        label: 'svg',
        copyText: widget.content,
        copyTooltip: 'Copy SVG',
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
        ContentView.rendered when _failed => const SizedBox.shrink(),
        ContentView.rendered => widget.fill ? _zoomable() : _inlinePicture(),
      },
    );
  }

  // Keyed by what it draws so each gets a fresh picture: a reused one keeps
  // showing the previous rendering when a new load fails, and reports a late
  // failure of a previous load against the current content.
  Widget _picture() => SvgPicture.string(
        _pictured,
        key: ValueKey(_pictured),
        placeholderBuilder: (_) => const SizedBox.shrink(),
        errorBuilder: (_, error, stackTrace) =>
            _onRenderError(error, stackTrace),
      );

  Widget _zoomable() => ZoomableView(child: _picture());

  Widget _inlinePicture() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _openFullSize,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: _picture(),
        ),
      ),
    );
  }

  // The bare picture, without the header: the dialog puts its close button
  // where the header's copy button would be. A failed picture is not tappable
  // after its first frame, so the dialog needs no failure presentation.
  void _openFullSize() {
    showZoomableMediaDialog(context, viewer: _zoomable());
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
