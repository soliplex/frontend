import 'package:flutter/material.dart';

/// A spinner sized to sit inside a button label without changing the
/// button's width.
///
/// Stacked over the original label at `Opacity(0)` by `SoliplexButton` so
/// the button's measured size is unchanged between idle and loading
/// states — preventing the "jumping button" anti-pattern when an async
/// action transitions to a loading state.
class ButtonLoadingIndicator extends StatelessWidget {
  const ButtonLoadingIndicator({required this.foregroundColor, super.key});

  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final size = DefaultTextStyle.of(context).style.fontSize ?? 14;
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
