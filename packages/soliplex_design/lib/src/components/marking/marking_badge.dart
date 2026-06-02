import 'package:flutter/material.dart';

import 'package:soliplex_design/src/marking/dataset_marking.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/radii.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// An inline classification marking pill for a single dataset, row, card,
/// attachment, or content portion.
///
/// The exact [DatasetMarking.label] text is authoritative; the fixed
/// marking color is a secondary cue only, so the badge still reads in
/// grayscale and is announced to screen readers via [Semantics]. Long
/// markings wrap rather than truncate.
///
/// Use the default constructor for an overall marking (`CUI`) and
/// [SoliplexMarkingBadge.portion] for a portion mark that precedes a
/// sensitive section (`(CUI)`).
class SoliplexMarkingBadge extends StatelessWidget {
  const SoliplexMarkingBadge({
    required this.marking,
    super.key,
  }) : _portion = false;

  /// Compact portion-marking variant rendering `(U)` / `(CUI)` / `(S)`.
  const SoliplexMarkingBadge.portion({
    required this.marking,
    super.key,
  }) : _portion = true;

  /// The marking to display.
  final DatasetMarking marking;

  final bool _portion;

  @override
  Widget build(BuildContext context) {
    final colors = SoliplexTheme.markingColorsOf(context).resolve(marking);
    final baseStyle = _portion
        ? Theme.of(context).textTheme.labelSmall
        : Theme.of(context).textTheme.labelMedium;
    final textStyle = baseStyle?.copyWith(
      color: colors.foreground,
      fontWeight: FontWeight.w700,
    );
    final text = _portion ? marking.portionLabel : marking.label;

    return Semantics(
      label: 'Classification marking: ${marking.label}',
      child: ExcludeSemantics(
        child: Container(
          padding: _portion
              ? const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s1,
                )
              : const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s2,
                  vertical: SoliplexSpacing.s1,
                ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(soliplexRadii.sm),
          ),
          child: Text(text, style: textStyle),
        ),
      ),
    );
  }
}
