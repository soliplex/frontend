import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Scroll controller whose position can be anchored beyond natural content
/// bounds, allowing a message to sit at the viewport top while a response
/// streams below.
///
/// Manual user scrolling is clamped to the anchor offset (or the natural
/// max if no anchor is set), so the user cannot scroll into empty space.
class AnchoredScrollController extends ScrollController {
  AnchoredScrollController({super.initialScrollOffset});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _AnchoredScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      oldPosition: oldPosition,
    );
  }

  _AnchoredScrollPosition get _anchoredPosition {
    assert(hasClients, 'Cannot access anchor before scroll view is attached');
    return position as _AnchoredScrollPosition;
  }

  /// Expand max scroll extent to [offset] so the target message can sit
  /// at the viewport top even when there isn't enough content below it.
  void setAnchor(double offset) => _anchoredPosition.anchorOffset = offset;

  /// Revert to natural content bounds.
  void clearAnchor() => _anchoredPosition.anchorOffset = null;
}

class _AnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _AnchoredScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.oldPosition,
  });

  /// When set, [maxScrollExtent] is expanded to at least this value.
  ///
  /// Callers must follow changes with a scroll command (jumpTo/animateTo)
  /// to trigger the layout pass that picks up the new value.
  double? anchorOffset;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final effectiveMax =
        anchorOffset != null
            ? math.max(maxScrollExtent, anchorOffset!)
            : maxScrollExtent;
    return super.applyContentDimensions(minScrollExtent, effectiveMax);
  }
}
