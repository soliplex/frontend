# Custom Theme Branch — Change Documentation

This document covers all changes introduced by the `custom-theme` branch compared
to `main`. It details the white-label theming architecture, design system
improvements, UI polish, and provides implementation guidance for manually
applying these changes.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Changes](#architecture-changes)
3. [Color System](#color-system)
4. [Font System](#font-system)
5. [Theme Building](#theme-building)
6. [Component Themes](#component-themes)
7. [Dark Mode Support](#dark-mode-support)
8. [AppBar and Navigation](#appbar-and-navigation)
9. [Semantic Colors](#semantic-colors)
10. [Typography Overhaul](#typography-overhaul)
11. [UI Polish](#ui-polish)
12. [New Shared Widgets](#new-shared-widgets)
13. [Test Coverage](#test-coverage)
14. [Benefits](#benefits)
15. [Manual Implementation Guide](custom-theme-branch-implementation.md)

---

## Overview

The `custom-theme` branch replaces the hardcoded color token system with a
dynamic, white-label-ready theming architecture. The key changes:

- **60 files changed** — +4,099 lines / -1,045 lines
- Replaces `SoliplexColors` (15 hardcoded tokens) with `ColorConfig` + `ColorPalette` (7 required + 6 optional roles per brightness)
- Introduces `FontConfig` with 3 font roles (body, display, brand)
- Adds full dark mode support with persistent theme toggle
- Extracts 40+ component themes into a dedicated module
- Generates the complete Material 3 `ColorScheme` from palette roles via direct color math (no `ColorScheme.fromSeed()`)
- Bundles custom fonts (Inter, Hyprsalvo, Tactical)
- Adds brand logo and app name rendering in the AppBar

---

## Architecture Changes

### Before (`main`)

```text
ThemeConfig
  +-- lightColors: SoliplexColors (15 fixed fields)
  +-- darkColors: SoliplexColors (15 fixed fields)

SoliplexColors -> manually mapped to partial ColorScheme
Theme built inline in soliplexLightTheme() / soliplexDarkTheme()
ThemeMode hardcoded to ThemeMode.light
```

### After (`custom-theme`)

```text
ThemeConfig
  +-- colorConfig: ColorConfig?
  |     +-- light: ColorPalette (7 required + 6 optional roles)
  |     +-- dark:  ColorPalette (7 required + 6 optional roles)
  +-- fontConfig: FontConfig?
        +-- bodyFont:    String?
        +-- displayFont: String?
        +-- brandFont:   String?

ColorPalette -> generateColorScheme() -> full Material 3 ColorScheme
ColorScheme + FontConfig -> _buildTheme() -> component theme builders -> ThemeData
ThemeMode reactive via themeModeProvider (persisted to SharedPreferences)
```

### Key files added or changed

| File | Status | Purpose |
|------|--------|---------|
| `lib/core/models/color_config.dart` | **New** | `ColorPalette` and `ColorConfig` models |
| `lib/core/models/font_config.dart` | **New** | `FontConfig` model with 3 font roles |
| `lib/core/models/theme_config.dart` | Modified | Now holds `ColorConfig?` + `FontConfig?` instead of `SoliplexColors` |
| `lib/core/providers/theme_provider.dart` | **New** | `ThemeModeNotifier` + `themeModeProvider` with SharedPreferences persistence |
| `lib/design/theme/theme.dart` | Rewritten | `generateColorScheme()` + unified `_buildTheme()` |
| `lib/design/theme/component_themes.dart` | **New** | 40+ extracted component theme builders |
| `lib/design/tokens/colors.dart` | **Deleted** | Old `SoliplexColors` class and constants |
| `lib/design/tokens/typography.dart` | Rewritten | `buildSoliplexTextTheme()` with full Material 3 type scale |
| `lib/design/color/color_scheme_extensions.dart` | Expanded | Tonal semantic colors (success, warning, info) |
| `lib/shared/widgets/theme_toggle_button.dart` | **New** | Light/dark toggle button |
| `lib/shared/widgets/overflow_tooltip.dart` | **New** | Smart tooltip only shown on text overflow |

---

## Color System

### ColorPalette (`lib/core/models/color_config.dart`)

Each `ColorPalette` defines a complete brand color set for one brightness mode.

**7 required roles:**

| Role | Purpose |
|------|---------|
| `primary` | Brand primary — buttons, links, focus rings |
| `secondary` | Secondary brand — FAB, nav indicators |
| `background` | Main background |
| `foreground` | Main text/icon color |
| `muted` | Subdued backgrounds — cards, chips, app bar |
| `mutedForeground` | Subdued text — subtitles, hints |
| `border` | Borders and dividers |

**6 optional roles** (auto-computed when null):

| Role | Default behavior |
|------|-----------------|
| `tertiary` | Falls back to neutral grey `#7B7486` |
| `error` | Falls back to Material red `#BA1A1A` |
| `onPrimary` | Luminance-based contrast (black or white) |
| `onSecondary` | Luminance-based contrast |
| `onTertiary` | Luminance-based contrast |
| `onError` | Luminance-based contrast |

### ColorConfig

Wraps separate `light` and `dark` `ColorPalette` instances:

```dart
const ColorConfig(
  light: ColorPalette(
    primary: Color(0xFF1976D2),
    secondary: Color(0xFF03DAC6),
    background: Color(0xFFFAFAFA),
    foreground: Color(0xFF1A1A1E),
    muted: Color(0xFFE4E4E8),
    mutedForeground: Color(0xFF6E6E78),
    border: Color(0xFFC8C8CE),
  ),
  dark: ColorPalette.defaultDark(), // use defaults for dark mode
);
```

### Color Scheme Generation

`generateColorScheme()` in `lib/design/theme/theme.dart` maps palette roles to
a full Material 3 `ColorScheme` via direct color math — no `fromSeed()`. This
gives precise control over every color:

- **Surface container scale**: 5 levels derived via `Color.lerp(background, muted, t)` at non-linear steps (0.05, 0.15, 0.30, 0.55, 0.80)
- **Container colors**: Derived via `Color.lerp(role, background, 0.85)` and `Color.lerp(role, foreground, 0.7)`
- **Fixed roles**: Computed once for both light and dark
- **Outline variant**: `Color.lerp(border, background, 0.5)`
- **Inverse colors**: Foreground/background swap with primary tint

---

## Font System

### FontConfig (`lib/core/models/font_config.dart`)

Three font roles that map to the typographic hierarchy:

| Role | Usage | Default |
|------|-------|---------|
| `bodyFont` | UI text, paragraphs, labels, buttons | Material sans-serif |
| `displayFont` | Display text, AppBar titles, ListTile titles | Material sans-serif |
| `brandFont` | Reserved for special brand uses | Material sans-serif |

All fields are nullable. When `null`, no `fontFamily` is set, so Material
defaults apply.

### Bundled Fonts

The branch bundles three custom font families in `fonts/`:

| Family | Files | Role |
|--------|-------|------|
| Inter | Variable weight + italic | Body font |
| Hyprsalvo | Regular + Bold Condensed | Display font |
| Tactical | Regular | Brand font |

These are registered in `pubspec.yaml` under `flutter.fonts` and referenced via
`FontFamilies` constants in `lib/design/tokens/typography.dart`.

### Font Threading

`FontConfig` flows through the entire theme pipeline:

1. `SoliplexConfig.theme.fontConfig` -> `app.dart`
2. `app.dart` -> `soliplexLightTheme(fontConfig:)` / `soliplexDarkTheme(fontConfig:)`
3. `_buildTheme()` -> `buildSoliplexTextTheme(bodyFont:, displayFont:)`
4. `_buildTheme()` -> every component theme builder that accepts `fontConfig`

---

## Theme Building

### Before: Duplicated inline themes

`main` defines two near-identical 200+ line functions (`soliplexLightTheme`,
`soliplexDarkTheme`) with all component styling inline. Any change requires
editing both functions.

### After: Unified builder pipeline

```text
soliplexLightTheme(colorConfig, fontConfig)
  +-- generateColorScheme(Brightness.light, palette)
       +-- _buildTheme(colorScheme, fontConfig)
            +-- buildSoliplexTextTheme(bodyFont, displayFont)
            +-- buildAppBarTheme(colorScheme, fontConfig)
            +-- buildListTileTheme(colorScheme, fontConfig)
            +-- buildFilledButtonTheme(colorScheme, fontConfig)
            +-- ... (40+ component builders)
            +-- extensions: [SoliplexTheme, MarkdownThemeExtension]
```

- Single `_buildTheme()` function for both light and dark
- Each component theme in its own builder function
- Font config threaded to every text-bearing component
- ColorScheme fully populated (no missing fields)

---

## Component Themes

`lib/design/theme/component_themes.dart` (785 lines) extracts theme
configuration for every Material component into standalone builder functions:

**Buttons**: FilledButton, OutlinedButton, TextButton, IconButton,
ElevatedButton, ToggleButtons, SegmentedButton, FloatingActionButton

**Navigation**: NavigationBar, NavigationRail, NavigationDrawer, Drawer,
BottomNavigationBar, BottomAppBar

**Inputs**: InputDecoration, Checkbox, Radio, Slider, Switch, SearchBar,
SearchView, DropdownMenu

**Data display**: ListTile, Card, Chip, DataTable, ExpansionTile, Badge,
Tooltip, ProgressIndicator

**Dialogs & surfaces**: Dialog, SnackBar, BottomSheet, Banner, PopupMenu, Menu,
MenuBar, MenuButton

**Date/time**: DatePicker, TimePicker

**Layout**: AppBar, Divider, TabBar

Each builder:

- Takes a `ColorScheme` as its first argument
- Optionally takes `FontConfig?` for text-bearing components
- Uses `soliplexRadii` and `SoliplexSpacing` tokens for consistent sizing
- Is independently testable

---

## Dark Mode Support

### Theme persistence (`lib/core/providers/theme_provider.dart`)

- `ThemeModeNotifier` manages `ThemeMode` state (light, dark, system)
- Persists selection to `SharedPreferences` under key `theme_mode`
- `initializeTheme()` preloads the saved mode in `main()` before `runApp()` to avoid a flash of wrong theme
- `toggle()` resolves `ThemeMode.system` to actual brightness before toggling

### Reactive wiring (`lib/app.dart`)

```dart
final themeMode = ref.watch(themeModeProvider);
// ...
MaterialApp(
  theme: lightTheme,
  darkTheme: darkTheme,
  themeMode: themeMode,  // was: ThemeMode.light (hardcoded)
);
```

### ThemeToggleButton (`lib/shared/widgets/theme_toggle_button.dart`)

- Placed in every AppBar via `AppShell`
- Shows sun icon in dark mode, moon icon in light mode
- Accessible — has `Semantics` label and `Tooltip`
- Calls `themeModeProvider.notifier.toggle(systemBrightness)`

---

## AppBar and Navigation

### Brand logo in AppBar (`lib/shared/widgets/app_shell.dart`)

Two new `SoliplexConfig` flags control AppBar branding:

| Flag | Default | Effect |
|------|---------|--------|
| `showLogoInAppBar` | `false` | Renders the configured logo left-aligned |
| `showAppNameInAppBar` | `true` | Shows app name next to logo (only when logo is shown) |

The AppBar layout changed to a three-section Row:

1. **Left group** (intrinsic width): leading widget + brand logo + app name
2. **Center** (expanded): page title, flex-centered
3. **Actions** (right): theme toggle + custom actions + inspector button

### Back button navigation

A `_BackButton` widget was added to the router for settings sub-pages:

- Settings screen
- Telemetry screen
- Network inspector screen
- Log viewer screen
- Backend versions screen

This provides consistent back navigation without relying on `automaticallyImplyLeading`.

---

## Semantic Colors

`lib/design/color/color_scheme_extensions.dart` was expanded with a tonal
semantic color system:

### Semantic seeds

```dart
abstract final class SemanticSeeds {
  static const success = Color(0xFF2E7D32); // Green 800
  static const warning = Color(0xFFE65100); // Orange 900
  static const info    = Color(0xFF1565C0); // Blue 800
}
```

### Pre-computed palettes

Tonal palettes are generated once using `ColorScheme.fromSeed()` for each
semantic seed, for both light and dark modes. The `SymbolicColors` extension
provides:

- `successColor` / `onSuccessColor` / `successContainerColor` / `onSuccessContainerColor`
- `warningColor` / `onWarningColor` / `warningContainerColor` / `onWarningContainerColor`
- `infoColor` / `onInfoColor` / `infoContainerColor` / `onInfoContainerColor`

These use the Material 3 tonal system for automatic light/dark adaptation.

---

## Typography Overhaul

### Before (`main`)

`soliplexTextTheme()` defined only 5 text styles with hardcoded colors from
`SoliplexColors`:

- `bodyMedium`, `labelMedium`, `titleSmall`, `titleMedium`, `titleLarge`

### After (`custom-theme`)

`buildSoliplexTextTheme()` defines the complete Material 3 type scale (15 styles)
with font family support:

| Category | Styles | Font |
|----------|--------|------|
| Display | `displayLarge` (48), `displayMedium` (32), `displaySmall` (28) | `displayFont` |
| Headline | `headlineLarge` (28), `headlineMedium` (24), `headlineSmall` (20) | `bodyFont` |
| Title | `titleLarge` (24), `titleMedium` (18), `titleSmall` (14) | `bodyFont` |
| Body | `bodyLarge` (16), `bodyMedium` (13), `bodySmall` (10) | `bodyFont` |
| Label | `labelLarge` (16), `labelMedium` (13), `labelSmall` (10) | `bodyFont` |

Each style has explicit `fontSize`, `fontWeight`, `letterSpacing`, and `height`
values. Colors are applied via `textTheme.apply()` from the `ColorScheme` rather
than being hardcoded.

---

## UI Polish

### Chat panel (`lib/features/chat/`)

- Simplified widget nesting (removed redundant `Align` + `ConstrainedBox` wrapper)
- Chat input constrained to `maxContentWidth` for readability on wide screens
- Message list uses theme-derived colors instead of hardcoded values
- Feedback dialog uses `AlertDialog` + `ListView.builder` with `ListTile` for consistent theming
- Code highlighting restored for dark mode

### Rooms screens (`lib/features/rooms/`)

- Room grid cards and list tiles refactored to use `ColorScheme` colors
- Room info screen uses theme-consistent styling
- Scrollbar positioning fixed

### History panel (`lib/features/history/`)

- Thread list items use theme colors
- Panel layout refined

### Settings (`lib/features/settings/`)

- All settings sub-pages migrated to `AppShell` with `ShellConfig` for consistent AppBar
- Backend versions screen uses `AppShell` instead of standalone `Scaffold`

### Home screen (`lib/features/home/`)

- Title removed from AppBar (brand logo handles identification)

---

## New Shared Widgets

### ThemeToggleButton (`lib/shared/widgets/theme_toggle_button.dart`)

Accessible icon button that toggles light/dark mode. Resolves
`ThemeMode.system` before toggling. Integrated into `AppShell` so it appears
on every screen.

### OverflowTooltip (`lib/shared/widgets/overflow_tooltip.dart`)

Displays text with a tooltip that only appears when the text is truncated.
Uses `LayoutBuilder` + `TextPainter` to measure overflow. Useful for room
names, thread titles, and other variable-length text.

---

## Test Coverage

The branch adds comprehensive test coverage for all new models and providers:

| Test file | Coverage |
|-----------|----------|
| `test/core/models/color_config_test.dart` | 369 lines — `ColorPalette`, `ColorConfig`, defaults, equality, copyWith |
| `test/core/models/font_config_test.dart` | 140 lines — `FontConfig` defaults, equality, copyWith, clear flags |
| `test/core/models/theme_config_test.dart` | Modified — updated for new `ColorConfig`/`FontConfig` fields |
| `test/core/providers/theme_provider_test.dart` | 130 lines — persistence, toggle, system mode |
| `test/design/theme/theme_test.dart` | 596+ lines — `generateColorScheme()`, component themes, font threading |
| `test/shared/widgets/app_shell_test.dart` | 134 lines — logo rendering, theme toggle, layout |
| `test/soliplex_frontend_contract_test.dart` | Expanded — updated API contract tests |

---

## Benefits

### 1. White-label readiness

Consumers can fully customize the app's visual identity by providing a
`ColorConfig` and `FontConfig` — no need to fork or override internal classes.
The 7-role color palette is simple to configure while producing a complete
Material 3 theme.

### 2. Dark mode support

Users get light/dark/system theme support out of the box, with persistent
preferences. The hardcoded `ThemeMode.light` is replaced with a reactive
provider.

### 3. Elimination of code duplication

The old codebase had two near-identical 200+ line theme functions. The new
architecture has a single `_buildTheme()` pipeline with extracted component
builders. Adding or modifying a component theme is a one-place change.

### 4. Complete Material 3 coverage

The `ColorScheme` on `main` only populates 8 of 40+ fields. The new
`generateColorScheme()` populates every field, preventing unexpected fallback
colors in Material widgets.

### 5. Full type scale

The text theme goes from 5 partially-defined styles to the complete 15-style
Material 3 type scale, with proper font threading for brand customization.

### 6. Consistent component styling

40+ component themes ensure every Material widget respects the brand's radii,
spacing, and font choices — not just the handful that were styled on `main`.

### 7. Better accessibility

- Theme toggle has semantic labels and tooltips
- Contrast colors are auto-computed from luminance
- Semantic status colors use Material 3 tonal palettes for proper
  light/dark contrast

### 8. Improved architecture

- `SoliplexColors` (a custom class tightly coupled to the theme) is replaced
  with standard `ColorScheme`, reducing custom API surface
- `SoliplexTheme` extension now wraps `ColorScheme` instead of `SoliplexColors`
- Feature screens reference `ColorScheme` via `Theme.of(context)` instead of
  custom extension methods
