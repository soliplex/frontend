import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Pan/zoom/rotate viewport for a single piece of visual content (a raster
/// image, a vector picture, anything). The content is laid out inside a
/// viewport-sized child (`constrained: true`), so fit is exactly `scale == 1.0`,
/// centered: zooming out always returns to the original position, with no
/// off-center drift.
///
/// Zoom works for mouse wheel, trackpad pinch, and — via
/// [InteractiveViewer.trackpadScrollCausesScale] — trackpad two-finger scroll,
/// which Flutter would otherwise route to a (clamped, invisible) pan.
///
/// A reset control appears while zoomed. A rotate control is always shown.
/// Both sit in the top-left, leaving the opposite corner free for whatever
/// affordance the host puts there. The view carries no dismissal of its own:
/// every host that embeds it already provides one.
///
/// Rotation is self-managed by default; use [ZoomableView.controlledRotation]
/// to own rotation from the caller so it can persist across paging (e.g. per
/// document page).
class ZoomableView extends StatefulWidget {
  /// Self-managed rotation, starting unrotated.
  const ZoomableView({
    required this.child,
    super.key,
  })  : rotationQuarterTurns = 0,
        onRotate = null;

  /// Caller-owned rotation: [rotationQuarterTurns] is the live source of truth
  /// and [onRotate] is invoked on each rotate tap, so rotation survives paging.
  const ZoomableView.controlledRotation({
    required this.child,
    required this.rotationQuarterTurns,
    required VoidCallback this.onRotate,
    super.key,
  });

  final Widget child;
  final int rotationQuarterTurns;
  final VoidCallback? onRotate;

  @override
  State<ZoomableView> createState() => _ZoomableViewState();
}

class _ZoomableViewState extends State<ZoomableView> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;
  // Used only in self-managed mode (default constructor); starts unrotated.
  int _selfRotation = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.001;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  void _reset() => _controller.value = Matrix4.identity();

  // Caller-owned when [onRotate] is provided (persists across paging);
  // self-managed otherwise.
  int get _rotationQuarterTurns =>
      widget.onRotate != null ? widget.rotationQuarterTurns : _selfRotation;

  void _rotate() {
    final onRotate = widget.onRotate;
    if (onRotate != null) {
      onRotate();
    } else {
      setState(() => _selfRotation = (_selfRotation + 1) % 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _controller,
            constrained: true,
            trackpadScrollCausesScale: true,
            // Slower than the default (200) so wheel/trackpad zoom advances in
            // fine steps instead of jumping.
            scaleFactor: 800.0,
            minScale: 1.0,
            maxScale: 4.0,
            // At fit the whole content is already visible, so there is nothing
            // to pan; panning is only for moving around zoomed-in content.
            panEnabled: _zoomed,
            child: RotatedBox(
              quarterTurns: _rotationQuarterTurns,
              child: widget.child,
            ),
          ),
        ),
        // Rotate is anchored at the edge so it keeps its position when reset
        // appears beside it.
        Positioned(
          left: SoliplexSpacing.s2,
          top: SoliplexSpacing.s2,
          child: Row(
            spacing: SoliplexSpacing.s2,
            children: [
              IconButton.filledTonal(
                onPressed: _rotate,
                icon: const Icon(Icons.rotate_right),
                tooltip: 'Rotate',
              ),
              // A quick way back to fit without scrolling all the way out.
              if (_zoomed)
                IconButton.filledTonal(
                  onPressed: _reset,
                  icon: const Icon(Icons.zoom_out_map),
                  tooltip: 'Reset zoom',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens [viewer] full-size in a centered dialog, with an optional [caption]
/// row beneath it, so the image and SVG zoom paths frame the viewer
/// identically. The dialog frame owns the close control, which is why
/// [ZoomableView] has none.
Future<void> showZoomableMediaDialog(
  BuildContext context, {
  required Widget viewer,
  Widget? caption,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(child: viewer),
                if (caption != null) caption,
              ],
            ),
            // The barrier dismisses too, but not discoverably: this is the way
            // out a pointer or screen reader user can find. Kept in the corner
            // the viewer leaves free, so it never covers the viewer's own
            // controls.
            Positioned(
              right: SoliplexSpacing.s2,
              top: SoliplexSpacing.s2,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
