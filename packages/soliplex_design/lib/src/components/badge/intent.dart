import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/theme_extensions.dart';

/// Semantic flavor of a `SoliplexBadge`.
///
/// Unlike `ButtonIntent` (an *action* gradient), badge intents are a
/// *status* gradient — they communicate state, not call-to-action.
enum BadgeIntent {
  /// Plain decorative label ("v2", "beta", "draft"). Uses the brand's
  /// neutral badge palette from `SoliplexBadgeThemeData`.
  neutral,

  /// Informational notice. Blue tint.
  info,

  /// Success state ("active", "completed"). Uses the brand's
  /// `successContainer` palette.
  success,

  /// Caution state ("review needed", "expiring"). Orange tint.
  warning,

  /// Failure / destructive state ("error", "blocked"). Uses the brand's
  /// `errorContainer` palette.
  danger,
}

/// The `(background, foreground)` colour pair for a badge at this intent,
/// resolved against the current theme.
///
/// Mixed sourcing by design:
///
/// - `neutral`: the brand's customizable [SoliplexBadgeThemeData].
/// - `danger` / `success`: the brand's `errorContainer` /
///   `successContainer` token pairs — these slots exist precisely for
///   status surfaces, so honouring them keeps brand fidelity.
/// - `info` / `warning`: derived at runtime from `SymbolicColors`
///   because there are no `infoContainer` / `warningContainer` brand
///   tokens (yet). Background is the symbolic color tinted to 15%
///   alpha, foreground is the symbolic color at full opacity.
///
/// If brand-customizable info/warning containers are ever needed, add
/// the tokens to `SoliplexColors` and swap the derived case below for
/// the new pair.
({Color background, Color foreground}) badgeIntentColors(
  BadgeIntent intent,
  BuildContext context,
) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final soliplex = SoliplexTheme.of(context);

  switch (intent) {
    case BadgeIntent.neutral:
      return (
        background: soliplex.badgeTheme.background,
        foreground: soliplex.badgeTheme.textStyle.color ?? scheme.onSurface,
      );
    case BadgeIntent.info:
      return (
        background: soliplex.colors.info.withValues(alpha: 0.15),
        foreground: soliplex.colors.info,
      );
    case BadgeIntent.success:
      return (
        background: soliplex.colors.successContainer,
        foreground: soliplex.colors.onSuccessContainer,
      );
    case BadgeIntent.warning:
      return (
        background: soliplex.colors.warning.withValues(alpha: 0.15),
        foreground: soliplex.colors.warning,
      );
    case BadgeIntent.danger:
      return (
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      );
  }
}
