import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A progress ring in a 16 px icon slot, drawn the size of an icon's shape
/// rather than its box, so it weighs as much as the icons beside it, and
/// named by [label] to a screen reader. Indeterminate when [value] is null.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.label, this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final ring = SizedBox.square(
      dimension: 16,
      child: Center(
        child: SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
            semanticsLabel: label,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (value != null) return ring;
    // A status, which a browser announces; a spinner's own role carries the
    // label to no reader there.
    return Semantics(
      container: true,
      role: SemanticsRole.status,
      label: label,
      excludeSemantics: true,
      child: ring,
    );
  }
}
