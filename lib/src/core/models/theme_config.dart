import 'package:meta/meta.dart';

import 'color_config.dart';
import 'font_config.dart';

/// Theme configuration for white-label customization.
///
/// Groups color and font customization into two optional config objects:
/// - [colorConfig]: brand color palettes for light and dark modes
/// - [fontConfig]: font families (body, display, brand)
///
/// When either config is `null`, all defaults for that category apply.
///
/// Example:
/// ```dart
/// const config = ThemeConfig(
///   colorConfig: ColorConfig(),
/// );
/// ```
@immutable
class ThemeConfig {
  /// Creates a theme configuration with optional color and font configs.
  ///
  /// Both [colorConfig] and [fontConfig] default to `null`, which means
  /// all color defaults and Material default fonts apply respectively.
  const ThemeConfig({
    this.colorConfig,
    this.fontConfig,
  });

  /// Optional color configuration for white-label color customization.
  ///
  /// When `null`, all default colors apply (see [ColorConfig] defaults).
  final ColorConfig? colorConfig;

  /// Optional font configuration for white-label font customization.
  ///
  /// When `null`, Material defaults apply (no custom font families).
  final FontConfig? fontConfig;

  /// Creates a copy with the specified fields replaced.
  ///
  /// Use `clear*` flags to reset a field to `null` (all defaults).
  ThemeConfig copyWith({
    ColorConfig? colorConfig,
    FontConfig? fontConfig,
    bool clearColorConfig = false,
    bool clearFontConfig = false,
  }) {
    return ThemeConfig(
      colorConfig: clearColorConfig ? null : (colorConfig ?? this.colorConfig),
      fontConfig: clearFontConfig ? null : (fontConfig ?? this.fontConfig),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeConfig &&
          runtimeType == other.runtimeType &&
          colorConfig == other.colorConfig &&
          fontConfig == other.fontConfig;

  @override
  int get hashCode => Object.hash(colorConfig, fontConfig);

  @override
  String toString() => 'ThemeConfig('
      'colorConfig: $colorConfig, '
      'fontConfig: $fontConfig)';
}
