# Custom Theme Branch

## Manual Implementation Guide

Follow these steps, in order, to manually apply the `custom-theme` branch changes.

### Step 1: Add dependencies and fonts

**pubspec.yaml** — add the `google_fonts` dependency:

```yaml
dependencies:
  google_fonts: ^6.2.1
```

Add font files to a `fonts/` directory at the project root, then register them:

```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: fonts/Inter-VariableFont_opsz,wght.ttf
        - asset: fonts/Inter-Italic-VariableFont_opsz,wght.ttf
          style: italic
    - family: Hyprsalvo
      fonts:
        - asset: fonts/HYPRSALVO.otf
        - asset: fonts/HYPRSALVO-BoldCondensed.otf
          weight: 700
    - family: Tactical
      fonts:
        - asset: fonts/TACTICAL.otf
```

Run `flutter pub get`.

### Step 2: Create the color model

Create `lib/core/models/color_config.dart` with:

- `ColorPalette` — immutable class with 7 required color roles + 6 optional
- `ColorPalette.defaultLight()` and `ColorPalette.defaultDark()` constructors
- `effective*` getters that auto-compute `on*` colors via luminance contrast
- `ColorConfig` — wraps `light` and `dark` `ColorPalette` instances
- `_contrastColor()` helper

### Step 3: Create the font model

Create `lib/core/models/font_config.dart` with:

- `FontConfig` — immutable class with 3 nullable `String?` fields
- `copyWith()` with `clear*` flags for resetting to null

### Step 4: Update ThemeConfig

Modify `lib/core/models/theme_config.dart`:

- Replace `SoliplexColors lightColors` / `darkColors` with `ColorConfig? colorConfig` / `FontConfig? fontConfig`
- Update `copyWith()`, `==`, `hashCode`, `toString()`

### Step 5: Update SoliplexConfig

Add two fields to `lib/core/models/soliplex_config.dart`:

```dart
final bool showLogoInAppBar;    // default: false
final bool showAppNameInAppBar; // default: true
```

Update `copyWith()`, `==`, `hashCode`, `toString()`.

### Step 6: Rewrite typography tokens

Replace `lib/design/tokens/typography.dart`:

- Remove `soliplexTextTheme(SoliplexColors)` function
- Add `FontFamilies` abstract class with `body`, `display`, `brand` constants
- Add `buildSoliplexTextTheme({String? bodyFont, String? displayFont})` that
  returns a complete 15-style `TextTheme`

### Step 7: Delete old color tokens

Delete `lib/design/tokens/colors.dart` (`SoliplexColors` class and
`lightSoliplexColors` / `darkSoliplexColors` constants).

Update `lib/design/design.dart` to remove the export.

### Step 8: Rewrite the theme builder

Replace `lib/design/theme/theme.dart`:

1. Add `generateColorScheme({Brightness, ColorPalette})` that maps palette
   roles to a complete `ColorScheme` via `Color.lerp()` math
2. Rewrite `soliplexLightTheme()` and `soliplexDarkTheme()` to accept
   `ColorConfig?` and `FontConfig?`, call `generateColorScheme()`, then
   delegate to `_buildTheme()`
3. Add `_buildTheme(ColorScheme, {FontConfig?})` that assembles `ThemeData`
   from component builders

### Step 9: Create component themes

Create `lib/design/theme/component_themes.dart` with builder functions for
each Material component. Each builder takes `ColorScheme` and optionally
`FontConfig?`. Use `soliplexRadii` and `SoliplexSpacing` for sizing.

### Step 10: Update theme extensions

Modify `lib/design/theme/theme_extensions.dart`:

- Change `SoliplexTheme.colors` from `SoliplexColors` to `ColorScheme`
- Update `copyWith()` signature

### Step 11: Expand color scheme extensions

Update `lib/design/color/color_scheme_extensions.dart`:

- Add `SemanticSeeds` with success/warning/info base colors
- Pre-compute tonal palettes via `ColorScheme.fromSeed()`
- Extend `SymbolicColors` with semantic color getters

### Step 12: Create theme provider

Create `lib/core/providers/theme_provider.dart`:

- `initializeTheme()` — loads saved theme mode from SharedPreferences
- `ThemeModeNotifier` — manages state, persists changes
- `themeModeProvider` — Riverpod `NotifierProvider`

### Step 13: Create shared widgets

Create `lib/shared/widgets/theme_toggle_button.dart`:

- `ConsumerWidget` that watches `themeModeProvider`
- Icon toggles between `Icons.light_mode` and `Icons.dark_mode`

Create `lib/shared/widgets/overflow_tooltip.dart`:

- Uses `LayoutBuilder` + `TextPainter` to detect text overflow
- Wraps text in `Tooltip` only when truncated

### Step 14: Wire into the app

**`lib/main.dart`**:

- Call `initializeTheme()` before `runSoliplexApp()`
- Configure `SoliplexConfig` with `showLogoInAppBar: true` and `FontConfig`

**`lib/app.dart`**:

- Watch `themeModeProvider`
- Pass `colorConfig` and `fontConfig` to theme builders
- Set `themeMode` to the provider value

**`lib/soliplex_frontend.dart`**:

- Export `ColorConfig`, `FontConfig` from the library barrel
- Remove `SoliplexColors` exports

### Step 15: Update AppShell

Modify `lib/shared/widgets/app_shell.dart`:

- Add brand logo rendering controlled by `showLogoInAppBar`
- Restructure AppBar title as a three-section Row
- Insert `ThemeToggleButton` into actions
- Set `automaticallyImplyLeading: false`

### Step 16: Update router

Modify `lib/core/router/app_router.dart`:

- Add `_BackButton` widget
- Add `leading` parameter to `_staticShell()` and `_staticPage()`
- Apply `_BackButton` to settings, telemetry, and other sub-pages
- Remove app name from home screen title

### Step 17: Update feature screens

Migrate feature screens from `SoliplexColors` references to `ColorScheme`:

- Replace `SoliplexTheme.of(context).colors.someColor` with
  `Theme.of(context).colorScheme.someRole`
- Use `colorScheme.surfaceContainerHigh` instead of `colors.inputBackground`
- Use `colorScheme.outline` instead of `colors.border`
- Use `colorScheme.onSurfaceVariant` instead of `colors.mutedForeground`

Key screens to update:

- `chat_panel.dart`, `chat_input.dart`, `message_list.dart`
- `history_panel.dart`, `thread_list_item.dart`
- `rooms_screen.dart`, `room_grid_card.dart`, `room_list_tile.dart`
- `room_screen.dart`, `room_info_screen.dart`
- `settings_screen.dart`, `backend_versions_screen.dart`
- `home_screen.dart`
- `log_viewer_screen.dart`, `log_level_badge.dart`
- `network_inspector_screen.dart`

### Step 18: Update tests

- Update `theme_config_test.dart` for new fields
- Add `color_config_test.dart` and `font_config_test.dart`
- Add `theme_provider_test.dart`
- Expand `theme_test.dart` to cover `generateColorScheme()` and component builders
- Add `app_shell_test.dart` for logo/toggle rendering
- Update `soliplex_frontend_contract_test.dart` for new exports

### Step 19: Run quality checks

```bash
dart format .
flutter analyze --fatal-infos
flutter test
```

All three must pass with zero issues.
