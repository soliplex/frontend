---
name: adopt-design-system
description: >-
  Use when a whitelabel fork or downstream deployment has its own hand-rolled
  theming — a custom ThemeData/ColorScheme, hex color literals, magic
  spacing/radii, raw Material widgets, or font-family strings — and wants to
  adopt soliplex_design tokens, branded components, and per-flavor
  SoliplexBranding (light/dark accents, logo, app name). Triggers: "adopt the
  design system", "migrate our fork to soliplex_design", "whitelabel branding",
  "replace our custom theme", "switch to Soliplex tokens".
---

# Adopt the Soliplex design system

Guides a whitelabel fork from a hand-rolled UI to `soliplex_design`: brand
identity flows through one `SoliplexBranding`, and every screen consumes
tokens and branded components instead of literals and raw Material widgets.

The design system is the single source of truth (`packages/soliplex_design/`,
documented in `packages/soliplex_design/README.md`). **Read that README first**
— it has the full accessor cheat sheet and component inventory this skill
abbreviates. The branding API and light/dark theme split were introduced in
PR #261 (`feat(branding): whitelabel branding API + light/dark theming`).

## When to use

A fork has any of: a custom `ThemeData`/`ColorScheme`, `Color(0x...)` literals,
`Colors.red`-style status colors, magic `EdgeInsets`/`SizedBox` numbers, raw
`BorderRadius.circular(N)`, `TextStyle(fontSize:)`, `fontFamily:` strings, or
raw `FilledButton`/`TextField`/`Chip`-family widgets where a `SoliplexX`
wrapper exists. The goal is to delete all of that and route it through the
design system.

## Step 1 — Audit

Run the bundled scanner against the fork's UI (default target `lib`):

```bash
.claude/skills/adopt-design-system/audit.sh lib
```

It reports every hard-rule candidate as `file:line:match` and exits non-zero
when any are found. The scanner over-reports by design — treat each hit as
something to review, not an automatic defect. The spacing/breakpoint section
is advisory because token values and raw numbers look alike; those need human
eyes.

Group the findings by rule before editing so the migration is systematic, not
file-by-file whack-a-mole.

## Step 2 — Migrate the violations

Import the barrel once per file: `import 'package:soliplex_design/soliplex_design.dart';`

| Found | Replace with |
| --- | --- |
| `Color(0x...)`, `Color.fromARGB/RGBO` | `Theme.of(context).colorScheme.<token>` or `SoliplexTheme.of(context).colors.<token>` |
| `Colors.red/green/orange/blue/yellow` (status) | `colorScheme.danger \| success \| warning \| info` (via `SymbolicColors`); for a *container* surface use `errorContainer`/`onErrorContainer` (or `colors.successContainer`/`onSuccessContainer`) |
| Destructive action color | `colorScheme.error` / `errorContainer` — never red hex |
| `EdgeInsets`/`SizedBox` magic numbers | `SoliplexSpacing.{s1=4, s2=8, s3=12, s4=16, s6=24}` — there is **no s5**; use `s6` for 24, never reach for 20 |
| `BorderRadius.circular(N)` | `SoliplexTheme.of(context).radii.{sm=6, md=12, lg=16, xl=24}` — default `md`; `sm` only for checkboxes/small wells |
| `TextStyle(fontSize:)` / bare `fontSize:` in `copyWith` | start from `Theme.of(context).textTheme.<style>` and `copyWith` only the delta |
| `fontFamily: 'monospace' \| 'Roboto Mono' \| 'SF Mono' \| 'Menlo'` | `context.monospace` |
| Hardcoded width breakpoint | `SoliplexBreakpoints.{mobile=320, tablet=600, desktop=840}` |
| `FilledButton`/`OutlinedButton`/`TextButton` | `SoliplexButton.{filled,outlined,text}` with `intent: ButtonIntent.{primary,danger}` |
| `Chip`/`ActionChip`/`FilterChip` | `SoliplexChip` (display), `.action`, `.filter` |
| `TextField`/`TextFormField` | `SoliplexInput` |
| `DropdownMenu<T>` | `SoliplexDropdown<T>` |
| `showDatePicker`/`showTimePicker` ad-hoc wiring | `SoliplexDatePickerField` / `SoliplexTimePickerField` (or `showSoliplexDatePicker()` / `showSoliplexTimePicker()`) |
| inline status pill | `SoliplexBadge(label, intent, icon)` |

Available text styles: `headlineMedium, titleLarge, titleMedium, titleSmall,
bodyLarge, bodyMedium, bodySmall, labelMedium, labelSmall`. Raw Material
widgets are fine when no Soliplex wrapper exists — they still pick up the brand
`ThemeData`.

**Never add a token to make a value fit.** If a value is genuinely missing,
stop and raise it in the PR — do not invent a token or keep the literal.

## Gotchas from real adoption sweeps

These cost time during the first-party sweeps; check them as you go.

- **`SoliplexTheme.of(context)` throws under bare `ThemeData`.** It resolves
  the extension with `!`, so a widget pumped in a test (or hosted) on a plain
  `MaterialApp` with no Soliplex theme crashes. Either pump a real
  `soliplexLightTheme()`/`soliplexDarkTheme()` in tests, or — for a widget that
  *must* survive bare `ThemeData` — read the const `soliplexRadii` token
  directly instead of `SoliplexTheme.of(context).radii`. (`ClassificationTheme.of`
  is the deliberate null-safe exception: it returns a fallback.)
- **Long label + leading icon overflows a constrained pill/row.** A `Row` with
  an icon and a `Text` will throw `RenderFlex overflowed` when the label is
  long and the parent is width-bounded. Wrap the label in `Flexible` so it
  wraps instead of truncating; a loose fit keeps the natural size when
  unbounded, so short labels are unaffected.
- **Golden text renders as placeholder boxes.** That is Flutter's test font,
  not a regression. After an *intentional* visual change, regenerate with
  `flutter test --update-goldens` and eyeball the PNG diff; never update
  goldens to paper over an unexplained change.
- **The spacing scale skips `s5`.** It steps `s4` (16) → `s6` (24); there is no
  20. The only sanctioned off-scale padding in the whole codebase is the chat
  bubble's `14/10` — do not introduce new exceptions.
- **`SymbolicColors` are single shades, and arrive with the barrel import.**
  `colorScheme.danger/success/warning/info` are flat colors. A status surface
  that needs a *container* tone uses `errorContainer`/`onErrorContainer` (or
  `colors.successContainer`/`onSuccessContainer`) — not the symbolic shade.
- **A `textTheme` style already carries a color.** When you `copyWith` from one
  onto a surface with different contrast, override `color:` explicitly — don't
  assume the base is neutral.
- **Use `withAlpha(N)`, not `withOpacity`.** `withOpacity` is deprecated;
  `flutter analyze` flags it, and the CI gate is zero warnings.

## Step 3 — Wire the branding

Replace the fork's custom `ThemeData` with one `SoliplexBranding`, then let the
standard flavor build both themes from it. `SoliplexColors.fromAccent` derives
`primary` (and a readable `onPrimary`) from the accent only — every neutral
surface, container tone, and status color stays Soliplex, so the platform
identity survives the rebrand.

```dart
final branding = SoliplexBranding(
  accentLight: const Color(0xFF1B5E20), // brand accent — light theme
  accentDark: const Color(0xFF66BB6A),  // brand accent — dark theme
  appName: 'Acme Workspace',
  logoLight: Image.asset('assets/acme/logo.png', width: 64, height: 64),
  // logoDark optional: when omitted, BrandLogo wraps logoLight in a
  // SoliplexGlow halo so a dark-on-light mark stays legible on dark surfaces.
);

final config = await standard(
  branding: branding,
  themeMode: ThemeMode.system,
  // classifications: ...  // optional, only if the deployment marks rooms
);
```

The hex literals in `accentLight`/`accentDark` are the **one** sanctioned place
for raw colors in consumer code — a brand accent has no token by definition.
Everything downstream of `branding` must stay token-driven.

## Step 4 — Verify

Run from the fork root and resolve everything before opening the PR:

1. `dart format .` (or `mcp__dart__dart_format`)
2. `flutter analyze` — **zero** warnings (or `mcp__dart__analyze_files`)
3. `flutter test --reporter failures-only` — fix any golden/widget drift
4. Re-run `audit.sh lib` — the sanctioned brand-accent hex is expected; review any other hits
5. `markdownlint-cli2 "**/*.md" "#node_modules"` if any `.md` changed

Then walk the adoption checklist (also in `packages/soliplex_design/README.md`):

- [ ] Colors from `colorScheme`/`SoliplexTheme`, not hex (accent excepted).
- [ ] Padding from `SoliplexSpacing`; radii from `radii`; text from `textTheme`.
- [ ] Monospace via `context.monospace`; status via `SymbolicColors`.
- [ ] Branded `SoliplexX` wrapper used wherever one exists.
- [ ] Screen behaves at all three `SoliplexBreakpoints`.
- [ ] Both light and dark palettes look correct.
- [ ] Destructive actions use `colorScheme.error`; never red hex.

For live visual review, run the component gallery
(`packages/soliplex_design/example/`, `flutter run`) or skim the golden
snapshots under `packages/soliplex_design/test/components/*/goldens/`.
