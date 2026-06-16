import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.zoomable_image');

/// Pan/zoom/rotate viewer for a single decoded image, shared by the chunk
/// visualization and workdir file previews.
///
/// Zoom works for mouse wheel, trackpad pinch, and — via
/// [InteractiveViewer.trackpadScrollCausesScale] — trackpad two-finger scroll,
/// which Flutter would otherwise route to a (clamped, invisible) pan.
///
/// Intrinsic dimensions are read from the decoded image so the image is sized
/// to its exact aspect ratio under `constrained: false`; zoom then scales only
/// image content, never surrounding whitespace. Works for every format the
/// engine decodes, not just PNG.
///
/// Rotation state is owned by the caller ([rotationQuarterTurns] / [onRotate])
/// so it can persist across paging. When the bytes can't be decoded,
/// [decodeFailureChild] is shown in place of the viewer and the rotate control
/// is hidden.
class ZoomableImage extends StatefulWidget {
  const ZoomableImage({
    required this.bytes,
    required this.rotationQuarterTurns,
    required this.onRotate,
    required this.decodeFailureChild,
    super.key,
  });

  final Uint8List bytes;
  final int rotationQuarterTurns;
  final VoidCallback onRotate;
  final Widget decodeFailureChild;

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  final TransformationController _controller = TransformationController();
  late MemoryImage _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _intrinsicSize;
  bool _failed = false;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _provider = MemoryImage(widget.bytes);
    _controller.addListener(_onTransformChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveDimensions();
  }

  @override
  void didUpdateWidget(ZoomableImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _detachStream();
      _provider = MemoryImage(widget.bytes);
      _intrinsicSize = null;
      _failed = false;
      _controller.value = Matrix4.identity();
      _resolveDimensions();
    }
  }

  @override
  void dispose() {
    _detachStream();
    _controller
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.001;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  void _resolveDimensions() {
    _detachStream();
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        if (mounted) setState(() => _intrinsicSize = size);
      },
      onError: _markFailed,
    );
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _detachStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _reset() => _controller.value = Matrix4.identity();

  void _markFailed(Object error, StackTrace? stackTrace) {
    if (_failed) return;
    _logger.warning(
      'image bytes failed to decode',
      error: error,
      stackTrace: stackTrace,
      attributes: {'byteLength': widget.bytes.length},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  Widget _interactive({required bool constrained, required Widget child}) {
    return InteractiveViewer(
      transformationController: _controller,
      constrained: constrained,
      trackpadScrollCausesScale: true,
      minScale: 1.0,
      maxScale: 4.0,
      child: child,
    );
  }

  Widget _viewer() {
    final rotation = widget.rotationQuarterTurns;
    final image = RotatedBox(
      quarterTurns: rotation,
      child: Image(
        image: _provider,
        fit: BoxFit.contain,
        errorBuilder: (_, error, stack) {
          _markFailed(error, stack);
          return const SizedBox.shrink();
        },
      ),
    );

    final size = _intrinsicSize;
    if (size == null) {
      return Center(child: _interactive(constrained: true, child: image));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final effW = rotation.isOdd ? size.height : size.width;
        final effH = rotation.isOdd ? size.width : size.height;
        final scale = min(
          constraints.maxWidth / effW,
          constraints.maxHeight / effH,
        );
        return Center(
          child: _interactive(
            constrained: false,
            child: SizedBox(
              width: effW * scale,
              height: effH * scale,
              child: image,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.decodeFailureChild;

    return Stack(
      children: [
        Positioned.fill(child: _viewer()),
        // With constrained:false zoom, scrolling back out clamps scale but
        // leaves a residual offset, so there's otherwise no reliable way back
        // to the starting view. The reset control appears only while zoomed.
        if (_zoomed)
          Positioned(
            left: SoliplexSpacing.s2,
            top: SoliplexSpacing.s2,
            child: IconButton.filledTonal(
              onPressed: _reset,
              icon: const Icon(Icons.zoom_out_map),
              tooltip: 'Reset zoom',
            ),
          ),
        Positioned(
          right: SoliplexSpacing.s2,
          top: SoliplexSpacing.s2,
          child: IconButton.filledTonal(
            onPressed: widget.onRotate,
            icon: const Icon(Icons.rotate_right),
            tooltip: 'Rotate',
          ),
        ),
      ],
    );
  }
}
