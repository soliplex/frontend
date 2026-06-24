import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/theme_extensions.dart';

/// Semantic flavor of a `SoliplexChip`.
///
/// Same gradient as `BadgeIntent` — chips and badges both communicate
/// status, just at different visual weights (chips are interactive or
/// deletable; badges are decorative). Intentionally a distinct enum so
/// either family can diverge later without breaking the other's
/// vocabulary.
enum ChipIntent {
  /// The brand's neutral chip palette from `ChipThemeData`.
  neutral,

  /// Informational notice. Uses the brand's `infoContainer` palette.
  info,

  /// Success state. Uses the brand's `successContainer` palette.
  success,

  /// Caution state. Uses the brand's `warningContainer` palette.
  warning,

  /// Failure / destructive state. Uses the brand's `errorContainer`
  /// palette.
  danger,
}

/// The `(background, foreground)` colour pair for a chip at this intent,
/// resolved against the current theme.
///
/// Sourced identically to badges: each status intent reads its
/// `errorContainer` / `successContainer` / `warningContainer` / `infoContainer`
/// token pair, and `null`s for neutral so the Material chip theme defaults
/// apply.
({Color? background, Color? foreground}) chipIntentColors(
  ChipIntent intent,
  BuildContext context,
) {
  final soliplex = SoliplexTheme.of(context);

  switch (intent) {
    case ChipIntent.neutral:
      return (background: null, foreground: null);
    case ChipIntent.info:
      return (
        background: soliplex.colors.infoContainer,
        foreground: soliplex.colors.onInfoContainer,
      );
    case ChipIntent.success:
      return (
        background: soliplex.colors.successContainer,
        foreground: soliplex.colors.onSuccessContainer,
      );
    case ChipIntent.warning:
      return (
        background: soliplex.colors.warningContainer,
        foreground: soliplex.colors.onWarningContainer,
      );
    case ChipIntent.danger:
      return (
        background: soliplex.colors.errorContainer,
        foreground: soliplex.colors.onErrorContainer,
      );
  }
}
