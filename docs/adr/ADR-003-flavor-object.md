# ADR-003: Reify the Flavor — a Declaration Object Between Composition and Boot

- **Status:** Proposed
- **Date:** 2026-07-16
- **Authors:** William Karol Di Cioccio
- **Supersedes:** —
- **Amends:** ADR-002 §2 (records the barrel-boundary change shipped in #426)
- **Superseded by:** —

---

## 1. Context and Problem Statement

Issue #418 and its follow-up #421 pushed us to open the theming system to
forks that need full token control. PR #426 delivered the agreed mechanism —
`buildStandardModules` (the composition kit), the direct
`buildSoliplexThemeData` path re-exported through the frontend barrel, and a
boot-time guard for the `SoliplexTheme` extension. Each piece is sound. But
stacking them exposed that the layer they all lean on was never designed —
it accreted. This ADR records the current shape, names its problems, and
proposes the missing concept before #426's surface becomes API that forks
depend on.

### 1.1 The hierarchy as shipped (post-#426)

```text
TOKENS       SoliplexColors (40 slots) · SoliplexRadii · typography
                  │
THEME        buildSoliplexThemeData(colors, brightness) ─► ThemeData
                  ▲                                        + SoliplexTheme ext
                  │
BRAND        BrandTheme ── lowerBrandTheme() ──┘   (curated path, ADR-002)

IDENTITY     AppIdentity (appName, logos, glow)

FEATURES     AppModule ── build() ─► ModuleRoutes (routes, overrides, redirect)

COMPOSITION  buildStandardModules(identity, backend knobs)        ← new in #426
             ─► StandardModules record:
                (modules, refreshListenable, initialRoute,
                 inactivity, serverManager)

"FLAVOR"     standard() — a bare Future<ShellConfig> function

BOOT         ShellConfig.fromModules(…) — flattens routes/overrides/redirects,
             guards the theme extension, owns dispose
                  │
SHELL        runSoliplexShell(config) ─► ProviderScope + MaterialApp.router
```

The theme column is clean: two public entry points (curated `BrandTheme`,
direct `SoliplexColors`) converging on one funnel that attaches the extension
and runs the contrast check. The problems are all in the two rows between
COMPOSITION and BOOT.

### 1.2 The problems

1. **"Flavor" is a calling convention, not a thing.** A flavor is whatever a
   `Future<ShellConfig>` function happens to do. The assembly ritual — pick an
   identity, lower the brand twice, thread `identity.appName` into a string
   slot, forward four kit fields into `ShellConfig.fromModules` — is
   copy-pasted into every author's function. `docs/authoring-a-flavor.md`
   documents the ritual honestly, and that is the tell: five lines of pure
   plumbing that every fork must transcribe, each line failable. Forget
   `refreshListenable` and auth-driven redirects silently stop re-evaluating;
   forget `initialRoute` and the OAuth callback breaks.

2. **`StandardModules` is the missing concept's torso, anonymized.** A
   five-field typedef record with no behavior: "a flavor minus identity minus
   theme," as loose values. `serverManager` — an escape hatch for custom
   modules — sits at the same level as boot-critical fields.

3. **`ShellConfig` is two things wearing one name.** Simultaneously the
   *declaration* of an app (name, themes, mode, modules in) and the *lowered
   boot artifact* (routes/overrides/redirects flattened, dispose closure out).
   `fromModules` is not a constructor; it is a compiler. Because the
   declaration has no home of its own, every upstream layer pours parameters
   into it.

4. **Field duplication across layers, resolved by hand.** `appName` lives on
   `AppIdentity` *and* `ShellConfig`, threaded via `identity.appName` at every
   call site. `InactivityConfig` is built inside `buildStandardModules` from
   two `Duration` knobs yet is also a `ShellConfig` field with its own
   default. `themeMode` rides on `ShellConfig` next to already-lowered
   `ThemeData`.

5. **#426's theme guard landed at the wrong layer — because the right layer
   does not exist.** `ShellConfig.fromModules` (core, module composition) now
   imports `soliplex_design` to check for the `SoliplexTheme` extension.
   Failing at boot instead of in the first branded widget is correct; but
   "is this theme valid" is a theme-boundary rule that ended up in the module
   coordinator because that is the only chokepoint the current shape offers.

6. **Even the directory names disagree.** `src/composition/` and
   `src/flavors/` are two names for the same missing idea — composition *is*
   flavor-making — and the `flavors.dart` barrel now exports a function plus
   a kit, a grab-bag shape.

### 1.3 Amendment to ADR-002, recorded

ADR-002 §2 fixed the `soliplex_frontend` barrel as the privacy boundary
("re-exports only the façade types"), and §8 rejected *"Expose
`SoliplexColors` directly to forks"* outright. The #418/#421 discussion
deliberately revised that call — a fork whose brand needs slots the façade
does not carry has no other path, and the curated contract remains the
default — and #426 implemented it by re-exporting `SoliplexColors`,
`buildSoliplexThemeData`, and the default palettes from the barrel. This ADR
records that amendment so ADR-002 does not read as silently violated:
**the barrel now carries two tiers — the curated façade (unchanged, still
recommended) and the full-control tier (explicitly opt-in, welded to token
names by choice).** The §8 rejection stands for the *default* path only.

---

## 2. Decision

Introduce a **`Flavor` value object** — the complete declaration of an app
variant: who it is (`AppIdentity`), how it looks (`FlavorTheme`), what it does
(`List<AppModule>`), and how it boots (route, refresh, inactivity) — with a
single `build()` that owns the lowering ritual once:

```text
AppIdentity + FlavorTheme + modules + boot knobs
        └───────────────── Flavor ─────────────────┘
                      │ build()      ← owns: appName threading, brand lowering,
                      ▼                theme guard, kit-field forwarding
                 ShellConfig         ← narrows toward a pure boot artifact
                      ▼
               runSoliplexShell
```

`FlavorTheme` is the theme half: one slot wrapping the two public theming
paths (`FlavorTheme.brand(BrandTheme, …)`, lowered lazily at build; or
`FlavorTheme.themeData(light:, dark:)` for full token control), and it owns
`themeMode` — brightness policy travels with the themes it selects between.

`standard()` keeps its exact signature and becomes a thin wrapper:
`standardFlavor(...)` builds the standard `Flavor`; `standard()` is
`(await standardFlavor(…)).build()`. A fork customizes by **composing a
value**, not re-implementing assembly:

```dart
// Full color control + an extra module — no hand-carried kit fields.
final flavor = await standardFlavor(
  identity: myIdentity,
  theme: FlavorTheme.themeData(light: myLight, dark: myDark),
  extraModules: (kit) => [MyModule(kit.serverManager)],
);
runSoliplexShell(await flavor.build());
```

---

## 3. The Decisions, by Axis

### 3.1 `Flavor` is an immutable value with `copyWith`, not a builder

Flavors are configuration, and configuration wants value semantics: cheap to
construct (`const`-friendly), cheap to derive (`copyWith`), inert until
`build()`. A builder or subclass-per-flavor invites state and ordering
concerns the domain does not have. Deep forks that want a named flavor still
just write a function — one that *returns a `Flavor`*, so the assembly ritual
stays owned by `build()`.

### 3.2 `FlavorTheme` holds the theme *source*, lowered at build time

Holding `BrandTheme` (not pre-lowered `ThemeData`) keeps flavor construction
synchronous and `const`-able, defers the lowering cost until it is needed
exactly once, and gives `build()` a single place to guarantee both
brightnesses are lowered with the same resolver and classifications — a pair
of calls every flavor function currently duplicates. The `themeData` variant
exists because the full-control tier (§1.3) hands us `ThemeData` directly.

### 3.3 `standardFlavor()` and the `extraModules` seam

`standardFlavor` converts the composition kit into a `Flavor`, absorbing the
kit-field forwarding that `docs/authoring-a-flavor.md` currently asks authors
to transcribe. Custom modules usually need shared state (`serverManager`), so
the seam is a callback receiving the kit —
`List<AppModule> Function(StandardModules kit)` — rather than a plain list.
`buildStandardModules` stays public for compositions that diverge further.

### 3.4 `standard()` is compatibility-frozen

Signature unchanged; implementation delegates. Existing callers (including
`main.dart`) compile and behave identically. This is also the correctness
proof: the entire shipped app boots through the new path.

### 3.5 `ShellConfig` narrows but stays public, for now

With `Flavor.build()` as the blessed assembly point, `ShellConfig` should
tend toward an internal boot artifact. It stays public in this change —
`runSoliplexShell` takes it, deep embedders construct it, and #426's doc
teaches it — but new capability should land on `Flavor`, not on
`ShellConfig.fromModules`'s parameter list.

### 3.6 The theme guard's eventual home

The `SoliplexTheme`-extension guard stays in `ShellConfig.fromModules` in
this change (moving it would alter #426's semantics for direct callers). Its
natural home is the theme boundary — `FlavorTheme.themeData` can validate at
construction, failing even earlier with the same message. Deferred until the
`Flavor` shape is accepted.

---

## 4. What Does Not Change

- The two theming tiers and their semantics (curated `BrandTheme` path,
  direct `SoliplexColors` path), including #426's contrast check and guard.
- `buildStandardModules` / `StandardModules` — the kit remains the
  composition layer; `Flavor` sits on top of it, not instead of it.
- `runSoliplexShell(ShellConfig)` and the shell widget tree.
- The shipped Soliplex app's behavior, byte for byte.

---

## 5. Known Limitations and Open Questions

1. **Naming.** `Flavor` collides with the informal use of "flavor" for the
   functions themselves; alternatives: `FlavorSpec`, `AppVariant`,
   `SoliplexApp`. `FlavorTheme` could be `ThemeSource`. Bikeshed explicitly
   before accepting.
2. **`appName` duplication survives** (§1.2 #4): `Flavor.build()` threads
   `identity.appName` into `ShellConfig.appName`, hiding the duplication
   rather than removing it. Removing it means `ShellConfig` taking
   `AppIdentity` — a breaking change deferred with §3.5.
3. **`copyWith` cannot unset** nullable fields (`refreshListenable`) — the
   standard Dart limitation; acceptable for a declaration type.
4. **The kit's `serverManager` escape hatch** is still a concrete type on a
   record; if custom modules need more shared state, the record grows. A
   future `FlavorContext` interface may age better; not needed yet.

---

## 6. Consequences

**Positive**

- Flavor authoring drops from a transcribed ritual to a composed value; the
  failure modes in §1.2 #1 become unrepresentable.
- The public API gains the concept users already talk about ("the standard
  flavor", "your fork's flavor") as a type the IDE can show them.
- `ShellConfig` stops accreting parameters; the guard and lowering logic get
  a single owner; `themeMode` rejoins the theme.
- ADR-002's amended boundary is written down (§1.3) instead of implicit in a
  PR diff.

**Negative / cost**

- One more public type to document and keep stable.
- Two blessed ways to reach `ShellConfig` during the transition (direct
  `fromModules`, and `Flavor.build()`); mitigated by §3.5's "new capability
  lands on `Flavor`" rule.
- `docs/authoring-a-flavor.md` and the barrels need a follow-up edit once
  accepted (kept out of the sketch to avoid churning #426's content).

---

## 7. Migration

None breaking. `standard()` callers are untouched. #426's
`buildStandardModules` consumers may adopt `standardFlavor` incrementally.
Doc and CHANGELOG updates follow acceptance, not the sketch.

---

## 8. Alternatives Considered

| Alternative | Why rejected |
| ----------- | ------------ |
| Keep the function convention (status quo) | The assembly ritual stays copy-pasted and failable in every fork; the concept keeps living in a doc instead of the type system. |
| Fatten `ShellConfig` (add identity, brand, kit fields) | Deepens the declaration/artifact conflation (§1.2 #3); every new axis lands as another `fromModules` parameter. |
| A builder (`FlavorBuilder…build()`) | Mutable staging for what is plain configuration; value semantics + `copyWith` express derivation ("standard, but…") more directly. |
| Sealed class hierarchy for the theme source | Two variants do not justify pattern-matching ergonomics over two named constructors; revisit if a third source appears. |
| Fold the kit into `Flavor` (kill `StandardModules`) | The kit is genuinely a lower layer — module graph wiring — and #426 just extracted it cleanly; re-fusing it would undo that separation. |
