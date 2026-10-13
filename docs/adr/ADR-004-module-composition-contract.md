# ADR-004: The AppModule Composition Contract

- **Status:** Accepted (retroactive record of #172 and #536)
- **Date:** 2026-10-13
- **Authors:** William Karol Di Cioccio
- **Supersedes:** decision 2 of `docs/plans/0001-app-shell/proposal.md`
  (`ModuleContribution`, "no base class, no registry")
- **Superseded by:** —

---

## 1. Context and Problem Statement

Every screen in the app, and every screen a fork adds, reaches the user
through one seam: an `AppModule` contributes routes, Riverpod overrides, an
optional redirect and the paths it serves without a session, and
`ShellConfig.fromModules` lowers the list into one router and one root
`ProviderScope`. ADR-003 put a `Flavor` in front of that seam. It did not
record the seam's own rules.

Those rules were settled in two PRs, and their reasoning lives only in PR
bodies and long code comments:

- **#172** (`da882974`, 2026-04-24) replaced the original design. That design
  used plain module functions returning a `ModuleContribution` data class,
  with "no base class, no registry" and "no module lifecycle hooks". #172
  introduced the `AppModule` subclass with a namespace and an async
  `onDispose`, so that "shell teardown does not return while cached runtimes
  are still shutting down". `3780ecc0` made the caller, not the shell
  widget, own disposal.
- **#536** (`3cbc8efa`, 2026-09-02) moved the "needs no session" judgement
  from the auth module onto the module that registers each route. The old
  `_publicPaths` constant in `auth_module.dart` "declared four paths public,
  two of which belong to other modules. So the auth module owned a security
  judgement about screens it does not build." It also composed the redirect
  inside `ShellConfig`, made teardown run on every aborted build, and made
  teardown continue past a failing module.

The contract is what fork authors code against. Several of its failure modes
are silent: a router assembled by hand drops an in-flight sign-in with no
error, and a public path skips every global redirect. This ADR writes the
contract down so it can be changed deliberately.

## 2. Decision

A module is an `AppModule` subclass (`lib/src/core/app_module.dart`):

```dart
abstract class AppModule {
  String get namespace;        // unique per config; '' is exempt
  ModuleRoutes build();        // called once, in registration order
  Future<void> onDispose() async {}  // reverse order; may run without build()
}

class ModuleRoutes {
  final List<RouteBase> routes;
  final List<Override> overrides;
  final GoRouterRedirect? redirect;   // a global redirect
  final Set<String> publicPaths;      // bare paths of this module's own routes
}
```

`ShellConfig.fromModules` (`lib/src/core/shell_config.dart`) is the only place
modules are lowered. It is a compiler, not a constructor (ADR-003 §1.2).
Validation fails boot with a `ShellConfigurationError`, which the boot screen
shows verbatim. Shell-level behaviour belongs to the shell, and module authors
must not reassemble it. `Flavor.build()` is the blessed caller (ADR-003).

## 3. The Decisions, by Axis

### 3.1 A subclass with an identity and a lifecycle

`AppModule` exists because modules hold resources: a `ServerManager`, HTTP
clients and runtime caches. Those need an awaited teardown, which a data
class cannot express. The namespace is the module's identity in errors and
logs. Uniqueness is the only rule enforced on it. The empty namespace opts
out, for anonymous and test modules.

### 3.2 Build in registration order, dispose in reverse, never stop early

- `build()` runs once per module, in list order.
- `dispose` runs `onDispose` in reverse order. It continues past a throwing
  module, logs each failure under that module's namespace, and rethrows the
  first error. In the code's words: "stopping at the first one strands every
  module registered before it".

### 3.3 Any aborted build tears down every module

- If anything in `fromModules` throws, every module's `onDispose` is fired,
  including modules whose `build()` never ran. This covers the theme guard,
  duplicate namespaces, route validation, and a module's own `build()`.
- The reason: a rejected config otherwise left "a ServerManager, two HTTP
  clients, an inspector and a runtime manager live with nothing able to reach
  their onDispose" (#536).
- Consequence: `onDispose` must tolerate `build()`-created state being absent.

### 3.4 The caller owns disposal

`ShellConfig.dispose` is returned to the embedder. The shell widget never
calls it, "to honor the Flutter ownership rule (the widget receives the
config; it does not own it) and to avoid orphaned async work during widget
unmount, hot restart, or test teardown" (`3780ecc0`). A standalone app relies
on process exit.

### 3.5 One composed redirect: public paths bypass, then first non-null wins

`ShellConfig.redirect` is the only redirect a router may install:

1. If `matchedLocation` is a declared public path, it returns null. No global
   redirect runs. A route's own `GoRoute.redirect` still applies.
2. Otherwise it awaits each module redirect in registration order, and the
   first non-null result wins.

The individual module redirects are `@visibleForTesting`. Installing them
directly, or building a `GoRouter` from `ShellConfig.routes` by hand, skips
step 1 and silently discards an in-flight OIDC callback (comment in
`auth_module.dart`). `buildRouter(config)` is the supported assembly.

### 3.6 A public path is declared by the module that registers its route

- `publicPaths` entries must be bare paths: leading `/`, no trailing slash,
  no `?`, `#` or `:`.
- Each must name a route in the declaring module's own `routes`; nested
  routes count. `validateModulePublicPaths` (`lib/src/core/router.dart`)
  enforces this per module, because once routes are merged "the declaring
  module is no longer known".
- There is deliberately no flavor-level `extraPublicPaths`. It was
  implemented in #536 and removed, because it "would have extended that same
  centralisation to forks".
- Today the public paths are: auth `/` and `/auth/callback`; diagnostics
  `/diagnostics`; versions `/versions`.

### 3.7 Routes and boot targets are validated at boot

`fromModules` rejects:

- an empty route set;
- duplicate paths, after canonicalising parameters;
- a top-level path with no leading slash, which go_router accepts and then
  never matches;
- an `initialRoute` that is unregistered or parameterised;
- a `signedOutLandingPath` that is not a registered, declared-public bare path.

These checks run in release builds too.

### 3.8 Overrides compose into one root scope

All module overrides are flattened, in module order, into the single root
`ProviderScope`. Riverpod is the DI channel between modules and widgets
(ADR-001 §5.3). Modules share state by constructor injection from the
composition kit (`lib/src/flavors/standard_kit.dart`), not through each
other's providers.

## 4. Consequences

**Positive**

- A fork adds a screen by appending a module; it cannot accidentally open
  another module's route to unauthenticated users.
- Every aborted boot releases what modules were constructed with, and every
  failure surfaces on screen with the module named.
- The security-relevant statement "this route needs no session" sits next to
  the route it describes.

**Negative**

- Module order is semantics. It decides redirect priority and dispose order,
  yet nothing in `AppModule` expresses a dependency. "Composition is
  append-only … Room depends on Lobby" (`docs/authoring-a-flavor.md`) is
  prose; ADR-005 addresses the coupling behind it.
- A public path skips **every** global redirect, not only the sign-in guard.
  A fork's own gate (terms, maintenance mode) would be silently skipped on the
  four standard public paths. Fixing that changes the type of
  `ModuleRoutes.redirect`, so #536 deferred it to the next breaking change
  of this surface. No issue tracks it yet.
- A declared-public screen keeps rendering after a session ends, because an
  inactivity logout does not navigate. A landing screen needs its own exit.

**Enforcement**

| Rule | Pinned by |
| ---- | --------- |
| Namespace uniqueness, empty exempt | `test/core/shell_test.dart` |
| Dispose in reverse, continues past failure | `test/core/shell_test.dart`, `test/core/shell_config_test.dart` |
| Teardown on aborted build | `test/core/shell_config_test.dart` ("tears down the modules already built when one build() throws") |
| Shell widget never disposes | `test/core/shell_test.dart` |
| First non-null redirect wins | `test/core/shell_test.dart` ("first non-null redirect wins") |
| Public-path ownership and shape | `test/core/route_validation_test.dart`, `test/core/shell_config_test.dart` |
| Standard flavor's public surface | `test/flavors/standard_flavor_test.dart` ("the standard flavor serves exactly these paths without a session", "every path served without a session is actually reached") |
| Exactly one global redirect in the standard flavor (tripwire for the bypass gap) | `test/flavors/standard_flavor_test.dart` ("the sign-in guard is the only global redirect") |
| Module authoring against the barrel alone | `test/barrel_module_authoring_test.dart` |

## 5. Known Limitations and Open Questions

1. **Unpinned semantics.**
   - Build-call order and "build exactly once" are tested only indirectly.
   - A provider overridden by two modules is not checked; the original
     proposal assumed "last one wins silently".
   - An exception thrown by a module redirect has no defined handling.
2. **Namespace format.** Only uniqueness is validated, although `CLAUDE.md`
   says namespaces are "validated at startup".
3. **Dangling route references.** Route validation is structural. A module
   that navigates to another module's route (`AppRoutes.lobby`,
   `AppRoutes.diagnostics`) is not checked against the routes actually
   registered, so dropping a module leaves dead links. See ADR-005.
4. **Public-path matching is exact.** Percent-encoded variants never match, and
   a parameterised route cannot be public.
5. **`refreshListenable` ownership.** The standard kit's comes from the auth
   module, which disposes it. A fork-supplied one has no stated owner.
6. **Abort teardown is fire-and-forget.** It is not awaited, so the error can
   surface while modules are still tearing down.

## 6. Alternatives Considered

| Alternative | Why rejected |
| ----------- | ------------ |
| Plain functions returning `ModuleContribution` (original plan) | No place for awaited teardown of resources modules own; no identity for errors and logs. Replaced in #172 with "no deprecation layer". |
| `AppModuleContext` discovery surface | Not introduced in #172: "no unused surface". Modules share state by constructor injection instead. |
| Auth module holds the public-path list | Auth made a security judgement about screens it does not build, and a custom module could not add one at any position (#536). |
| Flavor-level `extraPublicPaths` | Implemented and removed in #536: it would extend the same centralisation to forks. |
| Expose module redirects for routers to install | A router that does so silently drops an in-flight sign-in. The composed `redirect` is the only one exposed for production use. |
| Shell widget disposes the config on unmount | Breaks Flutter ownership and orphans async work on hot restart and in tests (`3780ecc0`). |
| Stop teardown at the first failing module | Strands every module registered before it. |
