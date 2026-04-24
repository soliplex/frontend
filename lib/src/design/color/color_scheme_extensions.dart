import 'package:flutter/material.dart';

/// Semantic color seeds for generating tonal palettes.
///
/// These are the base colors used to generate Material 3 tonal palettes
/// for semantic status colors not included in the standard ColorScheme.
abstract final class SemanticSeeds {
  static const success = Color(0xFF2E7D32); // Green 800
  static const warning = Color(0xFFE65100); // Orange 900
  static const info = Color(0xFF1565C0); // Blue 800
}

/// Pre-computed tonal palettes for semantic colors.
///
/// Generated once from [SemanticSeeds] to avoid repeated computation.
/// Uses Material 3's tonal system for consistent light/dark adaptation.
abstract final class _SemanticPalettes {
  static final _successLight = ColorScheme.fromSeed(
    seedColor: SemanticSeeds.success,
  );
  static final _successDark = ColorScheme.fromSeed(
    seedColor: SemanticSeeds.success,
    brightness: Brightness.dark,
  );
  static final _warningLight = ColorScheme.fromSeed(
    seedColor: SemanticSeeds.warning,
  );
  static final _warningDark = ColorScheme.fromSeed(
    seedColor: SemanticSeeds.warning,
    brightness: Brightness.dark,
  );
  static final _infoLight = ColorScheme.fromSeed(
    seedColor: SemanticSeeds.info,
  );
  static final _infoDark = ColorScheme.fromSeed(
    seedColor: SemanticSeeds.info,
    brightness: Brightness.dark,
  );

  static ColorScheme success(Brightness brightness) =>
      brightness == Brightness.light ? _successLight : _successDark;

  static ColorScheme warning(Brightness brightness) =>
      brightness == Brightness.light ? _warningLight : _warningDark;

  static ColorScheme info(Brightness brightness) =>
      brightness == Brightness.light ? _infoLight : _infoDark;
}

/// Semantic status colors that adapt to light/dark themes.
///
/// Material 3's [ColorScheme] only includes `error` for status colors.
/// This extension adds `success`, `warning`, and `info` using the same
/// tonal system for visual consistency.
///
/// Each color has a corresponding `on*` color for proper text contrast,
/// and a `*Container`/`on*Container` pair for filled backgrounds.
extension SemanticColors on ColorScheme {
  // ---------------------------------------------------------------------------
  // Success (green) - positive outcomes, completed actions
  // ---------------------------------------------------------------------------

  /// Success color for icons and text.
  Color get success => _SemanticPalettes.success(brightness).primary;

  /// Contrast color for text/icons on [success] background.
  Color get onSuccess => _SemanticPalettes.success(brightness).onPrimary;

  /// Muted success background for containers.
  Color get successContainer =>
      _SemanticPalettes.success(brightness).primaryContainer;

  /// Contrast color for text/icons on [successContainer].
  Color get onSuccessContainer =>
      _SemanticPalettes.success(brightness).onPrimaryContainer;

  // ---------------------------------------------------------------------------
  // Warning (orange) - caution states, client errors
  // ---------------------------------------------------------------------------

  /// Warning color for icons and text.
  Color get warning => _SemanticPalettes.warning(brightness).primary;

  /// Contrast color for text/icons on [warning] background.
  Color get onWarning => _SemanticPalettes.warning(brightness).onPrimary;

  /// Muted warning background for containers.
  Color get warningContainer =>
      _SemanticPalettes.warning(brightness).primaryContainer;

  /// Contrast color for text/icons on [warningContainer].
  Color get onWarningContainer =>
      _SemanticPalettes.warning(brightness).onPrimaryContainer;

  // ---------------------------------------------------------------------------
  // Info (blue) - informational states, neutral highlights
  // ---------------------------------------------------------------------------

  /// Info color for icons and text.
  Color get info => _SemanticPalettes.info(brightness).primary;

  /// Contrast color for text/icons on [info] background.
  Color get onInfo => _SemanticPalettes.info(brightness).onPrimary;

  /// Muted info background for containers.
  Color get infoContainer =>
      _SemanticPalettes.info(brightness).primaryContainer;

  /// Contrast color for text/icons on [infoContainer].
  Color get onInfoContainer =>
      _SemanticPalettes.info(brightness).onPrimaryContainer;
}
