import 'package:flutter/material.dart';

import 'package:soliplex_design/src/marking/dataset_marking.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// A full-width, persistent classification banner showing the current
/// effective marking — placed at the top of a scaffold (and, for
/// classified contexts, mirrored at the bottom).
///
/// The exact [DatasetMarking.label] text is authoritative; color is a
/// secondary cue. The label wraps rather than truncating, is centered,
/// and is exposed to screen readers as a header so it is announced before
/// the protected content beneath it. Pass [compact] for the mobile
/// header bar.
class SoliplexMarkingBanner extends StatelessWidget {
  const SoliplexMarkingBanner({
    required this.marking,
    this.compact = false,
    super.key,
  });

  /// The effective marking for the screen.
  final DatasetMarking marking;

  /// Tighter vertical padding and smaller text for narrow screens.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = SoliplexTheme.markingColorsOf(context).resolve(marking);
    final baseStyle = compact
        ? Theme.of(context).textTheme.labelMedium
        : Theme.of(context).textTheme.titleSmall;
    final textStyle = baseStyle?.copyWith(
      color: colors.foreground,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );

    return Semantics(
      header: true,
      label: 'Classification banner: ${marking.label}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          color: colors.background,
          padding: EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s4,
            vertical: compact ? SoliplexSpacing.s1 : SoliplexSpacing.s2,
          ),
          child: Text(
            marking.label,
            textAlign: TextAlign.center,
            style: textStyle,
          ),
        ),
      ),
    );
  }
}
