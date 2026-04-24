import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/color_config.dart';
import '../../core/models/font_config.dart';
import '../../modules/room/ui/markdown/markdown_theme_extension.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'component_themes.dart';
import 'theme_extensions.dart';

// ---------------------------------------------------------------------------
// Color Scheme Generation
// ---------------------------------------------------------------------------

/// Generates a Material 3 [ColorScheme] from a [ColorPalette].
///
/// Maps palette roles directly to [ColorScheme] fields and derives container,
/// surface, and outline variations via simple color math — no `fromSeed()`.
ColorScheme generateColorScheme({
  required Brightness brightness,
  required ColorPalette palette,
}) {
  final bg = palette.background;
  final fg = palette.foreground;
  final m = palette.muted;
  final p = palette.primary;
  final s = palette.secondary;
  final t = palette.effectiveTertiary;
  final e = palette.effectiveError;

  // Surface container scale — non-linear steps.
  final scLowest = Color.lerp(bg, m, 0.05);
  final scLow = Color.lerp(bg, m, 0.15);
  final sc = Color.lerp(bg, m, 0.30);
  final scHigh = Color.lerp(bg, m, 0.55);
  final scHighest = Color.lerp(bg, m, 0.80);

  // Surface variants.
  final surfaceDim = Color.lerp(bg, m, 0.40);
  final surfaceBright = brightness == Brightness.light
      ? Color.lerp(bg, Colors.white, 0.5)
      : Color.lerp(bg, fg, 0.08);

  // Fixed roles — same in light & dark.
  final primaryFixed = Color.lerp(p, Colors.white, 0.80);
  final primaryFixedDim = Color.lerp(p, Colors.white, 0.60);
  final onPrimaryFixed = Color.lerp(p, Colors.black, 0.70);
  final onPrimaryFixedVariant = Color.lerp(p, Colors.black, 0.50);
  final secondaryFixed = Color.lerp(s, Colors.white, 0.80);
  final secondaryFixedDim = Color.lerp(s, Colors.white, 0.60);
  final onSecondaryFixed = Color.lerp(s, Colors.black, 0.70);
  final onSecondaryFixedVariant = Color.lerp(s, Colors.black, 0.50);
  final tertiaryFixed = Color.lerp(t, Colors.white, 0.80);
  final tertiaryFixedDim = Color.lerp(t, Colors.white, 0.60);
  final onTertiaryFixed = Color.lerp(t, Colors.black, 0.70);
  final onTertiaryFixedVariant = Color.lerp(t, Colors.black, 0.50);

  return ColorScheme(
    brightness: brightness,

    // Primary
    primary: p,
    onPrimary: palette.effectiveOnPrimary,
    primaryContainer: Color.lerp(p, bg, 0.85),
    onPrimaryContainer: Color.lerp(p, fg, 0.7),

    // Secondary
    secondary: s,
    onSecondary: palette.effectiveOnSecondary,
    secondaryContainer: Color.lerp(s, bg, 0.80),
    onSecondaryContainer: Color.lerp(s, fg, 0.7),

    // Tertiary
    tertiary: t,
    onTertiary: palette.effectiveOnTertiary,
    tertiaryContainer: Color.lerp(t, bg, 0.80),
    onTertiaryContainer: Color.lerp(t, fg, 0.7),

    // Error
    error: e,
    onError: palette.effectiveOnError,
    errorContainer: Color.lerp(e, bg, 0.85),
    onErrorContainer: Color.lerp(e, fg, 0.7),

    // Surfaces
    surface: bg,
    onSurface: fg,
    onSurfaceVariant: palette.mutedForeground,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: scLowest,
    surfaceContainerLow: scLow,
    surfaceContainer: sc,
    surfaceContainerHigh: scHigh,
    surfaceContainerHighest: scHighest,

    // Outline
    outline: palette.border,
    outlineVariant: Color.lerp(palette.border, bg, 0.5),

    // Inverse
    inverseSurface: fg,
    onInverseSurface: bg,
    inversePrimary: Color.lerp(p, bg, 0.4),

    // Misc
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
    scrim: Colors.black,

    // Fixed
    primaryFixed: primaryFixed,
    primaryFixedDim: primaryFixedDim,
    onPrimaryFixed: onPrimaryFixed,
    onPrimaryFixedVariant: onPrimaryFixedVariant,
    secondaryFixed: secondaryFixed,
    secondaryFixedDim: secondaryFixedDim,
    onSecondaryFixed: onSecondaryFixed,
    onSecondaryFixedVariant: onSecondaryFixedVariant,
    tertiaryFixed: tertiaryFixed,
    tertiaryFixedDim: tertiaryFixedDim,
    onTertiaryFixed: onTertiaryFixed,
    onTertiaryFixedVariant: onTertiaryFixedVariant,
  );
}

// ---------------------------------------------------------------------------
// Theme Creation Functions
// ---------------------------------------------------------------------------

/// Create the light ThemeData with optional brand colors and fonts.
///
/// Uses [buildSoliplexTextTheme] to create the text theme. When [fontConfig]
/// is `null`, Material default fonts apply.
///
/// Colors are read from [colorConfig] with fallbacks to defaults.
ThemeData soliplexLightTheme({
  ColorConfig? colorConfig,
  FontConfig? fontConfig,
}) {
  final colors = colorConfig ?? const ColorConfig();
  final colorScheme = generateColorScheme(
    brightness: Brightness.light,
    palette: colors.light,
  );
  return _buildTheme(colorScheme, fontConfig: fontConfig);
}

/// Create the dark ThemeData with optional brand colors and fonts.
///
/// Uses [buildSoliplexTextTheme] to create the text theme. When [fontConfig]
/// is `null`, Material default fonts apply.
///
/// Colors are read from [colorConfig] with fallbacks to defaults.
ThemeData soliplexDarkTheme({
  ColorConfig? colorConfig,
  FontConfig? fontConfig,
}) {
  final colors = colorConfig ?? const ColorConfig();
  final colorScheme = generateColorScheme(
    brightness: Brightness.dark,
    palette: colors.dark,
  );
  return _buildTheme(colorScheme, fontConfig: fontConfig);
}

// ---------------------------------------------------------------------------
// Theme Building
// ---------------------------------------------------------------------------

/// Builds a complete ThemeData from a ColorScheme and optional FontConfig.
///
/// Font resolution strategy:
/// - Bundled fonts (e.g. Inter, registered in pubspec.yaml) resolve from
///   local assets automatically.
/// - Non-bundled fonts (e.g. Oswald, Squada One) are resolved via the
///   `google_fonts` package, which fetches and caches them at runtime.
/// - [GoogleFonts.getTextTheme] is used to wrap the text theme so that
///   all font family strings are resolved through google_fonts. Bundled
///   fonts take precedence when available.
ThemeData _buildTheme(ColorScheme colorScheme, {FontConfig? fontConfig}) {
  var textTheme = buildSoliplexTextTheme(
    bodyFont: fontConfig?.bodyFont,
    displayFont: fontConfig?.displayFont,
  );

  // Resolve non-bundled fonts via google_fonts.
  textTheme = GoogleFonts.getTextTheme(
    fontConfig?.bodyFont ?? FontFamilies.body,
    textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    textTheme: textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    canvasColor: colorScheme.surface,
    appBarTheme: buildAppBarTheme(colorScheme, fontConfig: fontConfig),
    listTileTheme: buildListTileTheme(colorScheme, fontConfig: fontConfig),
    dividerTheme: buildDividerTheme(colorScheme),
    dialogTheme: buildDialogTheme(colorScheme),
    inputDecorationTheme: buildInputDecorationTheme(colorScheme),
    cardTheme: buildCardTheme(colorScheme),
    filledButtonTheme:
        buildFilledButtonTheme(colorScheme, fontConfig: fontConfig),
    outlinedButtonTheme:
        buildOutlinedButtonTheme(colorScheme, fontConfig: fontConfig),
    textButtonTheme: buildTextButtonTheme(colorScheme, fontConfig: fontConfig),
    iconButtonTheme: buildIconButtonTheme(colorScheme),
    elevatedButtonTheme:
        buildElevatedButtonTheme(colorScheme, fontConfig: fontConfig),
    toggleButtonsTheme:
        buildToggleButtonsTheme(colorScheme, fontConfig: fontConfig),
    segmentedButtonTheme:
        buildSegmentedButtonTheme(colorScheme, fontConfig: fontConfig),
    floatingActionButtonTheme:
        buildFloatingActionButtonTheme(colorScheme, fontConfig: fontConfig),
    dropdownMenuTheme: buildDropdownMenuTheme(colorScheme),
    popupMenuTheme: buildPopupMenuTheme(colorScheme),
    chipTheme: buildChipTheme(colorScheme),
    searchBarTheme: buildSearchBarTheme(colorScheme, fontConfig: fontConfig),
    searchViewTheme: buildSearchViewTheme(colorScheme),
    checkboxTheme: buildCheckboxTheme(colorScheme),
    radioTheme: buildRadioTheme(colorScheme),
    sliderTheme: buildSliderTheme(colorScheme, fontConfig: fontConfig),
    switchTheme: buildSwitchTheme(colorScheme),
    tabBarTheme: buildTabBarTheme(colorScheme, fontConfig: fontConfig),
    datePickerTheme: buildDatePickerTheme(colorScheme, fontConfig: fontConfig),
    timePickerTheme: buildTimePickerTheme(colorScheme),
    snackBarTheme: buildSnackBarTheme(colorScheme),
    bottomAppBarTheme: buildBottomAppBarTheme(colorScheme),
    bottomSheetTheme: buildBottomSheetTheme(colorScheme),
    bottomNavigationBarTheme:
        buildBottomNavigationBarTheme(colorScheme, fontConfig: fontConfig),
    navigationBarTheme:
        buildNavigationBarTheme(colorScheme, fontConfig: fontConfig),
    navigationDrawerTheme:
        buildNavigationDrawerTheme(colorScheme, fontConfig: fontConfig),
    navigationRailTheme:
        buildNavigationRailTheme(colorScheme, fontConfig: fontConfig),
    drawerTheme: buildDrawerTheme(colorScheme),
    tooltipTheme: buildTooltipTheme(colorScheme, fontConfig: fontConfig),
    badgeTheme: buildBadgeTheme(colorScheme, fontConfig: fontConfig),
    menuTheme: buildMenuTheme(colorScheme),
    menuBarTheme: buildMenuBarTheme(colorScheme),
    menuButtonTheme: buildMenuButtonTheme(colorScheme),
    expansionTileTheme: buildExpansionTileTheme(colorScheme),
    progressIndicatorTheme: buildProgressIndicatorTheme(colorScheme),
    bannerTheme: buildBannerTheme(colorScheme, fontConfig: fontConfig),
    dataTableTheme: buildDataTableTheme(colorScheme, fontConfig: fontConfig),
    extensions: [
      SoliplexTheme(
        colors: colorScheme,
        radii: soliplexRadii,
        codeFont: fontConfig?.codeFont,
        badgeTheme: SoliplexBadgeThemeData(
          background: Color.alphaBlend(
            colorScheme.onSurface.withAlpha(15),
            colorScheme.surface,
          ),
          textStyle: textTheme.labelMedium!.copyWith(
            color: colorScheme.onSurface,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s2,
            vertical: SoliplexSpacing.s1,
          ),
        ),
      ),
      _markdownThemeExtension(colorScheme, textTheme),
    ],
  );
}

MarkdownThemeExtension _markdownThemeExtension(
  ColorScheme colorScheme,
  TextTheme textTheme,
) {
  return MarkdownThemeExtension(
    h1: textTheme.titleLarge,
    h2: textTheme.titleMedium,
    h3: textTheme.titleSmall,
    body: textTheme.bodyLarge,
    code: textTheme.bodyMedium?.copyWith(
      backgroundColor: colorScheme.surfaceContainerHigh,
    ),
    link: TextStyle(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: colorScheme.primary,
    ),
    codeBlockDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.zero,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      border: Border(
        left: BorderSide(
          color: colorScheme.outlineVariant,
          width: 3,
        ),
      ),
    ),
  );
}
