import 'package:flutter/material.dart';

/// Bundled font family constants for the default Soliplex theme.
abstract final class FontFamilies {
  /// Body font — UI text, paragraphs, labels, buttons (bundled asset).
  static const String body = 'Inter';

  /// Display font — hero text, AppBar titles, ListTile titles (Google Fonts).
  static const String display = 'Oswald';

  /// Brand font — reserved for special brand uses (Google Fonts).
  static const String brand = 'SquadaOne';
}

/// Builds the Soliplex [TextTheme] with optional font overrides.
///
/// When [bodyFont] or [displayFont] are `null`, no `fontFamily` is set on
/// those styles, so Material's default sans-serif font is used.
TextTheme buildSoliplexTextTheme({String? bodyFont, String? displayFont}) {
  return TextTheme(
    // Display styles - large, prominent text
    displayLarge: TextStyle(
      fontFamily: displayFont,
      fontSize: 48,
      letterSpacing: -0.25,
      height: 1.2,
    ),
    displayMedium: TextStyle(
      fontFamily: displayFont,
      fontSize: 32,
      letterSpacing: 0,
      height: 1.8,
    ),
    displaySmall: TextStyle(
      fontFamily: displayFont,
      fontSize: 28,
      letterSpacing: 0,
      height: 2.15,
    ),

    // Headline styles - section headers
    headlineLarge: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w600,
      fontSize: 28,
      letterSpacing: 0,
      height: 1.25,
    ),
    headlineMedium: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w600,
      fontSize: 24,
      letterSpacing: 0,
      height: 2.4,
    ),
    headlineSmall: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w600,
      fontSize: 20,
      letterSpacing: 0,
      height: 2.8,
    ),

    // Title styles - card titles, list headers
    titleLarge: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w500,
      fontSize: 24,
      letterSpacing: 0,
      height: 1.27,
    ),
    titleMedium: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w500,
      fontSize: 18,
      letterSpacing: 0.15,
      height: 1.5,
    ),
    titleSmall: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w500,
      fontSize: 14,
      letterSpacing: 0.1,
      height: 1.43,
    ),

    // Body styles - paragraph text
    bodyLarge: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w400,
      fontSize: 16,
      letterSpacing: 0.5,
      height: 1.3,
    ),
    bodyMedium: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w400,
      fontSize: 13,
      letterSpacing: 0.25,
      height: 1.4,
    ),
    bodySmall: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w400,
      fontSize: 10,
      letterSpacing: 0.4,
      height: 1.6,
    ),

    // Label styles - buttons, chips, form labels
    labelLarge: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w500,
      fontSize: 16,
      letterSpacing: 0.1,
      height: 1.5,
    ),
    labelMedium: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w500,
      fontSize: 13,
      letterSpacing: 0.5,
      height: 1.5,
    ),
    labelSmall: TextStyle(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w500,
      fontSize: 10,
      letterSpacing: 0.5,
      height: 1.5,
    ),
  );
}
