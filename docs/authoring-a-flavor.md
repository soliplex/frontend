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
  installLogSinks();
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
kit (see ADR-003 §3.3). Every kit field is then yours to forward, and two of
them fail quietly if you don't. Forget `refreshListenable` and auth-driven
redirects stop re-evaluating. Forget `initialRoute` and it falls back to `/`,
which discards the kit's answer — so someone returning mid sign-in lands on the
sign-in screen instead of the callback that would have consumed their tokens,
and the sign-in never completes. Pass `kit.initialRoute` verbatim; a literal of
your own has the same effect, and it also strands `signedOutLandingPath`, whose
path the guard still admits even though nothing lands on it.
Prefer `standardFlavor` unless you genuinely need a different module graph.

## Rules

- Build the theme with `buildSoliplexThemeData` (never a bare `ThemeData`) — the
  `SoliplexTheme` extension is required and `Flavor.build()` (via
  `ShellConfig.fromModules`) throws without it.
- Composition is append-only: add your own modules via `extraModules`; do not
  drop standard ones (Room depends on Lobby, and modules share session state).
- Logging is yours to install, and nothing installs it for you: with no sink
  attached `LogManager` discards every record. Call `installLogSinks()` before
  you build your flavor, as the `main()` above does — the storage migration,
  server restoration and the contrast checks below all log while the flavor is
  being assembled.
- Contrast checks only warn, never block. The warnings go through `LogManager`,
  so without a sink installed first they drop silently.
- Disposal is yours: the `ShellConfig` returned by `Flavor.build()` carries a
  `dispose` callback that the shell widget never invokes. Standalone apps can
  rely on OS reclamation; embedders that unmount the shell must retain the
  config and `await config.dispose()` themselves.
- `standardFlavor`'s `extraPublicPaths` is what makes a route of yours
  reachable without a session — an intro or welcome screen. It is on
  `buildStandardKit` too, and deliberately not on `standard()`: without
  `extraModules` there is no route of your own to declare, and the only
  standard path it could open is the lobby, which without a session has nothing
  to show. Requests
  arrive normalized but your entries are compared literally, so write
  `/welcome`: a leading slash, no trailing slash, no query or fragment. Those
  forms could never match, and an assertion rejects them in debug and under
  test rather than leaving you a dead entry. The request side stays forgiving —
  `/welcome/` and `/welcome?ref=email` both reach a declared `/welcome`.
  Matching is exact, never a prefix: declaring `/welcome` leaves
  `/welcome/admin` guarded, and `/welcome/:step` resolves per visit to a
  concrete path that matches no entry.
- `signedOutLandingPath` lands a signed-out launch on a screen of your own
  instead of the sign-in page — it sits on the same two functions, and like
  `extraPublicPaths` not on `standard()`. You do not declare it public
  separately: the guard admits it, since a landing path it bounced would be
  meaningless. It replaces only that one branch — an in-flight auth callback
  still finishes, and an already-connected stored server still opens the lobby.
  A server that needs no sign-in counts as connected, so such a deployment
  shows this screen on a fresh install and goes straight to the lobby on every
  launch after it has stored one. The path follows the same form rules as an
  entry above — a leading slash, no trailing slash, no query or fragment — and
  it must name a literal route one of your modules registers, not a concrete
  instance of a parameterized one like `/room/prod/123`. That check runs against the route the app actually starts on, so a
  machine with a connected server will not surface a typo here —
  `Flavor.build()` throws on a signed-out launch, listing the paths it does
  know.
- Two ways `extraPublicPaths` can bite. Nothing checks an entry against your
  routes, and an entry naming none is worse than inert: the guard stops
  bouncing that location, so an unauthenticated visitor reaches go_router's
  "Page Not Found" screen instead of the server list. And declaring a path that
  already belongs to a module removes that screen's sign-in guard — for a
  per-server path that also costs the return trip, since the route's own guard
  bounces to a bare `/lobby` rather than to sign-in-and-come-back. On its own
  `extraPublicPaths` leaves your `initialRoute` untouched, so a cold launch
  lands where it did. On web a URL to a declared path opens it directly,
  because go_router prefers a non-`/` platform route over `initialLocation`;
  native deep links do not, since no platform in this repo enables Flutter deep
  linking.
