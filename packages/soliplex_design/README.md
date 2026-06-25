# soliplex_design

The **single source of truth** for color, type, spacing, radii, breakpoints,
and the core component library in the Soliplex Flutter stack. Consumed by
`soliplex_frontend` and any whitelabel app embedding it; everything under
`lib/src/modules/` in the frontend must consume tokens from here — no hex
literals, no magic padding numbers, no hardcoded font sizes or families — and
prefer the branded components below over raw Material widgets for any
interactive surface that has a Soliplex equivalent.

The canonical reference (with swatches, type specimens, and component demos) is
[`design_system/`](../../design_system/). Open
`design_system/Soliplex Design System.html` in a browser to verify a new screen
matches. A runnable gallery of every component variant lives in
[`example/`](example/) — `flutter run` it for live visual review, or skim the
golden snapshots under
`test/components/*/goldens/` for a static reference.

## Accessor cheat sheet

| What                  | How                                                                                                  |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| Color                 | `Theme.of(context).colorScheme.<token>` or `SoliplexTheme.of(context).colors.<token>`                |
| Status color          | `context.{danger,success,warning,info}` (via `SymbolicColors` on `BuildContext`)                     |
| Spacing               | `SoliplexSpacing.s1` (4) / `s2` (8) / `s3` (12) / `s4` (16) / `s6` (24)                              |
| Radius                | `context.radii.{sm,md,lg,xl}` — default is `md` (12 px)                                              |
| Text style            | `Theme.of(context).textTheme.{headlineMedium,titleLarge,titleMedium,titleSmall,bodyLarge,bodyMedium,bodySmall,labelMedium,labelSmall}` |
| Monospace             | `context.monospace` — picks `SF Mono` on Cupertino, `Roboto Mono` elsewhere                          |
| Breakpoints           | `SoliplexBreakpoints.{mobile,tablet,desktop}` (320 / 600 / 840)                                      |

> The `SymbolicColors` entries are single shades. For errors **with** a
> container surface use `colorScheme.errorContainer` / `onErrorContainer` —
> not the symbolic `danger`. For success **with** a container surface use
> `SoliplexTheme.of(context).colors.successContainer` / `onSuccessContainer`.

Import the whole surface via:

```dart
import 'package:soliplex_design/soliplex_design.dart';
```

## Components

Six families ship under the package barrel. Every interactive component family
shares a small, consistent axis vocabulary so the same mental model carries
across the library:

- `intent` — semantic role. Buttons take an *action* gradient
  (`primary`, `danger`); badges and chips take a *status* gradient
  (`neutral`, `info`, `success`, `warning`, `danger`).
- `isLoading` — interactive components only. Disables taps and shows a
  spinner *in the existing slot* so the widget's measured size doesn't
  shift between idle and loading states.
- `enabled` — disables interaction without painting a spinner.

| Family                          | Constructors                                    | Replaces                                            | Key axes                              |
| ------------------------------- | ----------------------------------------------- | --------------------------------------------------- | ------------------------------------- |
| `SoliplexButton`                | `.filled`, `.outlined`, `.text`                 | `FilledButton`, `OutlinedButton`, `TextButton`      | `intent`, `isLoading`, `isCompact`, `icon`, `iconAlignment`, `alignment` (text) |
| `SoliplexBadge`                 | default                                         | inline status pills (not Material's positional `Badge`) | `intent`, `icon`                  |
| `SoliplexChip`                  | default (display), `.action`, `.filter`         | `Chip`, `ActionChip`, `FilterChip`                  | `intent`, `selected`, `onDeleted`     |
| `SoliplexInput`                 | default                                         | `TextField` / `TextFormField`                       | `isPassword` (eye toggle), `isLoading`, validation |
| `SoliplexDropdown<T>`           | default                                         | `DropdownMenu<T>`                                   | `isLoading`, generic `T` end-to-end   |
| `SoliplexDatePickerField`       | default + `showSoliplexDatePicker()` function   | `showDatePicker` + ad-hoc field                     | `isLoading`, `firstDate`, `lastDate`  |
| `SoliplexTimePickerField`       | default + `showSoliplexTimePicker()` function   | `showTimePicker` + ad-hoc field                     | `isLoading`                           |

**Rule of thumb**: reach for the branded wrapper whenever you'd reach for the
Material widget it replaces. Skip it only when the Material widget genuinely
has no Soliplex equivalent (e.g., a `Slider`) — in which case the raw widget
still picks up Soliplex `ThemeData` automatically.

The wrappers are intentionally thin: each delegates rendering to its Material
counterpart so any `ThemeData` override the host app sets still applies.

## Customizing the theme (BrandTheme)

`BrandTheme` is the public, stable customization contract — plain Flutter types,
no JSON. A flavor or whitelabel fork builds one and `standard()` lowers it to
`ThemeData` via `lowerBrandTheme(theme, brightness)`. The internal token system
(`SoliplexColors`, `SoliplexRadii`, the `TextTheme`) stays private behind that
boundary and can evolve without breaking the contract.

Constructor ladder, least → most change:

- `const BrandTheme.soliplex()` — the shipped look, pinned to today's literals.
- `BrandTheme.fromSeed(seed)` — derive light and dark palettes from one accent.
- `BrandTheme.fromAccents(light:, dark:)` — a distinct accent per brightness.
- `BrandTheme(light:, dark:, typography:, shape:, tint:)` — fully specified.

Each accepts optional `BrandTypography` (body/display/code font families,
fallbacks, per-role `TypeScaleOverride` deltas), `BrandShape` (`rounded()` /
`square()` / `custom()` radii), and `BrandTint` (opt-in on-color tinting; see
below). Colors come from `BrandColorScheme` — seven
required roles plus optional `tertiary`; the `on*` slots; the status *signal*
colors (`danger`/`success`/`warning`/`info`); the error/destructive role
(`error`/`onError`); the four soft status surfaces with their on-colors
(`errorContainer`/`successContainer`/`warningContainer`/`infoContainer`); and
`link`. Field names follow Material
`ColorScheme` convention. An unset role falls back to the base palette and an
unset `on*` color gets a soft near-black (`#212427`) / near-white (`#FAFAFA`)
foreground — a cascade that escalates to pure black/white only when a mid-tone
surface needs it — so derived colors always clear AA. An `on*` color you set
explicitly is used as-is — its legibility is your call — and a sub-AA pair (the
`on*` pairs, `foreground`/`background`, and `link` against `background` when you
set `link`), or `mutedForeground`/`muted` below 3:1, is logged as a warning.
Links also render on neutral surfaces beyond `background`; verify those
contrasts yourself.

**On-color tint (`BrandTint`).** By default derived on-colors are neutral. Set
`tint: BrandTint(source: TintSource.surface | primary, strength: 0.08)` to nudge
them toward the surface's hue (tonal) or the brand primary. It's opt-in
(`TintSource.none` by default), contrast-guaranteed (a tint that would fall
below AA is dropped), and visible only on dark on-colors over light surfaces.

**`danger` vs `error` — two reds, distinct roles.** `danger` is the inline
status *signal* (`context.danger`: badges, status text — no fill); `error` is
the destructive *action* role (delete buttons, error borders; lowers to
`colorScheme.error`). Set them — and the `errorContainer` surface — together to
keep error styling coherent.

Fonts resolve through a `FontResolver`. The default `BundledFontResolver` trusts
native asset fonts (offline-safe, no extra dependencies); a fork wanting
arbitrary fonts (e.g. `google_fonts`) implements `FontResolver` in its own app
and injects it at `standard(fontResolver: ...)`. A font family that isn't
registered — a typo, or a missing `pubspec.yaml` entry — falls back silently to
the platform default, so verify your fonts actually render. App identity
(`AppIdentity` — name + logos) is a separate config from the theme.

The bundled resolver is airgap-safe and does not load fonts. A `google_fonts`-backed resolver
loads fonts asynchronously; the app should await font readiness in `main()` before
`runApp()` (e.g. `await GoogleFonts.pendingFonts()`) to avoid a flash of fallback
text. An unresolved or misspelled font family falls back to the platform default
with no load-time error — Flutter resolves fonts lazily at render time — so confirm
custom fonts actually display by visual inspection.

### What is customizable vs fixed

| Surface | Customizable? | How |
| --- | --- | --- |
| Colors (7 roles → full palette) | ✅ | `BrandColorScheme` |
| Status signals (danger/success/warning/info) | ✅ | `BrandColorScheme` optional slots |
| Error/destructive + status banner surfaces | ✅ | `error`/`onError`, and `errorContainer`/`successContainer`/`warningContainer`/`infoContainer` slots |
| Link color | ✅ | `BrandColorScheme.link` |
| Font families (body / display / brand / code) | ✅ | `BrandTypography` + `FontResolver`; the brand family also drives the app-name headers via `context.brandNameOn` |
| Type scale (all 15 roles: size / weight / height / spacing / family) | ✅ | per-role `TypeScaleOverride`, with `family` routing a role to a `BrandFontRole` (body / display / brand) |
| Corner radii | ✅ | `BrandShape` |
| Auto on-color tint | ✅ opt-in | `BrandTint` (`source` + `strength`); off by default |
| App name + logos | ✅ | `AppIdentity` |
| Neutral surface ramp (cards/inputs/selected tints) | ❌ fixed | neutral by design, hosts colored content |
| Spacing grid + breakpoints | ❌ fixed | `static const` shared grammar |
| Widget composition / layout | ❌ fixed | module override or fork |

## Hard rules

1. No `Color(0x...)`, `Color.fromARGB`, or `Colors.red|green|orange|blue|yellow` outside this package.
2. No bare `BorderRadius.circular(N)` — use `context.radii.*` (or `SoliplexTheme.of(context).radii`).
3. No `TextStyle(fontSize: ...)` or bare `fontSize:` in `.copyWith` — start from a `textTheme` entry and `copyWith` only the delta you need.
4. No `fontFamily: 'monospace'` / `'Roboto Mono'` / `'SF Mono'` string literals — use `context.monospace`.
5. No raw `EdgeInsets` numbers — use `SoliplexSpacing`.
6. No raw breakpoint numbers — use `SoliplexBreakpoints`.
7. Prefer branded components over their Material equivalents — see the
   **Components** table above. Use raw Material only when no Soliplex wrapper
   exists.

These are reviewer-enforced. See the project root `CLAUDE.md` (`## Design
system`) for the same rules with examples and rationale.

## Adoption checklist (run before opening a PR)

Mirror of the checklist in `design_system/README.md`:

- [ ] Colors come from `Theme.of(context).colorScheme`, not hex literals.
- [ ] Padding values come from `SoliplexSpacing` (`s1..s6`).
- [ ] Corner radii come from `context.radii`.
- [ ] Text styles come from `Theme.of(context).textTheme`.
- [ ] Monospace uses `context.monospace`, not a hardcoded font family.
- [ ] Status colors go through `context.{danger,success,warning,info}`.
- [ ] Interactive widgets use the branded `SoliplexX` wrapper when one exists.
- [ ] Screen behaves at all three `SoliplexBreakpoints`.
- [ ] Both light and dark palettes look correct.
- [ ] Destructive actions use `colorScheme.error`; never red hex.

## Adding a token

Don't, without explicit user approval. If a missing value is genuinely needed:

1. Stop. Raise the case in the relevant PR.
2. Add the token to `lib/src/tokens/colors.dart` (or the matching tokens file)
   **and** to `design_system/tokens.{dart,css,jsx}` in the same change.
3. Update `design_system/README.md` so the table stays accurate.
