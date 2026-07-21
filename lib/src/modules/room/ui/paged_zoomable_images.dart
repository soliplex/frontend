import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'pager_dots.dart';

/// A pageable set of zoomable images sharing one page indicator and per-page
/// rotation that persists across paging. Used by the chunk-visualization page
/// browser and the citation-figure browser.
///
/// Each page is built by [pageBuilder], which receives the page's current
/// rotation and a rotate callback to wire into a `ZoomableImage`. [footerBuilder]
/// renders optional content (a page label, a caption) above the page dots for
/// the current page. Paging is driven by the page dots, the prev/next chevrons,
/// and the left/right arrow keys (set [autofocus] so the arrows work without a
/// prior tap, e.g. in a dialog).
///
/// Rotation and current-page state live for the widget's lifetime; to reset
/// them (e.g. on a reload) give the widget a new [key] so it remounts.
class PagedZoomableImages extends StatefulWidget {
  const PagedZoomableImages({
    required this.itemCount,
    required this.pageBuilder,
    this.initialIndex = 0,
    this.footerBuilder,
    this.dotLabelForIndex,
    this.autofocus = false,
    super.key,
  })  : assert(itemCount > 0, 'PagedZoomableImages requires at least one item'),
        assert(
          initialIndex >= 0 && initialIndex < itemCount,
          'initialIndex must be within [0, itemCount)',
        );

  final int itemCount;
  final Widget Function(
    BuildContext context,
    int index,
    ({int quarterTurns, VoidCallback onRotate}) rotation,
  ) pageBuilder;
  final int initialIndex;
  final Widget? Function(BuildContext context, int index)? footerBuilder;
  final String Function(int index)? dotLabelForIndex;
  final bool autofocus;

  @override
  State<PagedZoomableImages> createState() => _PagedZoomableImagesState();
}

class _PagedZoomableImagesState extends State<PagedZoomableImages> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  final FocusNode _focusNode = FocusNode();
  late int _current = widget.initialIndex;
  final Map<int, int> _rotations = {};

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _rotate(int index) =>
      setState(() => _rotations[index] = ((_rotations[index] ?? 0) + 1) % 4);

  void _goTo(int index) => _controller.animateToPage(
        index.clamp(0, widget.itemCount - 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _goTo(_current + 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _goTo(_current - 1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final footer = widget.footerBuilder?.call(context, _current);
    final showNav = widget.itemCount > 1;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.itemCount,
              onPageChanged: (index) => setState(() => _current = index),
              itemBuilder: (context, index) => widget.pageBuilder(
                context,
                index,
                (
                  quarterTurns: _rotations[index] ?? 0,
                  onRotate: () => _rotate(index),
                ),
              ),
            ),
          ),
          if (footer != null || showNav)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (footer != null) footer,
                  if (footer != null && showNav)
                    const SizedBox(height: SoliplexSpacing.s1),
                  if (showNav)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous',
                          onPressed:
                              _current > 0 ? () => _goTo(_current - 1) : null,
                        ),
                        PagerDots(
                          itemCount: widget.itemCount,
                          currentIndex: _current,
                          onGoTo: _goTo,
                          labelForIndex: widget.dotLabelForIndex,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next',
                          onPressed: _current < widget.itemCount - 1
                              ? () => _goTo(_current + 1)
                              : null,
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
