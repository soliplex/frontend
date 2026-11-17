import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/content/code_view.dart';
import '../../../../shared/content/content_frame.dart';
import '../../../../shared/zoomable_view.dart';
import '../markdown/log_source.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.svg_body');

const _notice = "Couldn't render this SVG; showing its source.";

/// An SVG under the shared header, with a Preview / Source switch.
///
/// Inline ([fill] false), the picture is capped in height and a tap opens it
/// full size in a zoomable dialog. Filling, the picture is zoomable in the
/// height it is given. When the SVG fails to render, the Preview shows the
/// failure (inline, a broken-image icon beside the notice text; filling, the
/// notice above the source) unless [isStreaming], when the content may still
/// be incomplete and the Preview stays empty and nothing is logged.
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
  bool _failed = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void didUpdateWidget(SvgBody old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _failed = false;
      _error = null;
      _stackTrace = null;
    } else if (old.isStreaming && !widget.isStreaming && _failed) {
      _logFailure();
    }
  }

  // flutter_svg calls the error builder during build, on every rebuild while
  // the failed picture is mounted, so the failure is recorded once and the
  // state flips after the frame.
  Widget _onRenderError(Object error, StackTrace stackTrace) {
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

  void _logFailure() {
    // vector_graphics_compiler's errors put SVG text in their messages (a
    // transform, a colour, a data: href) and xml's parse error carries the
    // source, so only describeFailure's reduction is logged, never `error:`.
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
        view: _view,
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

  // Keyed by content so each content gets a fresh picture: a reused one keeps
  // showing the previous rendering when a new load fails, and reports a late
  // failure of a previous load against the current content.
  Widget _picture() => SvgPicture.string(
        widget.content,
        key: ValueKey(widget.content),
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
  // where the header's copy button would be. Only a rendered SVG is tappable,
  // so the dialog needs no failure presentation.
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
