import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/classification_theme.dart';
import 'package:soliplex_design/src/theme/markdown_theme_extension.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_design/src/tokens/radii.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';
import 'package:soliplex_design/src/tokens/typography.dart';

ThemeData soliplexLightTheme({
  SoliplexColors colors = lightSoliplexColors,
  ClassificationTheme? classifications,
}) =>
    _buildTheme(
      colors: colors,
      brightness: Brightness.light,
      classifications: classifications,
    );

ThemeData soliplexDarkTheme({
  SoliplexColors colors = darkSoliplexColors,
  ClassificationTheme? classifications,
}) =>
    _buildTheme(
      colors: colors,
      brightness: Brightness.dark,
      classifications: classifications,
    );

ThemeData _buildTheme({
  required SoliplexColors colors,
  required Brightness brightness,
  ClassificationTheme? classifications,
}) {
  final textTheme = soliplexTextTheme(colors);
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.primaryContainer,
    onPrimaryContainer: colors.onPrimaryContainer,
    secondary: colors.secondary,
    onSecondary: colors.onSecondary,
    secondaryContainer: colors.muted,
    onSecondaryContainer: colors.mutedForeground,
    tertiary: colors.tertiary,
    onTertiary: colors.onTertiary,
    tertiaryContainer: colors.tertiaryContainer,
    onTertiaryContainer: colors.onTertiaryContainer,
    error: colors.destructive,
    onError: colors.onDestructive,
    errorContainer: colors.errorContainer,
    onErrorContainer: colors.onErrorContainer,
    surface: colors.background,
    onSurface: colors.foreground,
    onSurfaceVariant: colors.mutedForeground,
    surfaceContainerLowest: colors.surfaceContainerLowest,
    surfaceContainerLow: colors.surfaceContainerLow,
    surfaceContainer: colors.inputBackground,
    surfaceContainerHigh: colors.surfaceContainerHigh,
    surfaceContainerHighest: colors.surfaceContainerHighest,
    surfaceDim: colors.accent,
    surfaceBright: colors.background,
    outline: colors.outline,
    outlineVariant: colors.outlineVariant,
    inverseSurface: colors.primary,
    onInverseSurface: colors.onPrimary,
    inversePrimary: colors.inversePrimary,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    surfaceTint: colors.primary,
  );

  // Lets validation/helper text wrap instead of ellipsizing in narrow
  // fields. Shared so inputs and dropdowns (separate decoration channels)
  // can't drift apart.
  const inputFeedbackMaxLines = 2;

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.onPrimary,
      foregroundColor: colors.primary,
      elevation: 0,
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s2,
      ),
      shape: Border(bottom: BorderSide(color: colors.border)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: 1,
      space: 1,
    ),
    buttonTheme: ButtonThemeData(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
        side: BorderSide(color: colors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.inputBackground,
      helperMaxLines: inputFeedbackMaxLines,
      errorMaxLines: inputFeedbackMaxLines,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        borderSide: BorderSide(color: colors.border, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        borderSide: BorderSide(color: colors.destructive),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        borderSide: BorderSide(color: colors.destructive, width: 2),
      ),
      hintStyle: TextStyle(color: colors.hintText),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      selectedColor: colors.primary,
      selectedTileColor: colors.inputBackground,
    ),
    cardTheme: CardThemeData(
      color: colors.inputBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      elevation: 0,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      collapsedShape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      collapsedBackgroundColor: colors.inputBackground,
      backgroundColor: colors.onPrimary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.inputBackground,
      selectedColor: colors.primary.withAlpha(25),
      disabledColor: colors.muted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
        side: BorderSide(color: colors.border),
      ),
      labelStyle: TextStyle(color: colors.foreground),
      secondaryLabelStyle: TextStyle(color: colors.foreground),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s2,
        vertical: SoliplexSpacing.s1,
      ),
      secondarySelectedColor: colors.primary.withAlpha(25),
      brightness: brightness,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
    ),
    toggleButtonsTheme: ToggleButtonsThemeData(
      borderRadius: BorderRadius.circular(soliplexRadii.md),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: textTheme.bodyMedium,
      menuStyle: MenuStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStateProperty.all<OutlinedBorder?>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(soliplexRadii.md),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
        helperMaxLines: inputFeedbackMaxLines,
        errorMaxLines: inputFeedbackMaxLines,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      textStyle: textTheme.bodyMedium,
    ),
    scaffoldBackgroundColor: colors.background,
    useMaterial3: true,
    textTheme: textTheme,
    extensions: [
      classifications ?? ClassificationTheme.fallback,
      SoliplexTheme(
        colors: colors,
        radii: soliplexRadii,
        badgeTheme: SoliplexBadgeThemeData(
          background: Color.alphaBlend(
            colors.foreground.withAlpha(15),
            colors.background,
          ),
          textStyle: textTheme.labelMedium!.copyWith(color: colors.foreground),
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s2,
            vertical: SoliplexSpacing.s1,
          ),
        ),
      ),
      MarkdownThemeExtension(
        h1: textTheme.titleLarge,
        h2: textTheme.titleMedium,
        h3: textTheme.titleSmall,
        body: textTheme.bodyMedium,
        code: textTheme.bodyMedium?.copyWith(
          backgroundColor: colorScheme.surfaceContainerHighest,
        ),
        link: TextStyle(
          color: colors.link,
          decoration: TextDecoration.underline,
          decorationColor: colors.link,
        ),
        codeBlockDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
        blockquoteDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              color: colorScheme.outlineVariant,
              width: 3,
            ),
          ),
        ),
      ),
    ],
  );
}
