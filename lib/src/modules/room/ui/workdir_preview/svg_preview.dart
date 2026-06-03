import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.svg_preview');

/// Renders an SVG payload inside an [InteractiveViewer]. Falls back to
/// [fallback] if the bytes don't parse — sized as a peer of the viewer
/// so its controls aren't pannable/zoomable.
class SvgPreview extends StatefulWidget {
  const SvgPreview({
    super.key,
    required this.content,
    required this.fallback,
  });

  final String content;
  final Widget fallback;

  @override
  State<SvgPreview> createState() => _SvgPreviewState();
}

class _SvgPreviewState extends State<SvgPreview> {
  bool _failed = false;

  @override
  void didUpdateWidget(SvgPreview old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _failed = false;
    }
  }

  void _markFailed(Object? error, StackTrace? stackTrace) {
    if (_failed) return;
    _logger.warning(
      'svg content failed to parse',
      error: error,
      stackTrace: stackTrace,
      attributes: {'contentLength': widget.content.length},
    );
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
        child: SvgPicture.string(
          widget.content,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => const SizedBox.shrink(),
          errorBuilder: (_, error, stack) {
            _markFailed(error, stack);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
