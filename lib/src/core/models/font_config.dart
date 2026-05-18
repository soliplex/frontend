import 'package:meta/meta.dart';

/// Font configuration for white-label customization.
///
/// Provides four font roles that map to the app's typographic hierarchy:
/// - [bodyFont]: UI text, paragraphs, labels, buttons (default: Material sans)
/// - [displayFont]: display text, AppBar titles, ListTile titles
/// - [brandFont]: reserved for special brand uses
/// - [codeFont]: code blocks, inline code, monospaced content
///
/// All fields are nullable. When `null`, Material defaults apply (no
/// `fontFamily` is set on the TextStyle, so the framework's default is used).
/// For [codeFont], `null` means platform-adaptive monospace (SF Mono on Apple,
/// Roboto Mono elsewhere, with generic `monospace` fallback).
///
/// Bundled fonts (registered in pubspec.yaml under `flutter.fonts`) resolve
/// from local assets. Non-bundled font names are resolved via the
/// `google_fonts` package at runtime.
///
/// Example:
/// ```dart
/// const config = FontConfig(
///   bodyFont: 'Inter',          // bundled asset
///   displayFont: 'Oswald',      // resolved via google_fonts
///   codeFont: 'JetBrains Mono', // resolved via google_fonts
/// );
/// ```
@immutable
class FontConfig {
  /// Creates a font configuration with optional font roles.
  const FontConfig({
    this.bodyFont,
    this.displayFont,
    this.brandFont,
    this.codeFont,
  });

  /// Font family for body text, labels, and buttons.
  ///
  /// When `null`, Material's default sans-serif font is used.
  final String? bodyFont;

  /// Font family for display text, AppBar titles, and ListTile titles.
  ///
  /// When `null`, Material's default sans-serif font is used.
  final String? displayFont;

  /// Font family reserved for special brand uses.
  ///
  /// When `null`, Material's default sans-serif font is used.
  final String? brandFont;

  /// Font family for code blocks, inline code, and monospaced content.
  ///
  /// When `null`, a platform-adaptive monospace font is used (SF Mono on
  /// Apple platforms, Roboto Mono elsewhere, with generic `monospace`
  /// fallback).
  final String? codeFont;

  /// Creates a copy with the specified fields replaced.
  ///
  /// Use `clear*` flags to reset a field to `null` (Material default).
  FontConfig copyWith({
    String? bodyFont,
    String? displayFont,
    String? brandFont,
    String? codeFont,
    bool clearBodyFont = false,
    bool clearDisplayFont = false,
    bool clearBrandFont = false,
    bool clearCodeFont = false,
  }) {
    return FontConfig(
      bodyFont: clearBodyFont ? null : (bodyFont ?? this.bodyFont),
      displayFont: clearDisplayFont ? null : (displayFont ?? this.displayFont),
      brandFont: clearBrandFont ? null : (brandFont ?? this.brandFont),
      codeFont: clearCodeFont ? null : (codeFont ?? this.codeFont),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontConfig &&
          runtimeType == other.runtimeType &&
          bodyFont == other.bodyFont &&
          displayFont == other.displayFont &&
          brandFont == other.brandFont &&
          codeFont == other.codeFont;

  @override
  int get hashCode => Object.hash(bodyFont, displayFont, brandFont, codeFont);

  @override
  String toString() => 'FontConfig('
      'bodyFont: $bodyFont, '
      'displayFont: $displayFont, '
      'brandFont: $brandFont, '
      'codeFont: $codeFont)';
}
