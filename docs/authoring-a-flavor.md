# Authoring your own flavor

`standard()` is the opinionated default. To customize beyond the curated
`BrandTheme` — full color control, extra modules — write your own flavor with
`buildStandardModules`. You need only a `soliplex_frontend` dependency.

## Theme paths

- `standard()` lowers a curated `BrandTheme` via `lowerBrandTheme`, which ends at
  `buildSoliplexThemeData`.
- A custom flavor calls `buildSoliplexThemeData` directly with a full
  `SoliplexColors` — typically `lightSoliplexColors` / `darkSoliplexColors` with
  the slots you need overridden. Both attach the `SoliplexTheme` extension and
  run the contrast check; the direct path has no on-color auto-derivation, so you
  own legibility (a warning fires for low-contrast foreground/background role
  pairs — but `link` is contrast-checked only when building through
  `lowerBrandTheme` (from a `BrandTheme`); the direct `buildSoliplexThemeData`
  path never checks `link`, so verify a custom `link` color yourself).

## Example

```dart
import 'package:flutter/material.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/flavors.dart';

Future<ShellConfig> myFlavor() async {
  final identity = AppIdentity.soliplex; // or your own AppIdentity
  final standardModules = await buildStandardModules(
    identity: identity,
    defaultBackendUrl: 'https://api.mybrand.com',
  );

  final light = buildSoliplexThemeData(
      colors: lightSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF)),
      brightness: Brightness.light);
  final dark = buildSoliplexThemeData(
      colors: darkSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF)),
      brightness: Brightness.dark);

  return ShellConfig.fromModules(
    appName: identity.appName,
    lightTheme: light,
    darkTheme: dark,
    themeMode: ThemeMode.system,
    initialRoute: standardModules.initialRoute,
    refreshListenable: standardModules.refreshListenable,
    inactivity: standardModules.inactivity,
    modules: [
      ...standardModules.modules,
      // MyCustomModule(standardModules.serverManager),
    ],
  );
}
```

## Rules

- Build the theme with `buildSoliplexThemeData` (never a bare `ThemeData`) — the
  `SoliplexTheme` extension is required and `ShellConfig.fromModules` throws
  without it.
- Composition is append-only: add your own modules; do not drop standard ones
  (Room depends on Lobby, and modules share session state).
- Contrast checks only warn, never block. The warnings go through `LogManager`,
  so attach a log sink in your app's `main()` to see them — with no sink
  attached they drop silently.
