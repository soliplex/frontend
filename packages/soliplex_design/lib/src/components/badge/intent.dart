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

  /// Informational notice. Uses the brand's `infoContainer` palette.
  info,

  /// Success state ("active", "completed"). Uses the brand's
  /// `successContainer` palette.
  success,

  /// Caution state ("review needed", "expiring"). Uses the brand's
  /// `warningContainer` palette.
  warning,

  /// Failure / destructive state ("error", "blocked"). Uses the brand's
  /// `errorContainer` palette.
  danger,
}

/// The `(background, foreground)` colour pair for a badge at this intent,
/// resolved against the current theme.
///
/// - `neutral`: the brand's customizable [SoliplexBadgeThemeData].
/// - `danger` / `success` / `warning` / `info`: the brand's `errorContainer` /
///   `successContainer` / `warningContainer` / `infoContainer` token pairs —
///   each a soft status surface with a readable on-color, so a fork rebrands
///   the pill by setting those roles.
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
        background: soliplex.colors.infoContainer,
        foreground: soliplex.colors.onInfoContainer,
      );
    case BadgeIntent.success:
      return (
        background: soliplex.colors.successContainer,
        foreground: soliplex.colors.onSuccessContainer,
      );
    case BadgeIntent.warning:
      return (
        background: soliplex.colors.warningContainer,
        foreground: soliplex.colors.onWarningContainer,
      );
    case BadgeIntent.danger:
      return (
        background: soliplex.colors.errorContainer,
        foreground: soliplex.colors.onErrorContainer,
      );
  }
}
