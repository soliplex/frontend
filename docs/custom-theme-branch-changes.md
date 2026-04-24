# Custom Theme Branch — Scope and Changes

This document covers everything the `custom-theme` branch adds to `frontend`
relative to `main`: the scope of the white-label theming system, the
architecture, and a file-by-file inventory of what changed.

For step-by-step instructions on standing up the same theming system in a new
repo, see [`custom-theme-branch-implementation.md`](custom-theme-branch-implementation.md).

---

## Table of Contents

1. [Overview](#overview)
2. [State on `main` (before this branch)](#state-on-main-before-this-branch)
3. [Theming Architecture](#theming-architecture)
4. [Color System](#color-system)
5. [Font System](#font-system)
6. [Theme Building Pipeline](#theme-building-pipeline)
7. [Component Themes](#component-themes)
8. [Theme Extensions](#theme-extensions)
9. [Semantic Colors](#semantic-colors)
10. [Layout Tokens](#layout-tokens)
11. [Typography](#typography)
12. [Theme Mode Persistence and Toggle](#theme-mode-persistence-and-toggle)
13. [Shell Integration](#shell-integration)
14. [Flavor Wiring (`standard()`)](#flavor-wiring-standard)
15. [Public API Surface](#public-api-surface)
16. [File Inventory](#file-inventory)
17. [Test Coverage](#test-coverage)
18. [Platform Workarounds](#platform-workarounds)
19. [Things Intentionally Out of Scope](#things-intentionally-out-of-scope)

---

## Overview

The branch adds a complete white-label theming system on top of the existing
modular shell architecture. Consumers customize visual identity by passing a
`ThemeConfig` (colors + fonts) into the `standard()` flavor factory. The shell
generates light and dark `ThemeData` from that config and reactively switches
between them based on a persisted `ThemeMode` provider.

Key capabilities introduced:

- **`ColorConfig`** — 7 required + 6 optional color roles per brightness mode,
  expanded into a complete Material 3 `ColorScheme` via direct color math
  (`Color.lerp`), no `ColorScheme.fromSeed()`.
- **`FontConfig`** — four font roles (`bodyFont`, `displayFont`, `brandFont`,
  `codeFont`); bundled fonts resolve from local assets, non-bundled names
  resolve via the `google_fonts` package at runtime.
- **`ThemeConfig`** — composes `ColorConfig?` and `FontConfig?` and is the
  single argument consumers pass to `standard()`.
- **40+ component theme builders** in `component_themes.dart`, threaded with
  the active `ColorScheme` and optional `FontConfig`.
- **`SemanticColors` extension** on `ColorScheme` for `success` / `warning` /
  `info` (each with `on*` and `*Container` / `on*Container` pairs), generated
  via Material 3 tonal palettes.
- **`SoliplexTheme` `ThemeExtension`** carrying `ColorScheme`, radii, badge
  theme, and a configurable code font with platform-adaptive monospace
  fallback.
- **`themeModeProvider`** — Riverpod `NotifierProvider` persisted to
  `SharedPreferences`, with an `initializeTheme()` preloader called from
  `main.dart` before `runApp` to avoid a flash of wrong theme.
- **`ThemeToggleButton`** — `ConsumerWidget` icon button that toggles
  light/dark and resolves `ThemeMode.system` to actual brightness first.
- **Shell wiring** — `ShellConfig` gained `darkTheme` and `themeMode` fields;
  `SoliplexShell` extracts an internal `_ThemedApp ConsumerWidget` (so it can
  watch `themeModeProvider` from inside the `ProviderScope`).
- **Square-first surfaces** — the branch replaces rounded corners with
  minimal or zero radii across themed components. `soliplexRadii` defaults
  to `SoliplexRadii(sm: 2, md: 8, lg: 12, xl: 20)` and markdown code blocks,
  dialogs, sidebars, and buttons use `BorderRadius.zero` where previously
  rounded.

---

## State on `main` (before this branch)

For context on what was rebuilt, here is what existed before:

- `ShellConfig` accepted a single `ThemeData theme` — no `darkTheme`, no
  `themeMode`.
- `_defaultTheme()` in `lib/src/flavors/standard.dart` returned a bare
  `ThemeData()` with only a `MarkdownThemeExtension` added.
- `MaterialApp.router` only set `theme:` — no `darkTheme:` or `themeMode:`.
- No design tokens, no custom fonts (the font files in `fonts/` existed but
  were not registered).
- No theme persistence or toggle.
- The legacy `lib/src/design/tokens/colors.dart` defined a flat
  `SoliplexColors` class with hardcoded light/dark palettes. It is **still
  present on this branch** but no longer referenced by any production code —
  only by its own test (`test/design/tokens/colors_test.dart`). It is
  effectively dead code retained for now and slated for removal.
- `MarkdownThemeExtension` already existed at
  `lib/src/modules/room/ui/markdown/markdown_theme_extension.dart` and is
  reused unchanged by the new theme builder.

---

## Theming Architecture

```text
ThemeConfig
  +-- colorConfig: ColorConfig?
  |     +-- light: ColorPalette (7 required + 6 optional roles)
  |     +-- dark:  ColorPalette (7 required + 6 optional roles)
  +-- fontConfig: FontConfig?
        +-- bodyFont:    String?
        +-- displayFont: String?
        +-- brandFont:   String?
        +-- codeFont:    String?

ColorPalette -> generateColorScheme() -> full Material 3 ColorScheme
ColorScheme + FontConfig -> _buildTheme() -> 40+ component theme builders
                                         -> ThemeData (extensions: SoliplexTheme,
                                            MarkdownThemeExtension)

ThemeMode reactive via themeModeProvider (persisted to SharedPreferences,
preloaded by initializeTheme() before runApp)
```

---

## Color System

### `ColorPalette` (`lib/src/core/models/color_config.dart`)

Each `ColorPalette` is a complete brand color set for one brightness mode.

**7 required roles:**

| Role | Purpose |
| ---- | ------- |
| `primary` | Brand primary — buttons, links, focus rings |
| `secondary` | Secondary brand — FAB, nav indicators |
| `background` | Main background |
| `foreground` | Main text/icon color |
| `muted` | Subdued backgrounds — cards, chips, app bar |
| `mutedForeground` | Subdued text — subtitles, hints |
| `border` | Borders and dividers |

**6 optional roles** with `effective*` getter fallbacks:

| Role | Default behavior |
| ---- | ---------------- |
| `tertiary` | Falls back to neutral grey `#7B7486` |
| `error` | Falls back to Material red `#BA1A1A` |
| `onPrimary` | Luminance-based contrast (black or white) |
| `onSecondary` | Luminance-based contrast |
| `onTertiary` | Luminance-based contrast |
| `onError` | Luminance-based contrast |

`ColorPalette` ships with `defaultLight()` and `defaultDark()` constructors
that supply a complete desaturated grey-purple neutral palette so that
`const ThemeConfig()` produces a usable theme out of the box.

### `ColorConfig`

Wraps a `light` and `dark` `ColorPalette`. Both default to the respective
`ColorPalette.defaultLight()` / `defaultDark()` constructors, so
`const ColorConfig()` is valid.

```dart
const config = ColorConfig(
  light: ColorPalette(
    primary: Color(0xFF1976D2),
    secondary: Color(0xFF03DAC6),
    background: Color(0xFFFAFAFA),
    foreground: Color(0xFF1A1A1E),
    muted: Color(0xFFE4E4E8),
    mutedForeground: Color(0xFF6E6E78),
    border: Color(0xFFC8C8CE),
  ),
  // dark: defaults to ColorPalette.defaultDark()
);
```

### `generateColorScheme()` (`lib/src/design/theme/theme.dart`)

Maps a `ColorPalette` to a fully-populated Material 3 `ColorScheme` via direct
color math — no `fromSeed()`. This gives precise control over every field:

- **Surface container scale**: 5 levels via `Color.lerp(background, muted, t)`
  at non-linear steps `(0.05, 0.15, 0.30, 0.55, 0.80)`.
- **Container colors**: `Color.lerp(role, background, 0.85)` and
  `Color.lerp(role, foreground, 0.7)` for `*Container` / `on*Container`.
- **Surface variants**: `surfaceDim` / `surfaceBright` lerped from background.
- **Fixed roles**: `*Fixed`, `*FixedDim`, `on*Fixed`, `on*FixedVariant`
  computed once for both light and dark.
- **Outline variant**: `Color.lerp(border, background, 0.5)`.
- **Inverse colors**: foreground/background swap with primary tint.

Every `ColorScheme` field is populated; no Material widget falls back to a
default tint.

---

## Font System

### `FontConfig` (`lib/src/core/models/font_config.dart`)

| Role | Used by | Default behavior when null |
| ---- | ------- | -------------------------- |
| `bodyFont` | Body, label, title, headline text styles | Material default sans |
| `displayFont` | Display text styles, AppBar titles | Material default sans |
| `brandFont` | Reserved for brand-specific use sites | Material default sans |
| `codeFont` | Code blocks, inline code, monospaced text via `SoliplexTheme.codeStyle` / `mergeCode` | Platform-adaptive: SF Mono on Apple, Roboto Mono elsewhere, with `['monospace']` fallback |

`FontConfig` is fully `const`-constructible and supports `copyWith` with
`clear*` flags.

### Font resolution strategy (`_buildTheme` in `theme.dart`)

The branch uses a **hybrid strategy**:

1. `buildSoliplexTextTheme(bodyFont:, displayFont:)` builds a complete 15-style
   `TextTheme` with the requested family names.
2. `GoogleFonts.getTextTheme(bodyFont, textTheme)` then wraps the text theme
   so any non-bundled font name is fetched and cached at runtime by
   `google_fonts`.
3. Bundled fonts (those registered in `pubspec.yaml` under `flutter.fonts`)
   take precedence when their family name matches a registered asset.

### Default `FontFamilies` (`lib/src/design/tokens/typography.dart`)

| Constant | Value | Source |
| -------- | ----- | ------ |
| `FontFamilies.body` | `Inter` | Bundled (`fonts/Inter-VariableFont_opsz,wght.ttf` + italic) |
| `FontFamilies.display` | `Oswald` | `google_fonts` |
| `FontFamilies.brand` | `SquadaOne` | `google_fonts` |
| `FontFamilies.codeApple` | `SF Mono` | Platform default |
| `FontFamilies.codeDefault` | `Roboto Mono` | Platform default |

The `standard()` flavor passes a `_defaultFontConfig` of
`FontConfig(bodyFont: Inter, displayFont: Oswald, brandFont: SquadaOne)` when
the consumer does not supply a custom `fontConfig`.

### Code font

`SoliplexTheme` (the `ThemeExtension`) holds an optional `codeFont` string and
exposes three helpers used by code/markdown rendering:

- `SoliplexTheme.resolveCodeFontFamily(context)` — returns the configured
  font, or the platform-adaptive default.
- `SoliplexTheme.codeStyle(context)` — convenience `TextStyle` with
  `fontFamilyFallback: ['monospace']`.
- `SoliplexTheme.mergeCode(context, baseStyle)` — copies the code font onto
  an existing `TextStyle`.

---

## Theme Building Pipeline

```text
soliplexLightTheme(colorConfig, fontConfig)
  +-- generateColorScheme(brightness: light, palette: colors.light)
       +-- _buildTheme(colorScheme, fontConfig:)
            +-- buildSoliplexTextTheme(bodyFont, displayFont)
            +-- GoogleFonts.getTextTheme(bodyFont, textTheme)
            +-- buildAppBarTheme(colorScheme, fontConfig)
            +-- buildListTileTheme(colorScheme, fontConfig)
            +-- buildFilledButtonTheme(colorScheme, fontConfig)
            +-- ... 40+ component builders
            +-- extensions: [
                  SoliplexTheme(colors, radii, badgeTheme, codeFont),
                  MarkdownThemeExtension(...),
                ]
```

`soliplexDarkTheme()` is the same pipeline with `Brightness.dark` and
`colors.dark`. Both delegate to a single private `_buildTheme()` so adding or
modifying a component theme is a one-place change.

---

## Component Themes

`lib/src/design/theme/component_themes.dart` contains a builder
function for nearly every Material component. Each builder takes a
`ColorScheme` first and optionally a `FontConfig?` for text-bearing
components, and reads sizing from `soliplexRadii` and `SoliplexSpacing`
tokens.

Coverage groups:

- **Buttons**: FilledButton, OutlinedButton, TextButton, IconButton,
  ElevatedButton, ToggleButtons, SegmentedButton, FloatingActionButton
- **Navigation**: NavigationBar, NavigationRail, NavigationDrawer, Drawer,
  BottomNavigationBar, BottomAppBar
- **Inputs**: InputDecoration, Checkbox, Radio, Slider, Switch, SearchBar,
  SearchView, DropdownMenu
- **Data display**: ListTile, Card, Chip, DataTable, ExpansionTile, Badge,
  Tooltip, ProgressIndicator
- **Dialogs and surfaces**: Dialog, SnackBar, BottomSheet, Banner, PopupMenu,
  Menu, MenuBar, MenuButton
- **Date / time**: DatePicker, TimePicker
- **Layout**: AppBar, Divider, TabBar

---

## Theme Extensions

### `SoliplexTheme` (`lib/src/design/theme/theme_extensions.dart`)

A `ThemeExtension<SoliplexTheme>` registered in every generated `ThemeData`.
Carries:

- `colors: ColorScheme` — the active scheme (convenience accessor)
- `radii: SoliplexRadii` — radius tokens
- `badgeTheme: SoliplexBadgeThemeData` — custom badge config
- `codeFont: String?` — configured code font, or `null` for platform default

Static helpers:

- `SoliplexTheme.of(context)` — extract the extension
- `resolveCodeFontFamily(context)` — code font with platform fallback
- `codeStyle(context)` / `mergeCode(context, base)` — code-style helpers
- `appBarTitleStyle(context)` — responsive AppBar title style: uses
  `headlineSmall` below the tablet breakpoint, `headlineMedium` above

### `MarkdownThemeExtension`

Built inline by `_markdownThemeExtension(colorScheme, textTheme)` in
`theme.dart`. Reuses the existing class at
`lib/src/modules/room/ui/markdown/markdown_theme_extension.dart`. Populates
`h1`–`h3`, `body`, `code`, `link`, code-block decoration, and blockquote
decoration from the active `ColorScheme` and text theme.

---

## Semantic Colors

`lib/src/design/color/color_scheme_extensions.dart` adds a `SemanticColors`
extension on `ColorScheme` for status colors not in the standard scheme.

### Seeds

```dart
abstract final class SemanticSeeds {
  static const success = Color(0xFF2E7D32); // Green 800
  static const warning = Color(0xFFE65100); // Orange 900
  static const info    = Color(0xFF1565C0); // Blue 800
}
```

### Pre-computed palettes

A private `_SemanticPalettes` class generates light/dark `ColorScheme`s once
per seed via `ColorScheme.fromSeed()`, then `SemanticColors` exposes:

- `success` / `onSuccess` / `successContainer` / `onSuccessContainer`
- `warning` / `onWarning` / `warningContainer` / `onWarningContainer`
- `info` / `onInfo` / `infoContainer` / `onInfoContainer`

Each getter dispatches on the active `ColorScheme.brightness`, so light/dark
adaptation is automatic.

---

## Layout Tokens

Three layout-level token sets under `lib/src/design/tokens/` are used across
component themes and module UIs in place of hardcoded literals.

### Spacing (`spacing.dart`)

`SoliplexSpacing` exposes a 4-pixel-based scale. Every `EdgeInsets` /
`SizedBox` in the branch's themed surfaces and migrated module widgets
references one of these constants.

| Token | Value |
| ----- | ----- |
| `s1` | 4 |
| `s2` | 8 |
| `s3` | 12 |
| `s4` | 16 |
| `s5` | 20 |
| `s6` | 24 |
| `s7` | 28 |
| `s8` | 32 |
| `s9` | 48 |

### Radii (`radii.dart`)

`SoliplexRadii` is a `const` class with a static `lerp(a, b, t)` so it can
participate in `ThemeExtension.lerp`. The top-level `soliplexRadii` default
is tuned for the square-first aesthetic:

| Field | Value |
| ----- | ----- |
| `sm` | 2 |
| `md` | 8 |
| `lg` | 12 |
| `xl` | 20 |

### Breakpoints (`breakpoints.dart`)

`SoliplexBreakpoints` defines width thresholds used by responsive helpers
such as `SoliplexTheme.appBarTitleStyle`:

| Field | Pixels |
| ----- | ------ |
| `mobile` | 320 |
| `tablet` | 600 |
| `desktop` | 840 |

---

## Typography

`buildSoliplexTextTheme({bodyFont, displayFont})` defines the complete 15-style
Material 3 type scale with explicit `fontSize`, `fontWeight`, `letterSpacing`,
and `height`:

| Category | Styles | Font role |
| -------- | ------ | --------- |
| Display | `displayLarge` (48), `displayMedium` (32), `displaySmall` (28) | `displayFont` |
| Headline | `headlineLarge` (32), `headlineMedium` (28), `headlineSmall` (24) | `bodyFont` |
| Title | `titleLarge` (24), `titleMedium` (18), `titleSmall` (14) | `bodyFont` |
| Body | `bodyLarge` (18), `bodyMedium` (16), `bodySmall` (13) | `bodyFont` |
| Label | `labelLarge` (18), `labelMedium` (15), `labelSmall` (13) | `bodyFont` |

Colors are applied via `textTheme.apply(bodyColor:, displayColor:)` from the
generated `ColorScheme` rather than being hardcoded.

A separate `lib/src/design/tokens/typography_x.dart` exposes
`appMonospaceTextStyle(BuildContext)` — a `bodyMedium`-based monospace
`TextStyle` that adapts to the platform (`SF Mono` + `Menlo` fallback on
iOS/macOS, `Roboto Mono` + `monospace` fallback elsewhere) — plus a
`TypographyX on BuildContext` extension exposing `context.monospace`. Both
are currently unreferenced by production code on this branch; they exist as
a direct-monospace path for future use sites that do not route through
`SoliplexTheme.codeStyle`.

---

## Theme Mode Persistence and Toggle

### `theme_provider.dart` (`lib/src/core/providers/theme_provider.dart`)

- Top-level `_preloadedThemeMode` cache.
- `initializeTheme()` — loads the saved value from `SharedPreferences` under
  the key `theme_mode` and populates the cache. **Must be called from `main()`
  before `runApp`** to avoid a first-frame flash of the wrong theme.
- `ThemeModeNotifier extends Notifier<ThemeMode>` — its `build()` returns
  `_preloadedThemeMode ?? ThemeMode.system`. Exposes `toggle(systemBrightness)`
  which resolves `ThemeMode.system` to actual brightness before flipping, and
  persists every change.
- `themeModeProvider` — Riverpod `NotifierProvider<ThemeModeNotifier, ThemeMode>`.
- `resetPreloadedThemeMode()` — `@visibleForTesting` helper for test isolation.

### `ThemeToggleButton` (`lib/src/shared/theme_toggle_button.dart`)

A `ConsumerWidget` icon button that:

- Watches `themeModeProvider`
- Computes effective brightness from `ThemeMode.system` if needed via
  `MediaQuery.platformBrightnessOf(context)`
- Renders `Icons.light_mode` or `Icons.dark_mode` accordingly
- Wraps the button in `Semantics` and uses a `Tooltip` for accessibility
- Calls `ref.read(themeModeProvider.notifier).toggle(systemBrightness)`

The frontend repo's `lib/src/shared/` directory is flat (no `widgets/`
subdirectory), so this widget sits next to the existing `copy_button.dart` and
`file_type_icons.dart`.

---

## Shell Integration

### `ShellConfig` changes (`lib/src/core/shell_config.dart`)

Two new fields:

```dart
final ThemeData? darkTheme;
final ThemeMode themeMode;        // defaults to ThemeMode.system
```

The existing `theme` field remains and now represents the light theme.

### `SoliplexShell` — `_ThemedApp` extraction (`lib/src/core/shell.dart`)

`SoliplexShell` creates the root `ProviderScope` inside its `build` method, so
the shell itself sits **outside** any `ProviderScope` and cannot use
`ref.watch()`. The fix is a private `_ThemedApp extends ConsumerWidget` that
lives inside the scope:

```dart
class _SoliplexShellState extends State<SoliplexShell> {
  Widget build(context) => ProviderScope(
        overrides: widget.config.overrides,
        child: _ThemedApp(config: widget.config, router: _router),
      );
}

class _ThemedApp extends ConsumerWidget {
  Widget build(context, ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: config.appName,
      theme: config.theme,
      darkTheme: config.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
```

This is the minimum change needed to make the shell reactive to theme changes
without restructuring the rest of the boot path.

---

## Flavor Wiring (`standard()`)

`lib/src/flavors/standard.dart` accepts a new optional `themeConfig`
parameter and generates both light and dark themes inside the flavor:

```dart
Future<ShellConfig> standard({
  String appName = 'Soliplex',
  ThemeConfig? themeConfig,
  // ... other params
}) async {
  // ...
  return ShellConfig(
    appName: appName,
    logo: logo,
    theme: soliplexLightTheme(
      colorConfig: themeConfig?.colorConfig,
      fontConfig: themeConfig?.fontConfig ?? _defaultFontConfig,
    ),
    darkTheme: soliplexDarkTheme(
      colorConfig: themeConfig?.colorConfig,
      fontConfig: themeConfig?.fontConfig ?? _defaultFontConfig,
    ),
    // ...
  );
}
```

`_defaultFontConfig` is the `Inter` / `Oswald` / `SquadaOne` font set
described above.

### `lib/main.dart`

The entry point preloads the saved theme mode before `runApp`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeTheme();
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  runSoliplexShell(await standard(
    callbackParams: callbackParams,
    themeConfig: const ThemeConfig(),
  ));
}
```

---

## Public API Surface

`lib/soliplex_frontend.dart` re-exports the new public types:

```dart
export 'src/core/models/color_config.dart' show ColorPalette, ColorConfig;
export 'src/core/models/font_config.dart' show FontConfig;
export 'src/core/models/theme_config.dart' show ThemeConfig;
export 'src/core/providers/theme_provider.dart'
    show themeModeProvider, initializeTheme;
export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ModuleContribution, ShellConfig;
export 'src/design/design.dart';
```

`lib/src/design/design.dart` is the design system barrel, exporting
`theme.dart`, `theme_extensions.dart`, `tokens/breakpoints.dart`,
`tokens/radii.dart`, `tokens/spacing.dart`, `tokens/typography.dart`, and
`tokens/typography_x.dart`. (`color_scheme_extensions.dart` is imported
directly where needed.)

---

## File Inventory

### New files (15)

```text
lib/src/core/models/color_config.dart
lib/src/core/models/font_config.dart
lib/src/core/models/theme_config.dart
lib/src/core/providers/theme_provider.dart
lib/src/design/design.dart
lib/src/design/color/color_scheme_extensions.dart
lib/src/design/theme/component_themes.dart
lib/src/design/theme/theme.dart
lib/src/design/theme/theme_extensions.dart
lib/src/design/tokens/breakpoints.dart
lib/src/design/tokens/radii.dart
lib/src/design/tokens/spacing.dart
lib/src/design/tokens/typography.dart
lib/src/design/tokens/typography_x.dart
lib/src/shared/theme_toggle_button.dart
```

### Modified files (theme-system specific)

```text
pubspec.yaml                    — google_fonts + meta deps, Inter font registration
lib/main.dart                   — initializeTheme() call
lib/soliplex_frontend.dart      — barrel exports for theme types
lib/src/core/shell_config.dart  — darkTheme and themeMode fields
lib/src/core/shell.dart         — _ThemedApp ConsumerWidget extraction
lib/src/flavors/standard.dart   — themeConfig param, dual theme generation
```

Many additional `lib/src/modules/...` files were touched in style-only commits
(see `git log main..HEAD --oneline -- lib/src/modules`) to migrate hardcoded
colors to `ColorScheme` references and apply spacing tokens; those are
follow-on cleanup, not part of the core theme architecture.

---

## Test Coverage

| Test file | Coverage |
| --------- | -------- |
| `test/core/models/color_config_test.dart` | `ColorPalette` and `ColorConfig` defaults, `effective*` getters, equality, `copyWith` (including `clear*` flags) |
| `test/core/models/font_config_test.dart` | `FontConfig` defaults, equality, `copyWith`, `clear*` flags |
| `test/core/providers/theme_provider_test.dart` | `initializeTheme()`, `ThemeModeNotifier` toggle, `ThemeMode.system` resolution, persistence |
| `test/design/theme/theme_test.dart` | `generateColorScheme()` mapping, light/dark `_buildTheme` smoke tests |
| `test/shared/theme_toggle_button_test.dart` | Icon selection, semantics labels, tap-to-toggle, system-mode resolution |

Existing module and screen tests were updated as part of the migration to the
new theme types where they previously asserted on hardcoded colors.

---

## Platform Workarounds

### macOS merged platform/UI thread

`macos/Runner/Info.plist` sets `FLTEnableMergedPlatformUIThread` to `false`.
Without this flag, button taps on macOS can intermittently fail to register
against widgets that rebuild through Riverpod `ref.watch` — including the
reactive theme toggle introduced by this branch. Setting it to `false` opts
out of Flutter's merged platform/UI thread optimization on macOS and
restores reliable tap handling. This is a runtime behavioural fix, not a
theming change, but it lives on this branch because the theme toggle was
the first widget that surfaced the issue.

---

## Things Intentionally Out of Scope

The branch does not bring over a few items from the upstream design that the
theming architecture was inspired by, because they did not fit the
`frontend` repo's structure or were unnecessary:

- **`SoliplexConfig` flags** like `showLogoInAppBar` /
  `showAppNameInAppBar`. The `frontend` repo uses `ShellConfig` with a single
  `logo: Widget?` field; AppBar layout policies are handled at the screen
  level rather than via global flags.
- **`overflow_tooltip.dart`** — utility widget not part of the theming system
  itself.
- **A custom `app_shell.dart` AppBar restructure** with logo + theme toggle in
  the title row. The toggle is currently added per-screen via the existing
  module screens.
- **Router-level back-button helper** for settings sub-pages — those screens
  do not exist in this repo.
- **Feature-screen migration** of the kind needed in repos that previously
  used a custom `SoliplexColors` class. The frontend repo's screens already
  reference `Theme.of(context).colorScheme` directly, so no large-scale
  migration was needed; the legacy `SoliplexColors` in
  `lib/src/design/tokens/colors.dart` is now unused dead code.
- **Extra bundled font assets** — `fonts/HYPRSALVO.otf`,
  `fonts/HYPRSALVO-BoldCondensed.otf`, `fonts/OPERATORZ.otf`, and
  `fonts/TACTICAL.otf` live in the repo but are not registered under
  `flutter.fonts` in `pubspec.yaml` and are not referenced by `FontFamilies`.
  They are retained as raw assets for future brand variants; the default
  theme does not load them.
