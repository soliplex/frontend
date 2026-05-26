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
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
      ),
    );
  }
}
