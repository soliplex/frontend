import 'package:meta/meta.dart';

/// Font configuration for white-label customization.
///
/// Provides three font roles that map to the app's typographic hierarchy:
/// - [bodyFont]: UI text, paragraphs, labels, buttons (default: Material sans)
/// - [displayFont]: display text, AppBar titles, ListTile titles
/// - [brandFont]: reserved for special brand uses
///
/// All fields are nullable. When `null`, Material defaults apply (no
/// `fontFamily` is set on the TextStyle, so the framework's default is used).
///
/// Bundled fonts (registered in pubspec.yaml under `flutter.fonts`) resolve
/// from local assets. Non-bundled font names are resolved via the
/// `google_fonts` package at runtime.
///
/// Example:
/// ```dart
/// const config = FontConfig(
///   bodyFont: 'Inter',       // bundled asset
///   displayFont: 'Oswald',   // resolved via google_fonts
/// );
/// ```
@immutable
class FontConfig {
  /// Creates a font configuration with optional font roles.
  const FontConfig({
    this.bodyFont,
    this.displayFont,
    this.brandFont,
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

  /// Creates a copy with the specified fields replaced.
  ///
  /// Use `clear*` flags to reset a field to `null` (Material default).
  FontConfig copyWith({
    String? bodyFont,
    String? displayFont,
    String? brandFont,
    bool clearBodyFont = false,
    bool clearDisplayFont = false,
    bool clearBrandFont = false,
  }) {
    return FontConfig(
      bodyFont: clearBodyFont ? null : (bodyFont ?? this.bodyFont),
      displayFont: clearDisplayFont ? null : (displayFont ?? this.displayFont),
      brandFont: clearBrandFont ? null : (brandFont ?? this.brandFont),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontConfig &&
          runtimeType == other.runtimeType &&
          bodyFont == other.bodyFont &&
          displayFont == other.displayFont &&
          brandFont == other.brandFont;

  @override
  int get hashCode => Object.hash(bodyFont, displayFont, brandFont);

  @override
  String toString() => 'FontConfig('
      'bodyFont: $bodyFont, '
      'displayFont: $displayFont, '
      'brandFont: $brandFont)';
}
