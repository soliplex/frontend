/// Component theme builders for the Soliplex application.
///
/// Separates individual component themes from the main MaterialTheme class
/// to keep the theme configuration manageable and organized.
library;

import 'package:flutter/material.dart';

import '../../core/models/font_config.dart';
import '../design.dart';

const defaultButtonFontSize = 18.0;

/// Builds the AppBar theme with custom styling.
AppBarTheme buildAppBarTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) =>
    AppBarTheme(
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s2,
      ),
      backgroundColor: colorScheme.surfaceContainerHighest,
      shape: LinearBorder.bottom(
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      titleTextStyle: TextStyle(
        fontFamily: fontConfig?.displayFont,
        fontSize: 28,
        color: colorScheme.onSurface,
      ),
    );

/// Builds the ListTile theme with custom styling.
ListTileThemeData buildListTileTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) =>
    ListTileThemeData(
      shape: Border(
        bottom: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s2,
      ),
      horizontalTitleGap: 16,
      minVerticalPadding: 12,
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      titleTextStyle: TextStyle(
        fontFamily: fontConfig?.displayFont,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurfaceVariant,
      ),
      leadingAndTrailingTextStyle: TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      ),
    );

/// Builds the Divider theme with custom styling.
DividerThemeData buildDividerTheme(ColorScheme colorScheme) => DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
      thickness: 1,
      space: 0,
    );

/// Builds the Dialog theme with custom styling.
DialogThemeData buildDialogTheme(ColorScheme colorScheme) {
  return DialogThemeData(
    shape: const RoundedRectangleBorder(),
  );
}

/// Builds the InputDecoration theme with custom styling.
InputDecorationTheme buildInputDecorationTheme(ColorScheme colorScheme) {
  return InputDecorationTheme(
    border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: colorScheme.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: colorScheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: colorScheme.error, width: 2),
    ),
  );
}

/// Builds the Card theme with custom styling.
CardThemeData buildCardTheme(ColorScheme colorScheme) {
  return CardThemeData(
    color: colorScheme.surface,
    shadowColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: Border(
      bottom: BorderSide(color: colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
  );
}

/// Builds the FilledButton theme with custom styling.
FilledButtonThemeData buildFilledButtonTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s6,
        vertical: SoliplexSpacing.s4,
      ),
      textStyle: TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontWeight: FontWeight.w700,
        fontSize: defaultButtonFontSize,
      ),
    ),
  );
}

/// Builds the OutlinedButton theme with custom styling.
OutlinedButtonThemeData buildOutlinedButtonTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s3,
      ),
      textStyle: TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontWeight: FontWeight.w700,
        fontSize: defaultButtonFontSize,
      ),
    ),
  );
}

/// Builds the TextButton theme with custom styling.
TextButtonThemeData buildTextButtonTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s6,
        vertical: SoliplexSpacing.s4,
      ),
      textStyle: TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontWeight: FontWeight.w700,
        fontSize: defaultButtonFontSize,
      ),
    ),
  );
}

/// Builds the IconButton theme with custom styling.
IconButtonThemeData buildIconButtonTheme(ColorScheme colorScheme) {
  return IconButtonThemeData(
    style: IconButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s3,
      ),
    ),
  );
}

/// Builds the ElevatedButton theme with custom styling.
ElevatedButtonThemeData buildElevatedButtonTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s3,
      ),
      textStyle: TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontWeight: FontWeight.w700,
        fontSize: defaultButtonFontSize,
      ),
    ),
  );
}

/// Builds the ToggleButtons theme with custom styling.
ToggleButtonsThemeData buildToggleButtonsTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return ToggleButtonsThemeData(
    borderRadius: BorderRadius.zero,
    textStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Builds the SegmentedButton theme with custom styling.
SegmentedButtonThemeData buildSegmentedButtonTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return SegmentedButtonThemeData(
    style: ButtonStyle(
      shape: WidgetStatePropertyAll(
        const RoundedRectangleBorder(),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s4,
          vertical: SoliplexSpacing.s3,
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: fontConfig?.bodyFont,
          fontWeight: FontWeight.w700,
          fontSize: defaultButtonFontSize,
        ),
      ),
    ),
  );
}

/// Builds the FloatingActionButton theme with custom styling.
FloatingActionButtonThemeData buildFloatingActionButtonTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return FloatingActionButtonThemeData(
    shape: const RoundedRectangleBorder(),
    extendedTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontWeight: FontWeight.w600,
      fontSize: defaultButtonFontSize,
    ),
  );
}

/// Builds the DropdownMenu theme with custom styling.
DropdownMenuThemeData buildDropdownMenuTheme(ColorScheme colorScheme) {
  return DropdownMenuThemeData(
    menuStyle: MenuStyle(
      visualDensity: VisualDensity.compact,
      shape: WidgetStatePropertyAll(
        const RoundedRectangleBorder(),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
      ),
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      isDense: true,
      border: OutlineInputBorder(),
    ),
  );
}

/// Builds the PopupMenu theme with custom styling.
PopupMenuThemeData buildPopupMenuTheme(ColorScheme colorScheme) {
  return PopupMenuThemeData(
    shape: const RoundedRectangleBorder(),
  );
}

/// Builds the Chip theme with custom styling.
ChipThemeData buildChipTheme(ColorScheme colorScheme) {
  return ChipThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(
        color: colorScheme.outline,
      ),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: SoliplexSpacing.s2,
      vertical: SoliplexSpacing.s1,
    ),
    labelStyle: TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 1.2,
    ),
    backgroundColor: colorScheme.surfaceBright,
  );
}

/// Builds the Checkbox theme with custom styling.
CheckboxThemeData buildCheckboxTheme(ColorScheme colorScheme) {
  return CheckboxThemeData(
    shape: const RoundedRectangleBorder(),
  );
}

/// Builds the Radio theme with custom styling.
RadioThemeData buildRadioTheme(ColorScheme colorScheme) {
  return RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return colorScheme.primary;
      }
      return colorScheme.onSurfaceVariant;
    }),
  );
}

/// Builds the Slider theme with custom styling.
SliderThemeData buildSliderTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return SliderThemeData(
    trackShape: const RoundedRectSliderTrackShape(),
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: soliplexRadii.md / 2),
    overlayShape: RoundSliderOverlayShape(overlayRadius: soliplexRadii.lg),
    valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
    valueIndicatorTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Builds the Switch theme with custom styling.
SwitchThemeData buildSwitchTheme(ColorScheme colorScheme) {
  return SwitchThemeData(
    thumbIcon: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const Icon(Icons.check, size: 14);
      }
      return null;
    }),
  );
}

/// Builds the TabBar theme with custom styling.
TabBarThemeData buildTabBarTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return TabBarThemeData(
    indicatorSize: TabBarIndicatorSize.tab,
    dividerHeight: 1,
    labelStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    unselectedLabelStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    labelPadding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
  );
}

/// Builds the DatePicker theme with custom styling.
DatePickerThemeData buildDatePickerTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return DatePickerThemeData(
    shape: const RoundedRectangleBorder(),
    dayShape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    ),
    headerHelpStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 12,
    ),
  );
}

/// Builds the TimePicker theme with custom styling.
TimePickerThemeData buildTimePickerTheme(ColorScheme colorScheme) {
  return TimePickerThemeData(
    shape: const RoundedRectangleBorder(),
    hourMinuteShape: const RoundedRectangleBorder(),
    dayPeriodShape: const RoundedRectangleBorder(),
  );
}

/// Builds the SnackBar theme with custom styling.
SnackBarThemeData buildSnackBarTheme(ColorScheme colorScheme) {
  return SnackBarThemeData(
    shape: const RoundedRectangleBorder(),
    behavior: SnackBarBehavior.floating,
  );
}

/// Builds the BottomAppBar theme with custom styling.
BottomAppBarThemeData buildBottomAppBarTheme(ColorScheme colorScheme) {
  return BottomAppBarThemeData(
    shape: AutomaticNotchedShape(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
  );
}

/// Builds the BottomSheet theme with custom styling.
BottomSheetThemeData buildBottomSheetTheme(ColorScheme colorScheme) {
  return BottomSheetThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
    ),
    showDragHandle: true,
  );
}

/// Builds the BottomNavigationBar theme with custom styling.
BottomNavigationBarThemeData buildBottomNavigationBarTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return BottomNavigationBarThemeData(
    selectedItemColor: colorScheme.primary,
    unselectedItemColor: colorScheme.onSurfaceVariant,
    type: BottomNavigationBarType.fixed,
    selectedLabelStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    unselectedLabelStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 12,
    ),
    selectedIconTheme: const IconThemeData(size: SoliplexSpacing.s6),
    unselectedIconTheme: const IconThemeData(size: SoliplexSpacing.s6),
  );
}

/// Builds the NavigationBar theme with custom styling.
NavigationBarThemeData buildNavigationBarTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return NavigationBarThemeData(
    indicatorShape: const RoundedRectangleBorder(),
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    height: 72,
  );
}

/// Builds the NavigationRail theme with custom styling.
NavigationRailThemeData buildNavigationRailTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return NavigationRailThemeData(
    indicatorShape: const RoundedRectangleBorder(),
    labelType: NavigationRailLabelType.all,
    groupAlignment: 0,
    minWidth: 80,
    selectedLabelTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colorScheme.primary,
    ),
    unselectedLabelTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
    ),
  );
}

/// Builds the NavigationDrawer theme with custom styling.
NavigationDrawerThemeData buildNavigationDrawerTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return NavigationDrawerThemeData(
    indicatorShape: const RoundedRectangleBorder(),
    tileHeight: 48,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// Builds the Drawer theme with custom styling.
DrawerThemeData buildDrawerTheme(ColorScheme colorScheme) {
  return DrawerThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
    ),
    endShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
    ),
  );
}

/// Builds the Tooltip theme with custom styling.
TooltipThemeData buildTooltipTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return TooltipThemeData(
    decoration: BoxDecoration(
      color: colorScheme.inverseSurface,
      borderRadius: BorderRadius.zero,
    ),
    textStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 12,
      color: colorScheme.onInverseSurface,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: SoliplexSpacing.s3,
      vertical: SoliplexSpacing.s2,
    ),
  );
}

/// Builds the Badge theme with custom styling.
BadgeThemeData buildBadgeTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return BadgeThemeData(
    backgroundColor: colorScheme.error,
    textColor: colorScheme.onError,
    textStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
    padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
    largeSize: 18,
    smallSize: 10,
  );
}

/// Builds the Menu theme with custom styling.
MenuThemeData buildMenuTheme(ColorScheme colorScheme) {
  return MenuThemeData(
    style: MenuStyle(
      shape: WidgetStatePropertyAll(
        const RoundedRectangleBorder(),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
      ),
    ),
  );
}

/// Builds the MenuBar theme with custom styling.
MenuBarThemeData buildMenuBarTheme(ColorScheme colorScheme) {
  return MenuBarThemeData(
    style: MenuStyle(
      shape: WidgetStatePropertyAll(
        const RoundedRectangleBorder(),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
      ),
    ),
  );
}

/// Builds the MenuButton theme with custom styling.
MenuButtonThemeData buildMenuButtonTheme(ColorScheme colorScheme) {
  return MenuButtonThemeData(
    style: ButtonStyle(
      shape: WidgetStatePropertyAll(
        const RoundedRectangleBorder(),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s4,
          vertical: SoliplexSpacing.s3,
        ),
      ),
    ),
  );
}

/// Builds the ExpansionTile theme with custom styling.
ExpansionTileThemeData buildExpansionTileTheme(ColorScheme colorScheme) {
  return ExpansionTileThemeData(
    shape: const RoundedRectangleBorder(),
    collapsedShape: const RoundedRectangleBorder(),
    tilePadding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
    childrenPadding: const EdgeInsets.all(SoliplexSpacing.s4),
  );
}

/// Builds the SearchBar theme with custom styling.
SearchBarThemeData buildSearchBarTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return SearchBarThemeData(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
    ),
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontSize: 16,
      ),
    ),
    hintStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: fontConfig?.bodyFont,
        fontSize: 16,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Builds the SearchView theme with custom styling.
SearchViewThemeData buildSearchViewTheme(ColorScheme colorScheme) {
  return SearchViewThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
    ),
  );
}

/// Builds the ProgressIndicator theme with custom styling.
ProgressIndicatorThemeData buildProgressIndicatorTheme(
  ColorScheme colorScheme,
) {
  return ProgressIndicatorThemeData(
    linearTrackColor: colorScheme.surfaceContainerHighest,
    linearMinHeight: 4,
    circularTrackColor: colorScheme.surfaceContainerHighest,
  );
}

/// Builds the Banner (MaterialBanner) theme with custom styling.
MaterialBannerThemeData buildBannerTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return MaterialBannerThemeData(
    padding: const EdgeInsets.all(SoliplexSpacing.s4),
    leadingPadding: const EdgeInsets.only(right: SoliplexSpacing.s4),
    contentTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      color: colorScheme.onSurface,
    ),
  );
}

/// Builds the DataTable theme with custom styling.
DataTableThemeData buildDataTableTheme(
  ColorScheme colorScheme, {
  FontConfig? fontConfig,
}) {
  return DataTableThemeData(
    headingTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    ),
    dataTextStyle: TextStyle(
      fontFamily: fontConfig?.bodyFont,
      fontSize: 14,
      color: colorScheme.onSurface,
    ),
    horizontalMargin: SoliplexSpacing.s4,
    columnSpacing: SoliplexSpacing.s6,
    dataRowMinHeight: 48,
    headingRowHeight: 60,
  );
}
