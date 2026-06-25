# ADR-002: Customizable BrandTheme via a Façade and a Lowering Buffer

- **Status:** Accepted
- **Date:** 2026-06-24
- **Authors:** Jaemin Jo
- **Supersedes:** —
- **Superseded by:** —

---

## Design Brief — what a brand controls

*A plain-language companion to the engineering sections below: when we
whitelabel this app for a brand, what can the design actually control, and what
stays fixed?*

A brand defines a small, safe set of choices — colors, fonts, corner roundness,
logo, and name — and the app builds a complete, accessible light **and** dark
theme from them. You don't hand-paint every screen; you set the brand's "DNA"
and the system grows the rest. The fastest path is a **single brand color**:
hand the system one accent and it produces both light and dark themes. From
there you specify as much as you want, up to fully hand-picked palettes.

### What a brand can control

| Area        | What you set                                                                 |
| ----------- | ---------------------------------------------------------------------------- |
| **Identity**| App name, and the logo (a light-mode logo, optionally a separate dark-mode one). |
| **Color**   | A core palette: the main brand color, a secondary, page background, text, a muted/subtle surface and its (muted) text, and borders. You set these **separately for light and dark mode**. |
| **Status**  | The four status *signal* colors (danger / success / warning / info), the error / destructive red (delete buttons, error borders), and all four soft banner surfaces (error / success / warning / info). |
| **Links**   | The hyperlink color.                                                         |
| **Type**    | Up to three typefaces: one for body text, one for headings/display, one for code. Plus fine adjustments (size, weight, spacing) on individual text styles. |
| **Shape**   | How rounded corners are — from fully rounded down to fully square — across four size steps. |

### What stays fixed (and why)

| Fixed thing | Why |
| ----------- | --- |
| **Spacing & layout rhythm** | The gaps, padding, and breakpoints are a structural grid, not brand expression. Letting them drift would break layouts at different screen sizes. |
| **Neutral surface shades** (cards, panels, input backgrounds, selected-row tints) | These neutral surfaces *host* your colored content. If we tinted them with the brand color too, your content would stop reading cleanly against them. They stay neutral on purpose. (The status *banner* surfaces — error / success / warning / info — are an exception: those carry meaning, so you can brand them.) |
| **Per-element fonts and per-element colors** | You pick *body / heading / code* typefaces — the body font also covers labels and buttons, so they can't take a face different from body. (You *can* still make labels/buttons larger, heavier, or more spaced per style.) That's a deliberate simplification, not a platform limit. Text color always comes from the palette, never baked into a text style — otherwise text wouldn't flip correctly between light and dark mode. |

Rule of thumb: **you control the brand's voice (color, type, shape, logo); the
system owns the spatial structure and the neutral scaffolding that keeps your
content legible.**

### Accessibility is built in

- Whenever the brand doesn't specify a text-on-color (e.g. the label color on a
  button), the system fills in a **soft near-black or near-white** (whichever is
  more readable, easier on the eyes than pure black/white), clearing the standard
  **4.5:1** ratio by construction. A brand can optionally tint these toward its
  own hue (§3.9).
- Light and dark are first-class. You design both; neither is an
  afterthought-inversion of the other.

When you leave a text-on-color unset, the system fills a soft near-black or
near-white (clearing 4.5:1) for these surfaces:

| Surface you set   | Text color it fills in | Where it shows                    |
| ----------------- | ---------------------- | --------------------------------- |
| primary           | onPrimary              | the label on a filled button      |
| secondary         | onSecondary            | text on a secondary surface       |
| tertiary          | onTertiary             | text / icon on a tertiary chip    |
| error             | onError                | the label on a destructive button |
| errorContainer    | onErrorContainer       | text in an error banner           |
| successContainer  | onSuccessContainer     | text in a success banner          |
| warningContainer  | onWarningContainer     | text in a warning banner          |
| infoContainer     | onInfoContainer        | text in an info banner            |

(Set any of these text colors yourself and your choice is used as-is instead.)
For the colors you set **by hand**, a pair below 4.5:1 (or below 3:1 for muted,
de-emphasized text) is **logged as a warning, not blocked** — your color is
still used, so you own the final call. The warning does not cover the status
*signal* colors (danger / success / warning / info); see §5.2 for why.

### Illustration: a single brand color

*(A brand supplying **one** custom color — not the Soliplex default, which
reproduces the full Soliplex look with nothing to set.)*

A new brand gives the system a single deep-blue color, and nothing else.

**What you get automatically:** deep-blue buttons with readable (white) labels,
in both light and dark mode; a full type scale in the default font; rounded
corners; your logo placed correctly, with a soft glow behind a light logo when
it lands on a dark background.

**What you'd still see as Soliplex defaults:** card and panel shades, the link
color, and the destructive-action red — because this brand set *only* one color.
The difference: the card/panel shades **can't** be rebranded (they're neutral by
design), whereas the link and the destructive red **can** — this brand just
didn't set them.

### What we need from a brand handoff

- App name + logo (light, and ideally a dark variant).
- Light-mode and dark-mode values for: primary, secondary, background, text,
  muted surface + its text, border. Optionally: the four status colors, a third
  accent, the link color, the error/destructive red, and the four status banner
  shades.
- Body / heading / code typefaces (and the font files, if not system fonts).
- Desired corner style (rounded → square).

Everything else, the system fills in. The trade-offs to know before adopting are
in §5 (Known Limitations); the deep decision record follows below.

---

## 1. Context and Problem Statement

`soliplex_frontend` is both a runnable app and a library that whitelabel forks
import. Forks need to restyle the app — colors, fonts, corner radii, logo, app
name — without forking the design system itself.

Before this change there was no customization contract. A fork's only lever was
`SoliplexBranding(accentLight, accentDark, …)`, which conflated two unrelated
concerns (who the app *is* vs. how it *looks*) and exposed a single accent. Three
structural problems blocked anything richer:

1. **No stable customization surface.** The only styling primitives were the
   internal `SoliplexColors` (a flat 41-slot palette) and the `ThemeData`
   factories. Exposing those directly would weld every fork to internal token
   names, so the design system could never refactor them.
2. **Status color was hardcoded.** `SymbolicColors` returned
   `Colors.red/green/orange/blue` from an extension on `ColorScheme`, which has
   no path back to the token system — so a brand could not recolor status.
3. **Some style escaped the theme.** App widgets read the global `soliplexRadii`
   constant and a platform monospace string directly, so a brand override would
   silently miss those call sites.

**The core question:** how does a fork express a brand without (a) touching
internal tokens, (b) reformatting JSON, or (c) silently shipping an inaccessible
or off-brand result?

---

## 2. Decision

Introduce a **public, frozen façade** (`BrandTheme`) made of plain Flutter types,
and map it onto the internal token system through a single private **lowering
buffer** (`lowerBrandTheme`). The façade is the only thing forks depend on; the
41-slot palette stays private and free to evolve behind the buffer.

```text
  Fork code
     │  BrandTheme (+ AppIdentity, FontResolver)   ← public, frozen contract
     ▼
  lowerBrandTheme(theme, brightness)               ← the buffer (private mapping)
     │  SoliplexColors (41 slots) + TextTheme + SoliplexRadii
     ▼
  ThemeData + SoliplexTheme extension              ← internal, free to evolve
```

The guiding invariant: **the shipped Soliplex look does not change.**
`BrandTheme.soliplex()` lowers to today's palette byte-for-byte, enforced by a
41-slot equality test (`brand_lowering_test.dart`).

The privacy boundary is the **`soliplex_frontend` barrel**: it re-exports only
the façade types and `lowerBrandTheme`. `soliplex_design` is an internal package
whose own barrel still exports `SoliplexColors`, so "the palette is private"
holds for forks that depend on `soliplex_frontend` (the expected dependency) —
not for code that reaches past it into `soliplex_design` directly.

---

## 3. The Decisions, by Axis

Each axis records the decision, its rationale, and — where one remains — the
residual risk it leaves (collected in §5).

### 3.1 Identity is split from theme

`SoliplexBranding` is replaced by **two orthogonal configs** so they can vary
independently:

| Config        | Owns                                  | Type location              |
| ------------- | ------------------------------------- | -------------------------- |
| `AppIdentity` | App name + logo widgets (light/dark)  | `lib/src/core/app_identity.dart` |
| `BrandTheme`  | Color, typography, shape              | `packages/soliplex_design/` |

`standard()` takes `{AppIdentity? identity, BrandTheme theme, FontResolver
fontResolver, …}`. `identity` defaults to `AppIdentity.soliplex` and `theme`
defaults to `const BrandTheme.soliplex()`, so the runnable app is unchanged.

`AppIdentity` carries `appName` and the brand's logo widgets (`logoLight`,
optional `logoDark`, optional `logoGlow`) — the same logo handling the former
`SoliplexBranding` provided, now separated from the theme. The one thing this
split adds is an `assert` that `logoGlow` and `logoDark` aren't set together
(`logoGlow` only tints the dark-mode fallback shown when `logoDark` is absent) —
the feature's only enforced cross-field invariant.

### 3.2 A constructor ladder, cheapest-first

`BrandTheme` offers four entry points, in increasing effort:

| Constructor                 | Use when                                    |
| --------------------------- | ------------------------------------------- |
| `BrandTheme.soliplex()`     | Default; the shipped look (a `const`).      |
| `BrandTheme.fromSeed(c)`    | One accent drives both brightnesses.        |
| `BrandTheme.fromAccents(…)` | A distinct accent per brightness.           |
| `BrandTheme(light:, dark:)` | Fully specified palettes.                   |

All four also accept the shared `typography`, `shape`, and `tint` axes (the last,
a `BrandTint`, governs on-color tinting — §3.9).

### 3.3 Color: a semantic role set, not the flat palette

`BrandColorScheme` exposes **7 required roles** (`primary`, `secondary`,
`background`, `foreground`, `muted`, `mutedForeground`, `border`) plus **19
optional** roles:

- `tertiary` and the `on*` colors (`onPrimary`, `onSecondary`, `onTertiary`);
- the four status *signal* colors (`danger`, `success`, `warning`, `info`);
- the error / destructive role (`error`, `onError`);
- the four soft status *surfaces*, each with its on-color
  (`errorContainer`/`successContainer`/`warningContainer`/`infoContainer`);
- `link`.

Colors flip per `Brightness`; typography, shape, and the on-color tint
(`BrandTint`, §3.9) are shared across both. Light and dark are authored as
**peers** — each brightness carries its own required
palette, and dark is never derived by inverting light, since a color readable on
white can vanish on a dark surface. New customization arrives as **additive
optional fields** — never new required ones — so widening the contract never
breaks an existing fork.

**Signal vs. role — the one naming pitfall.** Two reds coexist on purpose and
must not be confused:

| Role | What it tints | On-color |
| ---- | ------------- | -------- |
| `danger` | Inline status *signals* — status text, dots, "risky" icons on neutral surfaces. Read via `context.danger`. | none (it's foreground) |
| `error` | The *error / destructive* role — solid destructive buttons, input error borders; lowers onto Material `colorScheme.error`. | `onError` |

The field names follow **Material `ColorScheme` convention** (`error`/`onError`,
`errorContainer`/`onErrorContainer`, `successContainer`/`onSuccessContainer`) so
a Flutter developer can see exactly which scheme slot each one drives;
`destructive` (an Apple HIG term) was rejected for that reason. The cost — that
`error` reads as a near-synonym of `danger` — is carried by field docs that
state the signal-vs-role split explicitly. `link` follows the de-facto community
name (Material has no link slot).

### 3.4 Status color moves to a token-backed `BuildContext` extension

`SymbolicColors` moves from an extension on `ColorScheme` to one on
`BuildContext`. `context.{danger,success,warning,info}` now read the active
`SoliplexTheme.colors`, falling back to the default palette for the current
brightness when unthemed. The status values became real token slots
(`danger/success/warning/info`), pinned to the previously-hardcoded Material
colors. Filled status pills don't read these signals — they use the container
surfaces instead (§3.11).

### 3.5 Radii route through the active theme

A `context.radii` accessor resolves the active `SoliplexTheme` radii (falling
back to the default scale when unthemed). Every `BorderRadius.circular(soliplexRadii.x)`
call site moved onto it. `BrandShape` carries the four steps (`sm/md/lg/xl`)
with `.rounded()` (6/12/16/24), `.square()` (all 0), and `.custom()` (which
`assert`s its radii are non-negative).

### 3.6 Typography: three families, primitive deltas, no per-role family

`BrandTypography` exposes **three font families** — `bodyFamily`,
`displayFamily`, `codeFamily` — plus a `fallbacks` chain and per-role
`TypeScaleOverride` deltas (size/weight/height/letterSpacing). Per-role *color*
is **absent** because color comes from the palette — baking a color into a text
style would not flip with brightness (a dark-mode footgun). Per-role *family* is
**absent** for simplicity (family is one of the three roles); the body family
covers body, labels, and buttons. A per-role family is feasible but deliberately
omitted — not a platform limit. `codeFamily` lowers to the monospace token;
`context.monospace` reads it, falling back to the platform family when unthemed.

The shipped type scale was tuned against the default font's metrics, so the
per-role deltas double as the lever a fork uses to **re-tune the scale after
swapping in a face with different proportions** (see §5.4).

### 3.7 Fonts resolve through an injected seam

`FontResolver` keeps `soliplex_design` dependency-free. The default
`BundledFontResolver` performs no lookup — families declared in the consumer's
`pubspec.yaml` resolve through Flutter's native asset machinery (works offline /
airgapped). A fork wanting arbitrary fonts (e.g. `google_fonts`) injects its own
resolver at theme-build time. A family that is not bundled (or is misspelled)
falls back to the platform default with no load-time signal — Flutter resolves
font assets lazily, so the buffer cannot verify a family exists (see §5.4).

### 3.8 The default is frozen against token refactors

`BrandTheme.soliplex()` is a `const` constructor whose palette literals are
**inlined** (`_defaultLightColors` / `_defaultDarkColors`) rather than read from
`lightSoliplexColors` / `darkSoliplexColors`. This makes the public default both
const-constructible and immune to internal token renames — the contract a fork
sees is stable even if the internal palette is refactored.

### 3.9 Accessibility is checked at the boundary

`lowerBrandTheme` fills any unspecified `on*` color with `readableOn(...)`, then
**logs a warning** for any pair below its floor: **4.5:1** (AA) for the `on*`
pairs and body `foreground`/`background`, **3:1** for de-emphasized
`mutedForeground`/`muted`. `link` (no on-color) is checked against `background`,
and only when the brand sets it — so overriding `background` alone can't fault an
untouched link. The warning fires in **all build modes** but the color is used
as-is — a diagnostic, not a gate. So it fires only for hand-built pairs; the
exact checked set, and what is deliberately *not* checked, is in §5.2.

**`readableOn` is a softest-first cascade.** Instead of pure black/white it
prefers a soft **near-black `#212427`** (or **near-white `#FAFAFA`**), stepping
down to `#0A0A0A` and finally pure `#000000` only when a mid-tone surface would
drop the near-tone below AA. The pure tone is the guaranteed last rung, never
below ≈4.58:1 (its minimum, at the black/white crossover), so the loop can
always find a tone clearing AA — it never falls through to a sub-AA result. The
returned tone itself is only guaranteed ≥4.5:1: a near-tone is taken as soon as
it clears that floor, so a derived pair can sit right at 4.5. The cascade is
AA-safe by construction while reading softer on the eyes — pure black surfaces
only on an unusual mid-gray. `fromSeed` / `fromAccents` leave `onPrimary` unset
so the buffer derives it through this cascade.

**Optional brand tint (`BrandTint`).** A brand may tint those derived on-colors
toward a hue — `TintSource.surface` (tonal, the surface the on-color sits on) or
`TintSource.primary` (the brand primary) — at a `strength` saturation. The tint
is the cascade's top rung: if it would fall below AA it is dropped for the neutral
tone, so contrast stays guaranteed. Tinting is **opt-in** — the default `source`
is `TintSource.none`, so Soliplex and any brand that doesn't ask stay neutral —
and
is visible only on dark on-colors over light surfaces (near-white is too light to
carry a hue). An explicitly-set on-color is never tinted. When a brand does
enable tinting, `surface` at `strength` 0.08 is the recommended default;
`primary` gives a consistent house tint. (This was the one call originally left
for design review; it is resolved, and the defaults are plain constants, easy to
revisit.)

On-color derivation has **one rule**: `BrandColorScheme.fromAccent`, the
token-layer `SoliplexColors.fromAccent`, and the buffer all derive through
`readableOn`. The brightness-estimate helper `contrastingForeground` (tone
`#0A0A0A`) is reserved for decorative runtime tints — e.g. a hashed avatar
background — and never derives an on-color.

### 3.10 The "color from tokens" premise is enforced in CI

`test/design_system_hygiene_test.dart` fails the build on raw hex color literals
(`Color(0x…)`, `Color.fromARGB/RGBO`) or hardcoded Material status colors
(`Colors.red|green|orange|blue|yellow`) anywhere in `lib/`. If app code bakes in
color, a brand theme can't recolor it — so the test guards the whole premise.

### 3.11 Status-intent colors are sourced per component

`SoliplexBadge` / `SoliplexChip` resolve an `intent` to a
`(background, foreground)` pair from **two sources**, because the token system
models status *signals* and status *surfaces* separately (§3.3):

- **`neutral`** — the brand's neutral badge/chip theme.
- **`danger` / `success` / `warning` / `info`** — the brand's `errorContainer` /
  `successContainer` / `warningContainer` / `infoContainer` token pairs. Each is
  a soft status surface with its own readable on-color, so all four status pills
  are filled the same way and are independently brandable.

Consequence: a `danger` badge reads `errorContainer`, **not** `context.danger` —
a filled pill is a surface, and `danger` (a signal) has no on-color. Rebranding
the `danger` signal does not restyle a danger badge; rebrand `errorContainer` for
that. The same split holds for the other three status families.

### 3.12 Non-goals (deliberately fixed)

Spacing (`SoliplexSpacing`) and breakpoints (`SoliplexBreakpoints`) are **not**
customizable. They are layout invariants, not brand expression.

---

## 4. Lowering Semantics and Edge Cases

How `lowerBrandTheme` maps each input, including the corners:

| Input                          | Behavior                                                                 |
| ------------------------------ | ------------------------------------------------------------------------ |
| A specified role               | Overrides the per-brightness neutral base slot.                          |
| An unspecified optional role   | Falls back to the base palette slot — so the untouched palette stays byte-identical. |
| An unspecified `on*` color, sibling role **set** | Derived via the `readableOn` cascade (soft near-tone → pure), tinted per `BrandTint` — always ≥ 4.5:1. |
| An unspecified `on*` color, sibling role **unset** | Keeps the base on-color, so the untouched role stays byte-identical. |
| `codeFamily == null`           | Monospace token is `null`; `context.monospace` falls back to platform.   |
| `BrandShape.square()`          | **All** radii become 0 — including checkboxes and small hit-target wells.|
| `BrandTint.source == none` (default) | Derived on-colors stay neutral near-black / near-white. |
| `fromSeed` / `fromAccents`     | Brand `primary`; `onPrimary` derived (and tintable) at lowering; every other role stays neutral. |

---

## 5. Known Limitations

These are real and intentional, but a fork author must know them. Listed worst-first.

1. **The façade exposes 26 of the 41 internal slots; 15 neutral-scaffolding
   slots stay fixed.** A fork **cannot** set `primaryContainer`/`onPrimaryContainer`,
   `tertiaryContainer`/`onTertiaryContainer`, `accent`/`onAccent`,
   `outline`/`outlineVariant`, `inputBackground`, `hintText`, the four
   `surfaceContainer*`, or `inversePrimary`. These neutral surfaces stay pinned
   to the Soliplex defaults regardless of brand — by design: tinting a surface
   that hosts colored content distorts how that content reads. Consequence: even
   a fully-specified brand still inherits Soliplex-grey cards and inputs.
   (`link`, the `error`/destructive role, and all four status container surfaces
   **are** exposed — see §3.3.) Promoting a neutral slot would be an additive
   optional role (§3.3), but inherits the legibility risk above.

2. **The contrast warning is a diagnostic, not a gate, and deliberately
   partial.** It validates the `primary`/`secondary`/`tertiary` pairs, the
   `error` pair, the four status-container pairs, body `foreground`/`background`,
   and `mutedForeground`/`muted` (at the 3:1 floor), plus `link` against
   `background` (only when the brand sets `link`). It is logged in **all build
   modes**, but the supplied color is always used as-is — it never blocks a build.
   By design it does **not** check the `danger`/`success`/`warning`/`info`
   *signal* colors: they tint iconography on whatever surface a call site picks,
   so there is no single background to validate against, and checking against
   `background` would mostly raise false positives. The filled status pills go
   through the checked container pairs instead, so the high-traffic path is
   covered; a hand-picked signal illegible on a given surface is the fork's call.
   A development smoke alarm, not a release gate.

3. **The frozen default is hand-synced duplication.** `_defaultL*Colors` in
   `brand_theme.dart` duplicate values from the token constants. The byte-for-byte
   test is the tripwire that forces re-sync if they drift. Additionally,
   `fromAccent` bases its non-primary roles off the *inlined snapshot* while the
   buffer bases off the *live tokens* — identical today, but a latent split if
   the two ever diverge.

4. **Swapping a font silently re-tunes the type scale.** The shipped scale was
   tuned to the default font's metrics. A replacement face with a different
   x-height or default line height shifts vertical rhythm and visual hierarchy
   even though no size value changed. The per-role deltas (§3.6) are the lever to
   correct it, but nothing flags that correction is needed — a fork must review
   headings and body text after any font change. (Separately, an unbundled font
   family falls back to the platform default with no signal — §3.7.)

5. **Theme color transitions snap.** `SoliplexTheme.lerp` interpolates radii but
   not colors, so animating between two brand palettes is instantaneous. Not a
   concern for the brightness toggle (Flutter cross-fades the two `ThemeData`s),
   but live brand-swapping would not tween.

---

## 6. Consequences

**Positive**

- Forks depend only on `BrandTheme` / `AppIdentity` / `FontResolver`, all
  re-exported from the frontend barrel. The 41-slot palette can be refactored
  freely behind the buffer.
- The shipped look is provably unchanged (byte-for-byte test) and accessible
  on-colors are automatic.
- Identity and visual theme vary independently; status, radii, and monospace all
  flow from one source of truth.

**Negative / cost**

- A breaking migration for existing forks (see §7).
- The §5 limitations — chiefly the 15 fixed neutral slots — mean even a "full"
  brand keeps the Soliplex surface ramp (cards, inputs, selected-row tints).

---

## 7. Migration (BREAKING)

Done in the same release; forks update:

- `SoliplexBranding(accentLight, accentDark, …)` → `AppIdentity(…)` +
  `BrandTheme.fromAccents(light:, dark:)`.
- `colorScheme.danger` → `context.danger` (`SymbolicColors` moved from
  `ColorScheme` to `BuildContext`).

---

## 8. Alternatives Considered

| Alternative                                   | Why rejected                                                                 |
| --------------------------------------------- | ---------------------------------------------------------------------------- |
| Expose `SoliplexColors` directly to forks     | Welds forks to internal slot names; no room to refactor tokens.              |
| JSON / design-token file as the contract      | Stringly-typed, no compile-time safety, parsing/asset overhead; plain Dart types give IDE support and `const`. |
| Keep the single-accent `SoliplexBranding`     | Cannot express per-brightness palettes, type, or shape; conflates identity.  |
| Make spacing/breakpoints customizable too     | Layout invariants, not brand; YAGNI and a stability risk.                    |
