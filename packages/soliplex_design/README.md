# soliplex_design

The **single source of truth** for color, type, spacing, radii, and breakpoints
in the Soliplex Flutter stack. Consumed by `soliplex_frontend` and any
whitelabel app embedding it; everything under `lib/src/modules/` in the frontend
must consume tokens from here — no hex literals, no magic padding numbers, no
hardcoded font sizes or families.

The canonical reference (with swatches, type specimens, and component demos) is
[`design_system/`](../../design_system/). Open
`design_system/Soliplex Design System.html` in a browser to verify a new screen
matches.

## Accessor cheat sheet

| What                  | How                                                                                                  |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| Color                 | `Theme.of(context).colorScheme.<token>` or `SoliplexTheme.of(context).colors.<token>`                |
| Status color          | `Theme.of(context).colorScheme.{danger,success,warning,info}` (via `SymbolicColors`)                 |
| Spacing               | `SoliplexSpacing.s1` (4) / `s2` (8) / `s3` (12) / `s4` (16) / `s6` (24)                              |
| Radius                | `SoliplexTheme.of(context).radii.{sm,md,lg,xl}` — default is `md` (12 px)                            |
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

## Hard rules

1. No `Color(0x...)`, `Color.fromARGB`, or `Colors.red|green|orange|blue|yellow` outside this package.
2. No bare `BorderRadius.circular(N)` — use `SoliplexTheme.of(context).radii.*`.
3. No `TextStyle(fontSize: ...)` or bare `fontSize:` in `.copyWith` — start from a `textTheme` entry and `copyWith` only the delta you need.
4. No `fontFamily: 'monospace'` / `'Roboto Mono'` / `'SF Mono'` string literals — use `context.monospace`.
5. No raw `EdgeInsets` numbers — use `SoliplexSpacing`.
6. No raw breakpoint numbers — use `SoliplexBreakpoints`.

These are reviewer-enforced. See the project root `CLAUDE.md` (`## Design
system`) for the same rules with examples and rationale.

## Adoption checklist (run before opening a PR)

Mirror of the checklist in `design_system/README.md`:

- [ ] Colors come from `Theme.of(context).colorScheme`, not hex literals.
- [ ] Padding values come from `SoliplexSpacing` (`s1..s6`).
- [ ] Corner radii come from `SoliplexTheme.of(context).radii`.
- [ ] Text styles come from `Theme.of(context).textTheme`.
- [ ] Monospace uses `context.monospace`, not a hardcoded font family.
- [ ] Status colors go through the `SymbolicColors` extension.
- [ ] Screen behaves at all three `SoliplexBreakpoints`.
- [ ] Both light and dark palettes look correct.
- [ ] Destructive actions use `colorScheme.error`; never red hex.

## Adding a token

Don't, without explicit user approval. If a missing value is genuinely needed:

1. Stop. Raise the case in the relevant PR.
2. Add the token to `lib/src/tokens/colors.dart` (or the matching tokens file)
   **and** to `design_system/tokens.{dart,css,jsx}` in the same change.
3. Update `design_system/README.md` so the table stays accurate.
