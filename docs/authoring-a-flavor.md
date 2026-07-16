# Authoring your own flavor

`standard()` is the opinionated default. To customize beyond the curated
`BrandTheme` — full color control, extra modules — compose your own `Flavor`
with `standardFlavor()`. You need only a `soliplex_frontend` dependency.
The design record is `docs/adr/ADR-003-flavor-object.md`.

A `Flavor` is the complete declaration of an app variant — identity, theme,
modules, boot knobs — as an immutable value. `Flavor.build()` lowers it to
the boot-ready `ShellConfig`, owning the assembly (identity threading, brand
lowering, kit-field forwarding) so your flavor never transcribes it.

## Theme paths

`FlavorTheme` is the theme half of a flavor, one slot wrapping both public
theming paths (and it carries `themeMode`):

- `FlavorTheme.brand(BrandTheme, ...)` — the curated contract. Lowered via
  `lowerBrandTheme` when the flavor builds; unset on-colors are derived to
  clear WCAG AA by construction.
- `FlavorTheme.themeData(light:, dark:)` — full token control. Build each
  `ThemeData` with `buildSoliplexThemeData` and a full `SoliplexColors` —
  typically `lightSoliplexColors` / `darkSoliplexColors` with the slots you
  need overridden. This path has no on-color auto-derivation, so you own
  legibility (a warning fires for low-contrast foreground/background role
  pairs — but `link` is contrast-checked only when building through
  `lowerBrandTheme` (from a `BrandTheme`); the direct `buildSoliplexThemeData`
  path never checks `link`, so verify a custom `link` color yourself).

Both paths end at `buildSoliplexThemeData`, which attaches the `SoliplexTheme`
extension and runs the contrast check.

## Example

```dart
import 'package:flutter/material.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/flavors.dart';

Future<Flavor> myFlavor() {
  final light = buildSoliplexThemeData(
      colors: lightSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF)),
      brightness: Brightness.light);
  final dark = buildSoliplexThemeData(
      colors: darkSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF)),
      brightness: Brightness.dark);

  return standardFlavor(
    identity: AppIdentity.soliplex, // or your own AppIdentity
    defaultBackendUrl: 'https://api.mybrand.com',
    theme: FlavorTheme.themeData(light: light, dark: dark),
    // Custom modules receive the composition kit, so they can share the
    // standard flavor's session state:
    // extraModules: (kit) => [MyCustomModule(kit.serverManager)],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flavor = await myFlavor();
  runSoliplexShell(await flavor.build());
}
```

Deriving a variant is a value operation — no re-assembly:

```dart
final base = await standardFlavor();
final darkOnly = base.copyWith(
  theme: FlavorTheme.themeData(light: light, dark: dark, mode: ThemeMode.dark),
);
```

For compositions that diverge further than `standardFlavor` allows, drop one
level: call `buildStandardModules` yourself and construct a `Flavor` from its
kit (see ADR-003 §3.3).

## Rules

- Build the theme with `buildSoliplexThemeData` (never a bare `ThemeData`) — the
  `SoliplexTheme` extension is required and `Flavor.build()` (via
  `ShellConfig.fromModules`) throws without it.
- Composition is append-only: add your own modules via `extraModules`; do not
  drop standard ones (Room depends on Lobby, and modules share session state).
- Contrast checks only warn, never block. The warnings go through `LogManager`,
  so attach a log sink in your app's `main()` to see them — with no sink
  attached they drop silently.
