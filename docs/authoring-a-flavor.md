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
  // Pass the builder, not the built config: `Flavor.build()` throws on an
  // invalid configuration, and a throw out here lands before any view exists —
  // which on iOS, macOS and Android is not a crash but a launch that never
  // finishes. Inside, it becomes a message naming the route at fault.
  await runSoliplexShell(flavor.build);
}
```

Customize through `standardFlavor`'s parameters — identity, theme,
`extraModules` — not by mutating a built flavor. It performs real provisioning
(storage migration, server restoration) and holds live module instances, so
`build()` runs once: a second call throws.

## Diverging further

For compositions that diverge further than `standardFlavor` allows, drop one
level: call `buildStandardKit` yourself and construct a `Flavor` from its
kit (see ADR-003 §3.3). Six of the kit's seven fields are then yours to forward
— `serverManager` is not one of them; it is shared state for `extraModules`,
not a `Flavor` field. Omit any of the six and it fails quietly, with one
partial exception: whether the config guard catches a missing `modules` or
`initialRoute` depends on your own module set, since it can only ask whether
some module registers the initial route. Three of the six are worth spelling
out; the other two, `inactivity` and `statusMessage`, silently revert to
defaults, so an auto-logout policy or a status-message endpoint you configured
on the kit simply does not apply.

Forget `refreshListenable` and auth-driven redirects stop re-evaluating.

Forget `initialRoute` and it falls back to `/`, which discards the kit's answer
— so someone returning mid sign-in lands on the sign-in screen instead of the
callback that would have consumed their tokens, and the sign-in never
completes. Pass `kit.initialRoute` verbatim; a literal of your own has the same
effect, and it also strands `signedOutLandingPath`, whose value the kit already
folded into that answer.

Forget `signedOutLandingPath` — it is a kit field of its own, and forwarding
only `kit.initialRoute` looks like it worked. The launch lands where you meant,
because the kit folded the path in; what you lose is the check. `Flavor`
validates that path against the routes and the public declarations, and a
`Flavor` that never received it validates nothing. So a fork gets the behaviour
and silently loses the guard against the two mistakes it is most likely to
make: naming a screen that does not exist, or one no module declared reachable
without a session. Forward `kit.signedOutLandingPath` alongside
`kit.initialRoute`; they answer different questions and the kit carries both.

A fourth quiet failure is not a kit field at all: building the `GoRouter` from
the module contributions rather than from the built config. A router assembled
out of `ModuleRoutes.routes` and `ModuleRoutes.redirect` never sees the
public-path step, and the sign-in guard then bounces `/auth/callback`,
`/diagnostics`, `/versions` and any screen of your own to the server list —
losing an in-flight sign-in in the first case.

Assembling from a `ShellConfig` is safe: `ShellConfig.redirect` is the module
redirects already composed behind that step, which is why the uncomposed ones
are not exposed. Simplest is still `buildRouter(flavor.build())` — it is
exported for exactly this, and it is what the shell runs, so your tests cannot
drift from production by reproducing the composition slightly differently.
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
- A route of yours is reachable without a session when the module that registers
  it says so — `publicPaths` on the `ModuleRoutes` your `AppModule.build()`
  returns, one line beside the route it names:

  ```dart
  ModuleRoutes build() => ModuleRoutes(
        routes: [GoRoute(path: '/welcome', builder: (_, __) => WelcomeScreen())],
        publicPaths: const {'/welcome'},
      );
  ```

  There is no flavor-level parameter for this, deliberately: the module that
  owns the route owns the statement that it needs no session, and the standard
  modules declare theirs the same way. Requests arrive normalized but your
  entries are compared literally, so write `/welcome` — a leading slash, no
  trailing slash, no query, fragment or `:param` segment. Those forms could
  never match a request, and `Flavor.build()` refuses them outright, in release
  as well as debug, rather than leaving you a dead entry. It refuses a
  well-formed path naming no route you registered, too. The request side stays
  forgiving: `/welcome/` and `/welcome?ref=email` both reach a declared
  `/welcome`. Matching is exact, never a prefix — declaring `/welcome` leaves
  `/welcome/admin` guarded, and `/welcome/:step` resolves per visit to a
  concrete path that matches no entry.
- **`publicPaths` skips every global redirect, not only the sign-in guard.**
  Today the sign-in guard is the only one, so the two readings coincide. If you
  contribute a `redirect` of your own on `ModuleRoutes`, it will not run for any
  declared public path — including `/`, `/auth/callback`, `/versions` and
  `/diagnostics`, which the standard modules declare and you cannot un-declare.
  Give a gate of your own an exemption list of its own rather than expecting
  `publicPaths` to describe it.
- An inactivity logout clears the session but does not navigate; a user is
  moved off a guarded screen only because the guard re-runs. On a path you
  declared public the guard does not run, so the screen stays exactly where it
  is with the session gone. Fine for a welcome page; think twice for anything
  that keeps rendering what the previous session loaded.
- Two kinds of redirect, one type. A `redirect` on `ModuleRoutes` is **global**:
  it judges every navigation in the app, not just your module's routes. A
  `redirect:` on a `GoRoute` is per-route, and a public path does not disable
  it — so declaring a per-server path public removes its sign-in bounce but not
  its connected-server check, which costs the return trip, since that guard
  bounces to a bare `/lobby` rather than to sign-in-and-come-back. Both are
  `GoRouterRedirect`, so nothing in the signature tells them apart; check where
  you are attaching it.
- `signedOutLandingPath` lands a signed-out launch on a screen of your own
  instead of the sign-in page. It sits on `standardFlavor` and
  `buildStandardKit`, and deliberately not on `standard()`: that function is
  the opinionated default, and a deployment choosing where a signed-out launch
  lands has already stepped past it. (A built-in public path would be a legal
  target, so this is a scope decision rather than a technical one.) **Declare that route
  public yourself** — this parameter says where to start, not that the
  destination is reachable, so a landing path no module declared bounces to
  sign-in the moment it arrives. It replaces only that one branch: an in-flight
  auth callback still finishes, and an already-connected stored server still
  opens the lobby. A server that needs no sign-in counts as connected, so such a
  deployment shows this screen on a fresh install and goes straight to the lobby
  on every launch after it has stored one. It means *every* signed-out launch,
  not only the first — for first-run-only, read your own onboarding flag before
  the call and pass `null` once it is set. The shell's `soliplex_has_launched`
  will not serve: it is install-freshness for the storage sweep, set on the
  first boot even if that boot never reached your screen. The path follows the
  same form rules as a public path, and must name a literal route one of your
  modules registers, not a concrete instance of a parameterized one like
  `/room/prod/123`. Both mistakes — a typo, and forgetting to declare the route
  public — are refused by `Flavor.build()` on **every** launch, not only the
  signed-out ones that would have been first to show them, because neither
  depends on the current auth state. So a developer whose machine has a
  connected server still finds out.

  **Give that screen its own way out.** The two rules compose into a trap: a
  landing path has to be declared public, and a public path runs no global
  redirect at all — so once the user has a session, nothing will move them off
  it. A welcome screen whose only exit was "the router will redirect me once
  sign-in completes" strands the user on it with a valid session, on every
  platform. Navigate explicitly, the way the built-in screens do:
  `context.canPop() ? context.pop() : context.go(AppRoutes.home)`.

  The same breadth is why a landing path must not carry a route-level
  `redirect:` of its own. Nothing validates that combination, and the two are
  contradictory claims: the declaration says "serve this without a session",
  the redirect says "do not serve this". What you get is your screen accepted
  at boot and silently skipped at runtime.
- Declaring a path public leaves your `initialRoute` untouched, so a cold launch
  lands where it did unless you also set `signedOutLandingPath`. On web a URL to
  a declared path opens it directly, because go_router prefers a non-`/`
  platform route over `initialLocation`; native deep links do not, since no
  platform in this repo enables Flutter deep linking.
- A module needs no `go_router` dependency of its own, in `dependencies` or in
  `dev_dependencies`. The barrel re-exports the routing types module authoring
  and module *testing* use — `GoRoute`, `GoRouter`, `GoRouterHelper`,
  `GoRouterRedirect`, `GoRouterState`, `NoTransitionPage` and `RouteBase` —
  plus `buildRouter`. That list is the types the module-authoring API's own
  signatures are written in, plus what a widget test needs to drive one. It is
  a curated surface, not the whole package: `ShellRoute`, `StatefulShellRoute`,
  typed routes and the rest are not there, and reaching for one means adding
  `go_router` directly. `GoRouterHelper` is the entry whose absence is
  invisible until it bites — Dart's `show` gates extensions, so without it
  `context.go` does not resolve. The others are there so you can *name* a type;
  Dart infers most of them without the name in scope, so you may never need
  some of them. If you already depend on
  `go_router` and a file of yours uses only what is listed here, the analyzer
  will report that import as `unnecessary_import` — a lint to delete rather
  than a problem to solve. Riverpod is not symmetrical: `ModuleRoutes.overrides` is
  `List<Override>`, `Override` comes from `flutter_riverpod`, and the barrel
  does not re-export it, so a module contributing overrides does need that
  dependency.
- Navigate with `context.go` / `context.push` — they take a path string, so
  every screen in the app is reachable from a module of yours without anything
  further being exported. Write the destination as a literal: `/` is the server
  list, which doubles as the sign-in entry and is what a "get started" button
  wants; `/lobby` is the room list once a server is connected. The route
  constants themselves are not exported, so paths that carry an encoded query —
  a room, a quiz, an auto-connect link — mean re-deriving both the shape and the
  escaping. If you need one of those, raise it rather than hand-rolling it.
