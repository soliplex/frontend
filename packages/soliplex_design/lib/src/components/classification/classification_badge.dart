import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/badge/pill.dart';
import 'package:soliplex_design/src/theme/classification_theme.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// Display-only confidentiality marking pill.
///
/// Resolves [classification] against the ambient [ClassificationTheme]
/// (`null` → the theme's default level) and renders it as a badge-style
/// pill. The label **wraps** rather than truncating — clipping a marking
/// is an integrity bug — so this widget is given a bounded width by its
/// parent. Not tappable.
///
/// In a deployment that has configured no classifications the resolved
/// level is the neutral built-in and this widget renders nothing: an
/// unconfigured product should not sprout meaningless pills. A configured
/// deployment always shows its default, and an unrecognized id always
/// resolves to a fail-loud alarm marking that is shown.
///
/// Safe under bare [ThemeData]: it reads only the null-safe
/// [ClassificationTheme.of] and const tokens, never the `!`-guarded
/// `SoliplexTheme.of`.
class SoliplexClassificationBadge extends StatelessWidget {
  const SoliplexClassificationBadge({this.classification, super.key})
      : _bar = false;

  /// The bar presentation: a marking mounted in a chrome bar rather than in a
  /// text row or a card.
  ///
  /// It fills the height its parent gives it (the caller supplies that — it
  /// should be the height of the controls beside it) with its label centred,
  /// and takes the brand corner and the roomier padding that make it read as
  /// a piece of the bar's furniture, the way a room avatar does in the rail.
  const SoliplexClassificationBadge.bar({this.classification, super.key})
      : _bar = true;

  /// Stable level id. `null` → the theme's default level.
  final String? classification;

  /// Whether this is the [SoliplexClassificationBadge.bar] presentation.
  final bool _bar;

  @override
  Widget build(BuildContext context) {
    final theme = ClassificationTheme.of(context);
    final level = theme.resolve(context, classification);

    // Suppress only the unconfigured built-in (identity check). Configured
    // defaults and the alarm level are distinct instances and still show.
    if (identical(level, ClassificationTheme.fallbackLevel)) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: 'Classification: ${level.label}',
      child: ExcludeSemantics(
        child: BadgePill(
          fillHeight: _bar,
          label: Text(level.label),
          icon: level.icon != null ? Icon(level.icon) : null,
          background: level.background,
          foreground: level.foreground,
          // The bar presentation doubles the inline pill's padding and takes
          // the brand corner (`md`, what every room avatar in the rail wears)
          // rather than the small well corner.
          padding: _bar
              ? const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s4,
                  vertical: SoliplexSpacing.s2,
                )
              : const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s2,
                  vertical: SoliplexSpacing.s1,
                ),
          radius: _bar ? context.radii.md : context.radii.sm,
          textStyle: textTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
