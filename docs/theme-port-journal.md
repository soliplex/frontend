# Theme System Port Journal

## Overview

This document captures the differences between the `flutter` repo (v0.66.1) and the
`frontend` repo (v0.81.0), with a focus on how the white-label theme system
(originally built in `flutter` commit `e017a3f`) was adapted for the `frontend`
architecture.

---

## Repo Architecture Delta

| Aspect | `flutter` | `frontend` |
|---|---|---|
| Lib structure | `lib/` flat | `lib/src/` nested |
| Features | 11 modules in `lib/features/` | 4 modules in `lib/src/modules/` |
| Core | `lib/core/` with auth, logging, models, providers, router, services | `lib/src/core/` minimal: router, shell, signal_listenable |
| State management | Riverpod only (22 providers) | Riverpod + Signals hybrid |
| App entry | `lib/app.dart` with `MaterialApp` directly | `ShellConfig` + `standard()` flavor factory |
| Design system | `lib/design/` | Did not exist; created as `lib/src/design/` |
| Shared widgets | 13 in `lib/shared/widgets/` | 2 in `lib/src/shared/` (flat, no `widgets/` subdir) |
| Packages | 3 (`soliplex_client`, `_native`, `_logging`) | 4 (added `soliplex_agent`) |
| SDK constraint | `>=3.5.0 <4.0.0` | `^3.6.0` |

---

## Theme System: What Existed in Each Repo

### `flutter` repo (source)

Full white-label theming from commit `e017a3f` (+4817/-1053 lines, 63 files):

- `lib/design/` directory with color, theme, and token subdirectories
- `ColorPalette` model with 7 required + 6 optional color roles
- `ColorConfig` wrapping light/dark palettes with sensible defaults
- `FontConfig` with body/display/brand font roles
- `ThemeConfig` compositing color + font configs
- `generateColorScheme()` — direct color math via `Color.lerp()`, no `fromSeed()`
- 30+ component theme builders in `component_themes.dart`
- `SoliplexTheme` ThemeExtension with ColorScheme, Radii, BadgeThemeData
- `SemanticColors` extension adding success/warning/info to ColorScheme
- `themeModeProvider` — Riverpod NotifierProvider with SharedPreferences persistence
- `ThemeToggleButton` ConsumerWidget
- Design tokens: spacing (s1–s6), radii (sm/md/lg/xl), breakpoints, typography
- Bundled fonts: Inter (body), Hyprsalvo (display), Tactical (brand)
- `MarkdownThemeExtension` for markdown rendering

### `frontend` repo (target, before port)

Minimal theme setup:

- `_defaultTheme()` in `lib/src/flavors/standard.dart` — bare `ThemeData()` with
  only a `MarkdownThemeExtension` added
- `ShellConfig` accepted a single `ThemeData theme` — no dark theme, no theme mode
- `MaterialApp.router` only set `theme:` — no `darkTheme:` or `themeMode:`
- No design tokens, no custom fonts (despite font files existing in `/fonts/`)
- No theme persistence or toggle
- `MarkdownThemeExtension` already existed identically at
  `lib/src/modules/room/ui/markdown/markdown_theme_extension.dart`

---

## Adaptations Required for the Port

### 1. File Placement — `lib/` vs `lib/src/`

The `flutter` repo places code directly under `lib/` (`lib/design/`,
`lib/core/models/`). The `frontend` repo nests everything under `lib/src/`.

**Mapping:**

| `flutter` path | `frontend` path |
|---|---|
| `lib/design/` | `lib/src/design/` |
| `lib/core/models/` | `lib/src/core/models/` |
| `lib/core/providers/` | `lib/src/core/providers/` |
| `lib/shared/widgets/theme_toggle_button.dart` | `lib/src/shared/theme_toggle_button.dart` |

The `frontend` repo's `shared/` directory is flat (no `widgets/` subdirectory), so
the toggle button was placed alongside existing `copy_button.dart` and
`file_type_icons.dart`.

### 2. Import Path Rewriting

Every file copied from `flutter` used absolute package imports like:

```dart
import 'package:soliplex_frontend/core/models/font_config.dart';
import 'package:soliplex_frontend/design/design.dart';
```

These were all converted to relative imports for the `frontend` repo:

```dart
import '../../core/models/font_config.dart';
import '../design.dart';
```

### 3. Shell Architecture — Single Theme to Light/Dark

This was the most significant structural adaptation. The `flutter` repo wired themes
directly in `app.dart`:

```dart
// flutter repo — app.dart
MaterialApp(
  theme: soliplexLightTheme(colorConfig: ..., fontConfig: ...),
  darkTheme: soliplexDarkTheme(colorConfig: ..., fontConfig: ...),
  themeMode: ref.watch(themeModeProvider),
)
```

The `frontend` repo uses a `ShellConfig` → `SoliplexShell` pattern where config is
built in `standard()` and passed to the shell. The shell was not a Consumer widget.

**Changes required:**

1. **`ShellConfig`** — Added `ThemeData? darkTheme` and
   `ThemeMode themeMode` fields (defaulting to `ThemeMode.system`).

2. **`SoliplexShell`** — The challenge was that `ProviderScope` is created *inside*
   `SoliplexShell.build()`, so the shell itself is outside any `ProviderScope` and
   cannot use `ref.watch()`. Solution: extracted a `_ThemedApp extends ConsumerWidget`
   that lives inside the `ProviderScope` and reactively watches `themeModeProvider`:

   ```dart
   // Before
   class _SoliplexShellState extends State<SoliplexShell> {
     Widget build(context) => ProviderScope(
       child: MaterialApp.router(theme: config.theme, ...),
     );
   }

   // After
   class _SoliplexShellState extends State<SoliplexShell> {
     Widget build(context) => ProviderScope(
       child: _ThemedApp(config: config, router: _router),
     );
   }

   class _ThemedApp extends ConsumerWidget {
     Widget build(context, ref) {
       final themeMode = ref.watch(themeModeProvider);
       return MaterialApp.router(
         theme: config.theme,
         darkTheme: config.darkTheme,
         themeMode: themeMode,
         ...
       );
     }
   }
   ```

3. **`standard()`** — Changed parameter from `ThemeData? theme` to
   `ThemeConfig? themeConfig`. Now generates both light and dark themes internally
   and passes them to `ShellConfig`.

### 4. Font Strategy Change — Bundled-Only to Bundled + Google Fonts

The `flutter` repo bundled all three fonts as assets (Inter, Hyprsalvo, Tactical) and
referenced them by `fontFamily` string on `TextStyle`. The `google_fonts` package was
listed as a dependency but never actually imported in code — font names in
`FontConfig` simply resolved from the bundled assets.

The `frontend` port uses a **hybrid approach** to demonstrate both methods:

| Font | Role | Resolution |
|---|---|---|
| Inter | Body | Bundled asset (registered in `pubspec.yaml` `flutter.fonts`) |
| Oswald | Display | `google_fonts` package (fetched + cached at runtime) |
| Squada One | Brand | `google_fonts` package (fetched + cached at runtime) |

**Code change in `theme.dart`:**

```dart
// flutter repo — font resolution was implicit (bundled assets only)
final textTheme = buildSoliplexTextTheme(
  bodyFont: fontConfig?.bodyFont,
  displayFont: fontConfig?.displayFont,
);

// frontend repo — explicit google_fonts resolution
var textTheme = buildSoliplexTextTheme(
  bodyFont: fontConfig?.bodyFont,
  displayFont: fontConfig?.displayFont,
);
textTheme = GoogleFonts.getTextTheme(
  fontConfig?.bodyFont ?? FontFamilies.body,
  textTheme,
);
```

`GoogleFonts.getTextTheme()` wraps the text theme so non-bundled font family strings
are resolved via the google_fonts cache. Bundled fonts (Inter) take precedence when
the family name matches a registered asset.

**`FontFamilies` defaults updated:**

```dart
// flutter repo
static const String display = 'Hyprsalvo';
static const String brand = 'Tactical';

// frontend repo
static const String display = 'Oswald';
static const String brand = 'SquadaOne';  // google_fonts naming (no space)
```

### 5. `typography_x.dart` — Platform Resolver Dependency

The `flutter` repo's `typography_x.dart` imported a `platform_resolver.dart` utility
from `lib/shared/utils/`. That utility didn't exist in the `frontend` repo, and
creating a `shared/utils/` directory for a single 4-line function was unnecessary.

**Solution:** Inlined the helper as a private function:

```dart
// flutter repo
import 'package:soliplex_frontend/shared/utils/platform_resolver.dart';
// ...
if (isCupertino(context)) { ... }

// frontend repo
bool _isCupertino(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}
// ...
if (_isCupertino(context)) { ... }
```

### 6. `meta` Package — Transitive vs Direct Dependency

The model files import `package:meta/meta.dart` for `@immutable` and
`@visibleForTesting` annotations. In the `flutter` repo this resolved transitively.
The `frontend` repo's linter (`depend_on_referenced_packages`) flagged this as an
error, requiring `meta` to be added as a direct dependency in `pubspec.yaml`.

### 7. MarkdownThemeExtension — Already Existed

The `MarkdownThemeExtension` class was identical in both repos. In the `flutter` repo
it lived at `lib/shared/widgets/markdown/markdown_theme_extension.dart`; in the
`frontend` repo at `lib/src/modules/room/ui/markdown/markdown_theme_extension.dart`.

No copy was needed. The `theme.dart` builder references it via a cross-module import:

```dart
import '../../modules/room/ui/markdown/markdown_theme_extension.dart';
```

This is a design→module cross-reference, which is acceptable since the design system
needs to populate theme extensions for the markdown renderer.

### 8. `main.dart` — Theme Initialization

The `flutter` repo's `main.dart` had more setup code (logging, config loading). The
`frontend` repo's `main.dart` is minimal. The only addition was the
`await initializeTheme()` call to preload the saved theme mode from
SharedPreferences before the first frame.

---

## Files Not Ported

These files from the `flutter` repo's theme system were intentionally excluded:

| File | Reason |
|---|---|
| `lib/core/models/soliplex_config.dart` | `frontend` uses `ShellConfig` instead; `showLogoInAppBar`/`showAppNameInAppBar` flags are specific to the `flutter` repo's AppBar layout |
| `lib/shared/widgets/overflow_tooltip.dart` | Utility widget created alongside the theme but not part of the theme system itself |
| `lib/shared/widgets/app_shell.dart` changes | AppBar layout with brand logo/toggle is specific to `flutter` repo's screen structure |
| `lib/core/router/app_router.dart` changes | Back button and routing changes are specific to `flutter` repo's feature structure |
| Feature screen migrations | The `frontend` repo already uses `ColorScheme` references, not `SoliplexColors` |

---

## Summary of New Dependencies

| Package | Version | Purpose |
|---|---|---|
| `google_fonts` | `^6.2.1` | Runtime font resolution for Oswald and Squada One |
| `meta` | `^1.17.0` | `@immutable` annotations in model classes (was transitive, now direct) |

---

## File Inventory

### 15 New Files

```
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

### 6 Modified Files

```
pubspec.yaml                        — google_fonts + meta deps, Inter font registration
lib/src/core/shell_config.dart      — darkTheme, themeMode fields
lib/src/core/shell.dart             — _ThemedApp ConsumerWidget extraction
lib/src/flavors/standard.dart       — ThemeConfig param, dual theme generation
lib/main.dart                       — initializeTheme() call
lib/soliplex_frontend.dart          — barrel exports for theme types
```
