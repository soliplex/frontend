# Authoring your own flavor

`standard()` is the opinionated default. To customize beyond the curated
`BrandTheme` — full color control, extra modules — compose your own `Flavor`
with `standardFlavor()`. You need only a `soliplex_frontend` dependency and a
single import (the main barrel carries the whole flavor-authoring surface).
The design record is `docs/adr/ADR-003-flavor-object.md`.

A `Flavor` is the complete declaration of an app variant — identity, theme,
modules, boot knobs — as a single-use assembly declaration, built once.
`Flavor.build()` lowers it to the boot-ready `ShellConfig`, owning the assembly
(identity threading, brand lowering, kit-field forwarding) so your flavor never
transcribes it.

## Theme paths

`FlavorTheme` is the theme half of a flavor, one slot wrapping both public
theming paths (and it carries `mode`, the `ThemeMode`):

- `FlavorTheme.brand(BrandTheme, ...)` — the curated contract. Lowered via
  `lowerBrandTheme` when the flavor builds; unset on-colors are derived to
  clear WCAG AA by construction.
- `FlavorTheme.themeData(light:, dark:)` — full token control. Build each
  `ThemeData` with `buildSoliplexThemeData` from a full `SoliplexColors`
  (typically `lightSoliplexColors` / `darkSoliplexColors` with slots
  overridden), passing `classifications` and fonts there too — the `.themeData`
  slot itself carries only `mode`. This path has no on-color auto-derivation, so
  you own legibility: a warning fires for every low-contrast role pair (`link`
  included), but the colors ship as-is regardless, so verify them yourself.

Both paths end at `buildSoliplexThemeData`, which attaches the `SoliplexTheme`
extension and runs the contrast check.

## Example

```dart
import 'package:flutter/material.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

Future<Flavor> myFlavor() {
  final light = buildSoliplexThemeData(
      colors: lightSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF)),
      brightness: Brightness.light);
  final dark = buildSoliplexThemeData(
      colors: darkSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF)),
      brightness: Brightness.dark);

  return standardFlavor(
    identity: AppIdentity(
      appName: 'MyBrand',
      logoLight: Image.asset('assets/my_logo.png'),
    ),
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
  runSoliplexShell(flavor.build());
}
```

Customize through `standardFlavor`'s parameters — identity, theme,
`extraModules` — not by mutating a built flavor. It performs real provisioning
(storage migration, server restoration) and holds live module instances, so
`build()` runs once: a second call throws.

## Diverging further

For compositions that diverge further than `standardFlavor` allows, drop one
level: call `buildStandardKit` yourself and construct a `Flavor` from its
kit (see ADR-003 §3.3). Every kit field is then yours to forward — forget
`refreshListenable` and auth-driven redirects silently stop re-evaluating.
Prefer `standardFlavor` unless you genuinely need a different module graph.

## Rules

- Build the theme with `buildSoliplexThemeData` (never a bare `ThemeData`) — the
  `SoliplexTheme` extension is required and `Flavor.build()` (via
  `ShellConfig.fromModules`) throws without it.
- Composition is append-only: add your own modules via `extraModules`; do not
  drop standard ones (Room depends on Lobby, and modules share session state).
- Contrast checks only warn, never block. The warnings go through `LogManager`,
  so attach a log sink in your app's `main()` to see them — with no sink
  attached they drop silently.
- Disposal is yours: the `ShellConfig` returned by `Flavor.build()` carries a
  `dispose` callback that the shell widget never invokes. Standalone apps can
  rely on OS reclamation; embedders that unmount the shell must retain the
  config and `await config.dispose()` themselves.
