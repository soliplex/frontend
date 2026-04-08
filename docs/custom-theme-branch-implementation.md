# Custom Theme — Implementation Guide

This guide gives the step-by-step procedure for standing up the same
white-label theming system in a new Flutter repo (or for adding it to an
existing repo that does not have one).

It mirrors the architecture used by the `custom-theme` branch of `frontend`
— see [`custom-theme-branch-changes.md`](custom-theme-branch-changes.md) for a
description of the system as a whole.

The instructions assume:

- A Flutter app using `lib/src/...` nesting (i.e. `lib/src/core/`,
  `lib/src/design/`, etc.). If your repo uses flat `lib/`, drop the `src/`
  segment from every path.
- Riverpod for state management (`flutter_riverpod ^3`).
- A modular shell pattern where a flavor factory (`standard()` here) builds a
  config object that is passed to a top-level shell widget. If you do not have
  this pattern, the same wiring goes directly into your `MaterialApp`
  construction.

---

## Prerequisites

Add the following dependencies to `pubspec.yaml`:

```yaml
dependencies:
  flutter_riverpod: ^3.1.0
  google_fonts: ^6.2.1
  meta: ^1.17.0
  shared_preferences: ^2.5.5
```

Then run `flutter pub get`.

`meta` is needed as a **direct** dependency (not just transitive) because the
model files use `@immutable` and `@visibleForTesting` annotations and the
`depend_on_referenced_packages` lint flags imports of transitive packages.

---

## Step 1 — Bundle fonts (optional)

If you want to ship one or more font families as assets (recommended for the
default body font so the app looks correct offline), drop the `.ttf` / `.otf`
files into a `fonts/` directory at the project root and register them under
`flutter.fonts` in `pubspec.yaml`. Example for the bundled `Inter` family used
by `frontend`:

```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: fonts/Inter-VariableFont_opsz,wght.ttf
        - asset: fonts/Inter-Italic-VariableFont_opsz,wght.ttf
          style: italic
```

Any non-bundled font family used in your `FontConfig` will be resolved at
runtime by `google_fonts` (Step 7's `_buildTheme` wires this up).

---

## Step 2 — Create the color model

Create `lib/src/core/models/color_config.dart` containing:

1. **`ColorPalette`** — `@immutable` class with 7 required `Color` fields
   (`primary`, `secondary`, `background`, `foreground`, `muted`,
   `mutedForeground`, `border`) and 6 optional ones (`tertiary`, `error`,
   `onPrimary`, `onSecondary`, `onTertiary`, `onError`).
2. **Default constructors** `ColorPalette.defaultLight()` and
   `ColorPalette.defaultDark()` so that `const ColorConfig()` produces a
   usable theme out of the box.
3. **`effective*` getters** that fall back to luminance-computed contrast or
   sensible defaults when the optional fields are `null`. Implement a private
   `Color _contrastColor(Color)` helper that returns black for luminance > 0.5
   and white otherwise.
4. **`copyWith`** with `clear*` flags for resetting the optional fields to
   `null`.
5. Standard `==`, `hashCode`, `toString`.
6. **`ColorConfig`** — wraps a `light: ColorPalette` and `dark: ColorPalette`,
   both defaulting to `ColorPalette.defaultLight()` / `defaultDark()`.

---

## Step 3 — Create the font model

Create `lib/src/core/models/font_config.dart` containing a single
`@immutable FontConfig` class with four nullable `String?` fields:
`bodyFont`, `displayFont`, `brandFont`, `codeFont`.

Provide `copyWith` with `clear*` flags, and the standard `==` / `hashCode` /
`toString`.

When a field is `null`, the consuming code should use Material defaults (no
`fontFamily` set on `TextStyle`). For `codeFont`, `null` means a
platform-adaptive monospace, which is resolved later in `SoliplexTheme`
(Step 8).

---

## Step 4 — Create the composite theme config

Create `lib/src/core/models/theme_config.dart` containing a `@immutable
ThemeConfig` class with two fields:

```dart
final ColorConfig? colorConfig;
final FontConfig? fontConfig;
```

Both default to `null`. `copyWith` should support `clearColorConfig` /
`clearFontConfig` flags. This is the single object consumers will pass into
the flavor factory.

---

## Step 5 — Create the theme-mode provider

Create `lib/src/core/providers/theme_provider.dart`:

1. A top-level `ThemeMode? _preloadedThemeMode` cache.
2. `Future<void> initializeTheme()` — reads `prefs.getString('theme_mode')`
   from `SharedPreferences` and parses it via `ThemeMode.values.firstWhere`
   into `_preloadedThemeMode`. **Must be called from `main()` before `runApp`**
   to avoid a flash of the wrong theme on the first frame.
3. `class ThemeModeNotifier extends Notifier<ThemeMode>` — its `build()`
   returns `_preloadedThemeMode ?? ThemeMode.system`. Expose:
   - `Future<void> toggle(Brightness systemBrightness)` — resolves
     `ThemeMode.system` to actual brightness first, then flips between
     `light` and `dark`.
   - A private `_setAndPersist` that writes to `SharedPreferences` and
     updates `state`.
4. `final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(...)`.
5. `@visibleForTesting void resetPreloadedThemeMode()` for test isolation.

---

## Step 6 — Create design tokens

Create the following under `lib/src/design/tokens/`:

- **`breakpoints.dart`** — width thresholds (`compact`, `tablet`, `desktop`,
  etc.) used for responsive layouts.
- **`spacing.dart`** — `SoliplexSpacing` constants (`s1`–`sN`) used by
  component themes for consistent padding.
- **`radii.dart`** — a `SoliplexRadii` class with `sm` / `md` / `lg` / `xl`
  fields, plus a `lerp(a, b, t)` static method (so it can participate in
  `ThemeExtension.lerp`).
- **`typography.dart`** — see Step 6a below.
- **`typography_x.dart`** — optional platform-aware text helpers (Cupertino
  vs Material). Inline any small helper rather than introducing a
  `shared/utils/` directory for one function.

### Step 6a — `typography.dart`

Define an `abstract final class FontFamilies` with constants for your default
fonts:

```dart
abstract final class FontFamilies {
  static const String body = 'Inter';        // bundled in Step 1
  static const String display = 'Oswald';    // resolved via google_fonts
  static const String brand = 'SquadaOne';   // resolved via google_fonts
  static const String codeApple = 'SF Mono';
  static const String codeDefault = 'Roboto Mono';
}
```

Then a builder function:

```dart
TextTheme buildSoliplexTextTheme({String? bodyFont, String? displayFont}) {
  return TextTheme(
    displayLarge: TextStyle(fontFamily: displayFont, fontSize: 48, ...),
    // ... 14 more styles covering display/headline/title/body/label
  );
}
```

Provide all 15 styles of the Material 3 type scale with explicit `fontSize`,
`fontWeight`, `letterSpacing`, and `height`. Use `displayFont` for the three
display styles and `bodyFont` for everything else. Do **not** set colors here
— colors are applied later via `textTheme.apply(bodyColor:, displayColor:)`.

---

## Step 7 — Create `generateColorScheme()`

Create `lib/src/design/theme/theme.dart` and add a top-level
`generateColorScheme` function:

```dart
ColorScheme generateColorScheme({
  required Brightness brightness,
  required ColorPalette palette,
}) {
  // Lerp surface containers via Color.lerp(background, muted, t)
  // for t in (0.05, 0.15, 0.30, 0.55, 0.80)
  // Compute container colors via Color.lerp(role, background, 0.85)
  // and Color.lerp(role, foreground, 0.7)
  // Compute *Fixed and on*Fixed roles via lerps with white/black
  // Return a ColorScheme(...) with EVERY field populated.
}
```

The goal is that no Material widget falls back to a default tint. Refer to
the `frontend` implementation (`lib/src/design/theme/theme.dart`) for the
exact lerp constants — they were tuned by hand and produce the expected M3
look.

---

## Step 8 — Create the `SoliplexTheme` `ThemeExtension`

Create `lib/src/design/theme/theme_extensions.dart`:

```dart
class SoliplexBadgeThemeData {
  const SoliplexBadgeThemeData({
    required this.background,
    required this.textStyle,
    required this.padding,
  });
  // ...
}

class SoliplexTheme extends ThemeExtension<SoliplexTheme> {
  const SoliplexTheme({
    required this.colors,    // ColorScheme
    required this.radii,     // SoliplexRadii
    required this.badgeTheme,
    this.codeFont,           // String?
  });
  // implement copyWith, lerp, of(context)
}
```

Add three static helpers for code rendering:

- `static String resolveCodeFontFamily(BuildContext context)` — returns the
  configured `codeFont` if set, otherwise returns
  `FontFamilies.codeApple` on iOS/macOS and `FontFamilies.codeDefault`
  elsewhere.
- `static TextStyle codeStyle(BuildContext context)` — convenience returning a
  `TextStyle` with that family and `fontFamilyFallback: ['monospace']`.
- `static TextStyle mergeCode(BuildContext context, [TextStyle? base])` —
  copies the code font + monospace fallback onto an existing `TextStyle`.

(Optional) Add `static TextStyle? appBarTitleStyle(BuildContext context)` for
a responsive AppBar title style based on a `MediaQuery.sizeOf(context).width`
breakpoint check.

---

## Step 9 — Create semantic colors

Create `lib/src/design/color/color_scheme_extensions.dart` with a
`SemanticColors extension on ColorScheme` that adds `success`, `warning`, and
`info` (each with `on*` and `*Container` / `on*Container` pairs).

Implement a private `_SemanticPalettes` final class that pre-computes
`ColorScheme.fromSeed()` palettes for each seed in light and dark, so that
each call site is O(1):

```dart
abstract final class SemanticSeeds {
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFE65100);
  static const info    = Color(0xFF1565C0);
}

abstract final class _SemanticPalettes {
  static final _successLight = ColorScheme.fromSeed(seedColor: SemanticSeeds.success);
  static final _successDark  = ColorScheme.fromSeed(seedColor: SemanticSeeds.success, brightness: Brightness.dark);
  // ... and so on for warning and info

  static ColorScheme success(Brightness b) =>
      b == Brightness.light ? _successLight : _successDark;
}

extension SemanticColors on ColorScheme {
  Color get success => _SemanticPalettes.success(brightness).primary;
  // ... etc.
}
```

---

## Step 10 — Create `component_themes.dart`

Create `lib/src/design/theme/component_themes.dart` with one builder
function per Material component you want to style. The signature for each is
either `buildXxxTheme(ColorScheme cs)` or, for text-bearing components,
`buildXxxTheme(ColorScheme cs, {FontConfig? fontConfig})`.

Cover (at minimum):

- Buttons: FilledButton, OutlinedButton, TextButton, IconButton,
  ElevatedButton, ToggleButtons, SegmentedButton, FloatingActionButton
- Navigation: NavigationBar, NavigationRail, NavigationDrawer, Drawer,
  BottomNavigationBar, BottomAppBar
- Inputs: InputDecoration, Checkbox, Radio, Slider, Switch, SearchBar,
  SearchView, DropdownMenu
- Data display: ListTile, Card, Chip, DataTable, ExpansionTile, Badge,
  Tooltip, ProgressIndicator
- Dialogs and surfaces: Dialog, SnackBar, BottomSheet, Banner, PopupMenu,
  Menu, MenuBar, MenuButton
- Date/time: DatePicker, TimePicker
- Layout: AppBar, Divider, TabBar

Each builder should pull radii from `soliplexRadii` and padding from
`SoliplexSpacing` for consistency.

---

## Step 11 — Wire up `_buildTheme` and the public theme functions

Back in `lib/src/design/theme/theme.dart`, add:

```dart
ThemeData soliplexLightTheme({ColorConfig? colorConfig, FontConfig? fontConfig}) {
  final colors = colorConfig ?? const ColorConfig();
  final scheme = generateColorScheme(
    brightness: Brightness.light,
    palette: colors.light,
  );
  return _buildTheme(scheme, fontConfig: fontConfig);
}

ThemeData soliplexDarkTheme({ColorConfig? colorConfig, FontConfig? fontConfig}) {
  final colors = colorConfig ?? const ColorConfig();
  final scheme = generateColorScheme(
    brightness: Brightness.dark,
    palette: colors.dark,
  );
  return _buildTheme(scheme, fontConfig: fontConfig);
}

ThemeData _buildTheme(ColorScheme cs, {FontConfig? fontConfig}) {
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
    brightness: cs.brightness,
    colorScheme: cs,
    textTheme: textTheme.apply(
      bodyColor: cs.onSurface,
      displayColor: cs.onSurface,
    ),
    scaffoldBackgroundColor: cs.surface,
    canvasColor: cs.surface,
    appBarTheme: buildAppBarTheme(cs, fontConfig: fontConfig),
    // ... call every component builder from Step 10
    extensions: [
      SoliplexTheme(
        colors: cs,
        radii: soliplexRadii,
        codeFont: fontConfig?.codeFont,
        badgeTheme: SoliplexBadgeThemeData(
          background: Color.alphaBlend(
            cs.onSurface.withAlpha(15),
            cs.surface,
          ),
          textStyle: textTheme.labelMedium!.copyWith(color: cs.onSurface),
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s2,
            vertical: SoliplexSpacing.s1,
          ),
        ),
      ),
      // ... any other ThemeExtensions you use (e.g. MarkdownThemeExtension)
    ],
  );
}
```

`GoogleFonts.getTextTheme` is what makes the hybrid font strategy work:
bundled families take precedence when their name matches a registered asset,
and any other family is fetched and cached at runtime.

---

## Step 12 — Create the theme toggle button

Create `lib/src/shared/theme_toggle_button.dart`:

```dart
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final effective = mode == ThemeMode.system
        ? systemBrightness
        : (mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
    final isDark = effective == Brightness.dark;

    return Semantics(
      label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: IconButton(
        icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
        tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: () =>
            ref.read(themeModeProvider.notifier).toggle(systemBrightness),
      ),
    );
  }
}
```

Place it wherever your screens import shared widgets from.

---

## Step 13 — Extend your `ShellConfig`

Add two fields to your shell config (in `frontend` this is
`lib/src/core/shell_config.dart`):

```dart
final ThemeData? darkTheme;
final ThemeMode themeMode;   // default ThemeMode.system
```

Keep the existing `ThemeData theme` field — it now represents the light
theme.

If you do not use a `ShellConfig` pattern, skip this step and pass
`darkTheme:` and `themeMode:` straight to `MaterialApp.router` in Step 14.

---

## Step 14 — Make the shell reactive to theme mode

This is the trickiest part. Your shell widget probably creates a
`ProviderScope` inside its own `build`, which means the shell itself sits
**outside** any `ProviderScope` and cannot use `ref.watch()`.

The fix is to extract a private `_ThemedApp extends ConsumerWidget` that
lives **inside** the scope:

```dart
class _SoliplexShellState extends State<SoliplexShell> {
  late final _router = buildRouter(widget.config);

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: widget.config.overrides,
      child: _ThemedApp(config: widget.config, router: _router),
    );
  }
}

class _ThemedApp extends ConsumerWidget {
  const _ThemedApp({required this.config, required this.router});
  final ShellConfig config;
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

If you do not use a shell pattern, just make whichever widget owns your
`MaterialApp` a `ConsumerWidget` and watch `themeModeProvider` there.

---

## Step 15 — Wire `themeConfig` into your flavor

Add an optional `ThemeConfig? themeConfig` parameter to your flavor factory
(in `frontend` this is `standard()` in `lib/src/flavors/standard.dart`).
Inside the factory, generate both light and dark themes and pass them to
`ShellConfig`:

```dart
const _defaultFontConfig = FontConfig(
  bodyFont: FontFamilies.body,
  displayFont: FontFamilies.display,
  brandFont: FontFamilies.brand,
);

Future<ShellConfig> standard({
  String appName = 'MyApp',
  ThemeConfig? themeConfig,
  // ... other params
}) async {
  // ... existing setup
  return ShellConfig(
    appName: appName,
    theme: soliplexLightTheme(
      colorConfig: themeConfig?.colorConfig,
      fontConfig: themeConfig?.fontConfig ?? _defaultFontConfig,
    ),
    darkTheme: soliplexDarkTheme(
      colorConfig: themeConfig?.colorConfig,
      fontConfig: themeConfig?.fontConfig ?? _defaultFontConfig,
    ),
    // ... rest of config
  );
}
```

Falling back to `_defaultFontConfig` ensures the bundled `Inter` and the
google-fonts `Oswald` / `SquadaOne` are used when the consumer does not
override them.

---

## Step 16 — Wire `main.dart`

Call `initializeTheme()` **before** `runApp` so the saved theme mode is
available on the first frame:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeTheme();
  runSoliplexShell(await standard(
    themeConfig: const ThemeConfig(),
  ));
}
```

Replace `const ThemeConfig()` with whatever brand customization you want, e.g.:

```dart
themeConfig: const ThemeConfig(
  colorConfig: ColorConfig(
    light: ColorPalette(
      primary: Color(0xFF1976D2),
      secondary: Color(0xFF03DAC6),
      background: Color(0xFFFAFAFA),
      foreground: Color(0xFF1A1A1E),
      muted: Color(0xFFE4E4E8),
      mutedForeground: Color(0xFF6E6E78),
      border: Color(0xFFC8C8CE),
    ),
  ),
  fontConfig: FontConfig(
    bodyFont: 'Inter',
    displayFont: 'Oswald',
    codeFont: 'JetBrains Mono',
  ),
),
```

---

## Step 17 — Export the public API

Re-export the new types from your library barrel
(`lib/<package_name>.dart`):

```dart
export 'src/core/models/color_config.dart' show ColorPalette, ColorConfig;
export 'src/core/models/font_config.dart' show FontConfig;
export 'src/core/models/theme_config.dart' show ThemeConfig;
export 'src/core/providers/theme_provider.dart'
    show themeModeProvider, initializeTheme;
export 'src/design/design.dart';
```

Where `lib/src/design/design.dart` is a barrel that re-exports the design
tokens, the theme functions, and `theme_extensions.dart`.

---

## Step 18 — Add tests

Cover the new public surface. Suggested files:

- `test/core/models/color_config_test.dart` — `ColorPalette` defaults,
  `effective*` getters, `copyWith` (including every `clear*` flag), equality.
- `test/core/models/font_config_test.dart` — `FontConfig` defaults, `copyWith`,
  `clear*` flags.
- `test/core/providers/theme_provider_test.dart` — `initializeTheme()` reads
  from `SharedPreferences.setMockInitialValues({...})`, `ThemeModeNotifier`
  toggle behavior including `ThemeMode.system` resolution, persistence after
  toggle. Use the `resetPreloadedThemeMode()` helper between tests.
- `test/design/theme/theme_test.dart` — light and dark `ThemeData` smoke
  tests, plus targeted assertions on a few `generateColorScheme()` outputs
  (e.g. that `outline == palette.border`, that `surface == palette.background`,
  that container colors fall on the expected lerp).
- `test/shared/theme_toggle_button_test.dart` — icon selection in light /
  dark / system mode, semantics labels, that tapping the button calls
  `toggle`.

If your test setup uses `google_fonts` indirectly via `_buildTheme`, override
`HttpOverrides.global` in `setUp` to prevent it from making real network
requests.

---

## Step 19 — Run quality checks

Per the project's `CLAUDE.md`, prefer the Dart MCP tools, with shell fallbacks:

| Check | MCP tool | Shell fallback |
| ----- | -------- | -------------- |
| Format | `mcp__dart__dart_format` | `dart format .` |
| Analyze (must be zero issues) | `mcp__dart__analyze_files` | `flutter analyze` |
| Tests | `mcp__dart__run_tests` | `flutter test --reporter failures-only` |
| Markdown lint (any `.md` you touched) | — | `markdownlint-cli2 "**/*.md" "#node_modules"` |

All checks must pass with zero diagnostics before the work is considered
complete.

---

## Verification — end-to-end smoke test

After everything is wired up:

1. `flutter run -d macos` (or your preferred device).
2. Confirm the app boots in the saved theme mode (defaults to system).
3. Tap the `ThemeToggleButton`. The app should switch theme immediately
   without rebuilding the route or losing state.
4. Hot-restart the app. The previously toggled theme should still be in
   effect (proves `SharedPreferences` persistence + `initializeTheme`
   preload).
5. Build a custom `ColorConfig` and pass it via `themeConfig` in `main.dart`.
   Confirm that `Theme.of(context).colorScheme.primary` reflects your
   `ColorPalette.primary` and that derived roles (`primaryContainer`, the
   surface container scale, etc.) all change accordingly.
6. Set a `FontConfig.codeFont` to a `google_fonts` family (e.g.
   `'JetBrains Mono'`). Confirm that any widget using
   `SoliplexTheme.codeStyle(context)` picks up the new font once the
   first runtime fetch completes.
