import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'zoomable_view.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.zoomable_image');

/// Pan/zoom/rotate viewer for a single image, shared by the app's image-preview
/// surfaces. Delegates the interaction to [ZoomableView]; owns the load/decode
/// failure so the fallback is shown *in place of* the viewer — no zoom or rotate
/// chrome over a broken image.
///
/// The rotate control is always shown. Rotation is self-managed by default; use
/// [ZoomableImage.controlledRotation] to own rotation from the caller so it
/// persists across paging. When the image fails to load or decode,
/// [decodeFailureChild] is shown, centered, in place of the viewer.
class ZoomableImage extends StatefulWidget {
  /// Decoded bytes, self-managed rotation, starting unrotated.
  ZoomableImage({
    required Uint8List bytes,
    required this.decodeFailureChild,
    this.semanticLabel,
    this.logSource,
    super.key,
  })  : provider = MemoryImage(bytes),
        byteLength = bytes.length,
        rotationQuarterTurns = 0,
        onRotate = null;

  /// Decoded bytes with caller-owned rotation so it survives paging (e.g. per
  /// document page).
  ZoomableImage.controlledRotation({
    required Uint8List bytes,
    required this.decodeFailureChild,
    required this.rotationQuarterTurns,
    required VoidCallback this.onRotate,
    this.semanticLabel,
    this.logSource,
    super.key,
  })  : provider = MemoryImage(bytes),
        byteLength = bytes.length;

  /// Any [ImageProvider] (network, asset, file), self-managed rotation. The
  /// provider's load failure is owned here, so the fallback shows without the
  /// zoom/rotate chrome.
  const ZoomableImage.provider(
    this.provider, {
    required this.decodeFailureChild,
    this.semanticLabel,
    this.logSource,
    super.key,
  })  : byteLength = null,
        rotationQuarterTurns = 0,
        onRotate = null;

  final ImageProvider provider;
  final Widget decodeFailureChild;
  final int rotationQuarterTurns;
  final VoidCallback? onRotate;
  final String? semanticLabel;

  /// Byte length recorded in the failure log when the image was built from
  /// bytes; null for provider-backed images.
  final int? byteLength;

  /// Optional identifier for the image source (e.g. a figure ref or redacted
  /// URI) recorded in the failure log so a failure can be traced to its source.
  final String? logSource;

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  bool _failed = false;

  @override
  void didUpdateWidget(ZoomableImage old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) _failed = false;
  }

  void _markFailed(Object error, StackTrace? stackTrace) {
    if (_failed) return;
    _logger.warning(
      'image failed to load',
      error: error,
      stackTrace: stackTrace,
      attributes: {
        if (widget.byteLength != null) 'byteLength': widget.byteLength,
        if (widget.logSource != null) 'source': widget.logSource,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return Center(child: widget.decodeFailureChild);

    final image = Image(
      image: widget.provider,
      fit: BoxFit.contain,
      semanticLabel: widget.semanticLabel,
      errorBuilder: (_, error, stack) {
        _markFailed(error, stack);
        return const SizedBox.shrink();
      },
    );
    final onRotate = widget.onRotate;
    return onRotate != null
        ? ZoomableView.controlledRotation(
            rotationQuarterTurns: widget.rotationQuarterTurns,
            onRotate: onRotate,
            child: image,
          )
        : ZoomableView(child: image);
  }
}
