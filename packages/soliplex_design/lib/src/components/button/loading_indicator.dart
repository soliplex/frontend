import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A spinner the size of the surrounding text, and no larger than [maxSize].
///
/// The loading slot of inputs, dropdowns and pickers uses it too.
///
/// `SoliplexButton` keeps the button's size around it, so the button does not
/// jump between idle and loading: with no icon it stacks the spinner over the
/// label hidden at `Opacity(0)`; with an icon it centres the spinner in the
/// icon's slot, passing the slot's size as [maxSize] so a large font cannot
/// overflow it.
class ButtonLoadingIndicator extends StatelessWidget {
  const ButtonLoadingIndicator({
    required this.foregroundColor,
    this.maxSize,
    super.key,
  });

  final Color foregroundColor;

  /// The largest the spinner may be; unbounded when null.
  final double? maxSize;

  @override
  Widget build(BuildContext context) {
    final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
    final maxSize = this.maxSize;
    final size = maxSize == null ? fontSize : math.min(fontSize, maxSize);
    // UnconstrainedBox so a tight non-square parent (e.g. an input's suffix
    // slot, which forces a ~48px height) can't stretch the indicator into an
    // ellipse: the child is laid out with loose constraints and keeps its
    // square size, and the box shrink-wraps to it rather than expanding to
    // fill — leaving the parent to position it as it would any icon.
    return UnconstrainedBox(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
        ),
      ),
    );
  }
}
