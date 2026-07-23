# Changelog

All notable changes to the Soliplex frontend app are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the `version+build` scheme from `pubspec.yaml`, bumped via
`dart run tool/bump_version.dart`.

## [Unreleased]

### Added

- Document origin URLs (`source_url`) now render as clickable links across the
  room document listing, document filter, citations, and the chunk-visualization
  page, replacing the internal file path — which remains only in the document
  listing's metadata dialog. Where the backend does not yet carry `source_url`
  (citations, chunks), the link comes from a resolver a deployment injects via
  `standard(documentBrowserUrl: ...)`.
- Room and lobby: the current server's name (or its address when unnamed) now
  shows alongside the room name in the room view header, and as a title band at
  the top of the lobby's room pane, so a user connected to several servers can
  tell which one they are viewing.
- Room info: a "View chunk" card lets you enter a chunk id and open its
  rendered page images, so a chunk can be viewed directly from an id (e.g. one
  taken from logs) rather than only by tapping a PDF citation. Expanded
  citations and the chunk viewer now also surface the chunk id and document
  provenance, each copyable.
- Tapping an inline image in chat or other markdown now opens a full-size
  pan/zoom/rotate view; SVG code blocks open the same view on tap.
- A citation's figures open in a pageable browser over all of that citation's
  figures, with previous/next chevrons, page dots, and left/right arrow-key
  navigation, instead of a single figure at a time.
- Removing a server now asks for confirmation first — on both the home-screen
  server list and the lobby sidebar's server menu — so a server and its sign-in
  session can't be dropped by a stray tap. For a signed-in server the prompt
  notes that removing also signs you out.

### Changed

- The lobby's rooms page is more compact on phones: a room's confidentiality
  marking and quiz indicator move to their own row so the room name keeps the
  full tile width, the sort control collapses to an icon button that shares the
  search row (the labelled dropdown stays on tablet and wider viewports), and
  the selected server's name moves into the app bar. The markings row wraps
  instead of overflowing at large accessibility text sizes.
- App bar titles now left-align on every platform. Previously iOS and macOS
  (and web served to those hosts) centered the title, diverging from the app's
  left-aligned pane and room headers; titles now match those headers across
  platforms and viewport sizes.
- The image and SVG preview surfaces — chunk visualization, workdir file
  preview, citation figures, and SVG previews — share a single
  pan/zoom/rotate/reset viewer, so those interactions behave consistently and
  zooming out returns to a centered fit.
- The insecure-connection warning ("This connection is not encrypted") stacks
  its actions vertically — a prominent Cancel above a quieter "Connect anyway"
  — so the label no longer wraps at a narrow width and the safe choice carries
  the visual emphasis.

## [0.94.0+68] - 2026-07-17

### Added

- `Flavor` and `FlavorTheme`: an app variant is now a declaration object
  (identity, theme, modules, boot knobs) that `Flavor.build()` lowers to a
  `ShellConfig`. `standardFlavor()` composes the standard variant for a fork to
  customize (theme, `extraModules`) before building; `standard()` is that
  flavor, lowered. `FlavorTheme` wraps the two theming paths (`.brand` /
  `.themeData`). A flavor holds live modules and builds once — a second
  `build()` throws `StateError`. See `docs/authoring-a-flavor.md`.
- Flavor authoring: `buildStandardKit` builds the standard module graph and
  its shared session state, so a fork can author its own flavor — with full
  theme and module control — using only a `soliplex_frontend` dependency.
  `standard()` now delegates through `standardFlavor` to it. See
  `docs/authoring-a-flavor.md`.
- The flavor-authoring surface is reachable from the `soliplex_frontend`
  barrel: `Flavor`, `FlavorTheme`, `standardFlavor`, the full-control theme
  types (`SoliplexColors`, `buildSoliplexThemeData`, `lightSoliplexColors`,
  `darkSoliplexColors`, `SoliplexRadii`, `soliplexTextTheme`) and the kit
  (`buildStandardKit`, `StandardKit`), so a fork needs no direct
  `soliplex_design` dependency.
- `buildStandardKit` surfaces `enableDocumentFilter` (default on) as a
  flavor knob.
- Room and lobby: a per-server status banner, chiefly an upcoming-maintenance
  warning with a live countdown, that operators post or cancel by dropping or
  deleting a static JSON file on the backend — no app rebuild. It is scoped to
  the in-context server and auto-hides once a maintenance window ends. A missing
  file or fetch error resolves silently to "no message"; a message whose
  maintenance window is malformed still shows, just without the window. The file
  location and poll interval are flavor-configurable.
- The banner starts collapsed (title + countdown + one body line) and expands on
  demand to show the server name, the maintenance window as a range in the
  viewer's local time (stacked onto two lines on narrow screens), and the full
  body. A dismiss button hides a message for the session; it returns on the next
  app start or after logging out and back in to the server.

### Changed

- `buildSoliplexThemeData` now runs the contrast check on every theme it builds
  — both the curated `BrandTheme` path and a fork's direct full-color path —
  logging a warning for any low-contrast foreground/background pair, including
  the `link` role, rather than silently shipping an illegible pairing.
- `ShellConfig.fromModules` now fails fast, throwing a clear `ArgumentError` at
  boot when a supplied `ThemeData` is missing the required `SoliplexTheme`
  extension (for example a bare `ThemeData()` instead of
  `buildSoliplexThemeData(...)`), replacing a deep crash in the first branded
  widget rendered.
- `AppIdentity` now asserts a non-empty `appName`, catching the mistake at
  construction rather than letting a blank name reach `MaterialApp.title` and
  the auth and versions surfaces.

### Removed

- The redundant `package:soliplex_frontend/flavors.dart` entrypoint. Its exports
  (`standard`, `standardFlavor`, `buildStandardKit`, `StandardKit`) now come from
  the main `soliplex_frontend` barrel; a fork importing `flavors.dart` should
  switch to `package:soliplex_frontend/soliplex_frontend.dart`.

## [0.93.1+67] - 2026-07-14

### Added

- Room: the document filter now survives a reload. On thread open the selection
  is restored from the thread's run history (the last-sent filter), so reopening
  a thread no longer drops the filter and silently searches the whole corpus. A
  filtered document that has since been deleted shows as an "Unavailable
  document" chip and is still applied, so results stay correctly scoped.

## [0.93.0+66] - 2026-07-13

### Added

- Room: a citation's cited figures now render inline as thumbnails, tapped to
  view full-size with the figure's caption, using the picture bytes the backend
  already ships in the rag state. Figures without shipped bytes are not shown
  inline; they remain viewable via the citation's source (chunk visualization)
  button.
- Lobby: an "Unread first" sort option groups a server's rooms into an Unread
  section above a Read section, each ordered by recent activity.

### Changed

- The chat "generating" placeholder and running agent step labels now animate
  with a light-sweep shimmer instead of static spinners, giving clearer
  in-progress feedback without a layout shift.
- Update route for thread-specific file uploads to stay current with
  backend release
  [v0.72.1](https://github.com/soliplex/soliplex/releases/tag/v0.72.1).
- Device-local cleanup on server removal is driven by an explicit
  `ServerManager.onServerRemoved` event instead of diffing the servers signal.
  Only a genuine removal clears a server's read state, unread-divider anchors,
  and composer drafts; a signal reset such as shell teardown no longer risks
  wiping stored state, independent of module dispose order.
- When a room or thread disappears from a server (deleted, or access removed),
  its device-local read markers and unread-divider anchors are dropped across
  users, and a deleted thread's document-filter selection is cleared. Unsent
  composer drafts are intentionally kept (they self-expire and clear on explicit
  server removal), so a transient fetch shortfall can't destroy unsent text.

### Fixed

- Cancelling or resetting an agent run while it was resuming after a tool call
  could execute the tool a second time (or repeatedly, when resetting), causing
  duplicate tool side effects. The run now stops cleanly without re-running the
  tool.
- A frontend decoding bug is no longer misreported as a backend
  malformed-response error: a run failure now classifies by its underlying
  cause, so an internal type error is surfaced and logged as internal rather
  than blamed on the server.
- A malformed chunk-visualization payload — a wrong-typed or missing
  `chunk_id`, `document_uri`, or `images_base_64` field — now surfaces as a
  non-retryable error instead of an uncaught type error, consistent with the
  HTTP transport hardening.
- A malformed backend response no longer crashes the client: a payload whose
  shape doesn't match the contract (a wrong-typed or missing field, non-UTF-8
  or undecodable JSON body) now surfaces as a non-retryable error carrying the
  underlying cause instead of an uncaught type/format error. A non-UTF-8 *error*
  body can no longer mask the HTTP status, so retry and re-auth still classify
  correctly.
- Deleting the open thread no longer writes a stale "read" marker for it on the
  way out (via dispose, or the auto-navigate to a sibling thread), so a thread
  later re-created under the same id no longer appears already-read.
- Removing a server now clears the rest of its device-local state, not just its
  read markers: the thread unread-divider anchors and unsent composer drafts are
  dropped too, on every removal path. Because server ids derive from the URL,
  re-adding the same server reused the id and could resurrect a stale divider or
  an old draft.
- Removing a server now evicts its in-memory agent runtime and tracked runs
  instead of leaking them until app exit — the runtime's timers and stream are
  disposed and any live run for the server is cancelled. Its in-memory
  document-filter selections are dropped too, so re-adding the same server (ids
  derive from the URL) starts with an empty filter.

### Security

- Composer drafts are now scoped to the signed-in user: a different user signing
  in on the same server no longer sees the previous user's unsent draft. A
  by-server draft clear also no longer over-reaches a same-host server that
  differs only by an explicit vs default port.
- On first launch after upgrade, a one-time cleanup removes device-local data
  left over from the previous storage format — orphaned read/anchor markers and
  raw-format composer drafts, plus a defunct hidden-servers key — so a former
  user's leftover plaintext no longer lingers on disk.
- Thread read markers and unread-divider anchors are now scoped to the signed-in
  user: a different user signing in on the same server no longer inherits the
  previous user's read state or "New messages" dividers. As a one-time effect of
  the storage-format change, existing thread read state resets on upgrade — every
  thread reads as unread once and dividers are recomputed from that point.
- Lobby room and server read markers are now scoped to the signed-in user, per
  server: a different user signing in on a shared device no longer inherits the
  previous user's unread state, and the multi-server lobby resolves each server's
  own signed-in user. This closes the last device-local read-state leak between
  users. As a one-time effect of the storage-format change, existing lobby
  read state resets on upgrade — every room reads as unread once.
- When a different user signs in on a server within the same app session, that
  server's in-memory session state is now torn down — the agent runtime, any
  tracked runs, in-flight and completed uploads, and document-filter selections
  — so the new user can't reattach to or observe the previous user's session.
  Servers whose identity provider issues opaque (non-JWT) access tokens are a
  known exception: they carry no per-user identity to key on, so the switch
  can't be detected for them.

## [0.92.0+65] - 2026-07-02

### Added

- Design system: `BrandTypography` now covers all 15 Material text roles (up
  from 9) — `displayLarge/Medium/Small`, `headlineLarge/Small`, and `labelLarge`
  are now built (the other six, including `headlineMedium`, already shipped) and
  each accepts a per-role `TypeScaleOverride`. A role can be
  pointed at a named font family via `TypeScaleOverride.family`
  (`BrandFontRole.{body,display,brand}`), and a fourth `brandFamily` font is
  available — it renders the app/brand name in the auth and lobby headers, read
  through `context.brandFont` / `context.brandNameOn`.
- Design system: `BrandTint` and `TintSource` are re-exported from
  `soliplex_frontend`, so a facade-only consumer can build
  `BrandTheme(tint: ...)` without depending on `soliplex_design` directly.
- Chat: messages now show a muted timestamp caption, and a centered day
  divider marks each calendar-day group in the transcript. Both use the
  viewer's local zone and stay correct across DST.
- Chat: the transcript is selectable across message bubbles — one drag spans
  user, assistant, error, and tool-output tiles at once.
- Room: the rooms rail clusters unread rooms at the top — the selected room is
  pinned first, then unread rooms newest-first, a divider, then read rooms
  newest-first, then idle rooms alphabetically — so a freshly-added server's
  backlog no longer reads as a wall of unread noise.
- Room/Lobby: read markers now cascade down a server → room → thread hierarchy.
  Each unread check floors an item's read state under its ancestors — a room
  reads as read when its activity is at or before the later of its own marker
  and its server's, and a thread under the later of its own, its room's, and its
  server's — so a single higher-level marker can clear every dot beneath it with
  no per-item write. Server-level markers persist per-device alongside the
  existing room and thread markers. Note: activating the hierarchy re-interprets
  markers you already have, so some threads may show as read on upgrade with no
  action on your part — the rule can only clear an unread dot, never light one.
- Room/Lobby: you can now mark a thread, a room, or a whole server read on
  demand — "Mark as read" in the thread tile menu, a long-press (touch) or
  right-click (desktop) "Mark as read" on the rooms-rail circle and on the lobby
  room cards, and "Mark all as read" in the server tile menu. Thanks to the
  read-up hierarchy above, marking a room read also reads all its threads, and
  marking a server read reads every room and thread on it — loaded or not — with
  a single marker write and no per-item fan-out.

### Changed

- Chat: a message's timestamp now comes from the backend's authoritative time
  — the AG-UI event timestamp, falling back to the run's server `created` —
  instead of the device clock, and is absent until that time is known (e.g. an
  optimistic user echo fills in on replay). Client-only tiles (cancellation,
  loading, in-flight streaming, locally executed tool results) carry a UTC
  client time.
- Design system: the label type scale is now strictly ordered at 12 / 14 / 16
  (`labelSmall` / `labelMedium` / `labelLarge`). `labelLarge` is built at 16 and
  drives interactive component text (buttons, chips, tabs, segmented controls),
  which previously fell through to Material's 14 pt default. `labelMedium` moves
  to 14 for incidental labels (badges, counters, dividers, filter indicators);
  prominent labels — the connect-flow rail, room-info section headers, and the
  classification badge — are pinned to `labelLarge` so they stay at 16.

### Fixed

- Room/Lobby: removing a server now clears its per-device read markers (server,
  room, and thread), so re-adding the same server no longer shows its rooms and
  threads as already read. Markers are keyed by a URL-derived server id, which a
  re-added server reuses, so a removed server's markers would otherwise floor
  the fresh one.
- Chat history: a malformed or out-of-range backend timestamp no longer aborts
  loading a thread's history or hangs an in-flight run; the affected message
  simply carries no timestamp. Naive (offset-less) backend timestamps are now
  read as UTC instead of the device's local zone, fixing an off-by-hours error.
- Consent notice: the full notice can now be selected and copied in one drag.
  The prose renderer no longer builds each markdown block as an isolated
  selectable, so a selection spans every paragraph and list at once.
- Room: the sidebar create-thread button is now labelled "New" instead of
  "New Thread".
- Room: the on-screen keyboard no longer hides the most recent message. When
  the keyboard opens while the conversation is resting at the bottom, or still
  parked on a just-sent question pinned to the top whose reply runs past the
  fold, the message list scrolls to the end of the latest reply so it stays
  visible above the input bar. The trigger is the viewport shrinking (any
  near-bottom reflow), not a platform check, so desktop — which has no software
  keyboard — is unaffected.
- Room and lobby: content now clears the device safe areas on mobile — the chat
  composer sits above the home indicator, and the wide room layout's rail and
  sidebar headers clear the status bar and side notches.
- Lobby: long room names and descriptions in the list view, and long server
  addresses in the sidebar, now ellipsize instead of overflowing their tiles on
  narrow screens.
- Quiz: the Submit/Next action bar is pinned in a footer below the scrolling
  question, so the on-screen keyboard can no longer push it off-screen during
  free-text answers.
- Diagnostics: long monospace values in the network inspector — the JSON tree
  root and the key/value and header cells (URLs, tokens, cookies) — now scroll
  horizontally instead of clipping.

## [0.91.0+64] - 2026-06-25

### Added

- Design system: `BrandTheme` is the public theme-customization contract — a
  constructor ladder (`soliplex()` / `fromSeed(...)` / `fromAccents(...)`), a
  `BrandColorScheme` of seven required roles plus optional status and on-color
  slots, `BrandTypography` + `TypeScaleOverride`, and `BrandShape`. A fork
  customizes color, type, and shape through it and depends only on the
  `soliplex_frontend` barrel, which re-exports the façade, `AppIdentity`, and
  `FontResolver`.
- Design system: app identity is now split from the visual theme. `AppIdentity`
  (app name + logos) and `BrandTheme` vary independently; `standard()` takes
  `identity`, `theme`, and a `fontResolver`, defaulting to the shipped Soliplex
  look.
- Design system: `FontResolver` injection seam with a dependency-free
  `BundledFontResolver` that defers to native asset fonts.
- Design system: `BrandColorScheme` exposes `link`, `error`/`onError`, and the
  soft status-surface roles (`errorContainer`/`successContainer` and their
  on-colors), plus `warningContainer`/`infoContainer` — so a fork can rebrand
  all four status pills (`SoliplexBadge` / `SoliplexChip`) alongside the base
  palette.
- Design system: `BrandTint` (`TintSource none|surface|primary` + strength), an
  opt-in axis that tints auto-derived on-colors toward the surface or
  brand-primary hue. Default is `none`, so the shipped look is unchanged.

### Changed

- Design system: derived on-colors resolve through a WCAG-aware `readableOn`
  cascade (softest-first near-black/near-white, falling through to pure
  black/white only when a mid-tone surface would drop below AA), so
  auto-filled on-colors stay AA-legible while reading easier than pure
  black/white. `BrandTheme.soliplex()` lowers byte-for-byte to the previous
  Soliplex palette, so the shipped look is unchanged.
- Design system: corner radii and status colors now route through the active
  brand theme rather than fixed internal tokens.
- Design system (**breaking**): consumer forks migrate
  `SoliplexBranding(accentLight, accentDark, ...)` to `AppIdentity(...)` +
  `BrandTheme.fromAccents(...)`, and `SymbolicColors` moves from `ColorScheme`
  to `BuildContext` (`colorScheme.danger` becomes `context.danger`).

### Fixed

- Design system: brand-supplied on-colors are used verbatim; a pair below the
  WCAG AA 4.5:1 threshold is reported through `soliplex_logging` (naming the
  brightness) instead of tripping a debug-only assert, so the contract holds in
  release builds. The `link` role is checked against the background only when a
  fork sets it, so overriding just the background no longer flags the default
  link.

## [0.90.3+63] - 2026-06-24

### Changed

- Logging: auth, room, and shared modules now log through `soliplex_logging`
  instead of `debugPrint`, carrying error and stack-trace detail. The app
  registers a console and a stdout sink at startup, holding release builds to
  warnings and debug builds to info.

### Fixed

- Room: deleting a thread that no longer exists server-side no longer traps the
  user in the Delete dialog. A 404 is now treated as success (DELETE is
  idempotent — the thread is already gone), so the dialog closes and the stale
  entry is removed from the sidebar. Other failures still surface in the dialog.

## [0.90.2+62] - 2026-06-22

### Added

- Design system: themes are now customizable through a public `BrandTheme`
  contract — a per-brightness `BrandColorScheme` (seven core roles plus optional
  status *signal* colors, the `error`/destructive role, the four status banner
  surfaces (error/success/warning/info containers), and `link`),
  `BrandTypography` (font families via a pluggable `FontResolver` seam, plus
  per-role type-scale deltas), `BrandShape` corner radii, and an opt-in
  `BrandTint` on-color tint — lowered to `ThemeData` by `lowerBrandTheme`. A
  flavor passes a `BrandTheme` and an `AppIdentity` to `standard()`. An unset
  role falls back to the base palette; unspecified on-colors get a soft
  near-black/near-white foreground (a cascade that escalates to pure black/white
  only when a mid-tone surface needs it to stay AA-legible), which a brand can
  optionally tint toward the surface or primary hue via `BrandTint`. An
  explicitly-set on-color is used as-is, and a sub-AA pair (the on-color pairs,
  `foreground`/`background`, and `link` against the background), or muted text
  below 3:1, is logged as a warning. `BrandTheme.soliplex()` lowers byte-for-byte
  to today's palette, and the app's rendered screens are unchanged.
- Room: threads now show a "New messages" divider at the first unread message
  and auto-scroll to it on open. Read state is tracked per-device, by message
  id; there is no server-side read state or unread count.

### Changed

- Design system (**breaking for whitelabel forks**): `SoliplexBranding` is
  replaced by `AppIdentity` (app name + logos) plus `BrandTheme` (visual
  theme); `standard()` now takes `identity:` + `theme:` instead of
  `branding:`. The `SymbolicColors` status accessors moved from `ColorScheme`
  to `BuildContext` (`colorScheme.danger` → `context.danger`), and app corner
  radii now read `context.radii` so a `BrandShape` override reaches them.
- Design system: the `info` and `warning` filled status pills
  (`SoliplexBadge`/`SoliplexChip`) now read the new
  `infoContainer`/`warningContainer` token pairs — a soft container surface with
  an AA-legible on-color, matching the existing `danger`/`success` pills —
  instead of tinting the signal color at 15% alpha. This restyles those two pill
  variants (visible in the component gallery); no app screen uses the
  `info`/`warning` intents, so shipped screens are unaffected.
- Room: a room now keeps its unread dot while any of its threads is unread,
  instead of clearing the moment the room is opened. Read state stays
  per-device; the room marker is derived from thread-read state.
- Auth: the consent agreement is now toggled by tapping anywhere on its row,
  not just the checkbox, giving it a full-width tap target.
- Auth: the consent notice terms are now selectable, so users can copy the
  text they're agreeing to.

## [0.90.1+61] - 2026-06-17

### Changed

- Auth: the pre-sign-in consent notice body now renders as markdown
  (paragraphs, lists, emphasis, and external links) instead of literal text.
  Flavors can structure the notice; the body is treated as trusted,
  flavor-provided input.

## [0.90.0+60] - 2026-06-16

### Added

- Lobby: an unread dot on each room card when the room has activity newer than
  the last time the user opened it. Read state is tracked per-device; there is
  no server-side read state or unread count.
- Room: workdir file image previews are now zoomable and rotatable, with a
  reset-to-original control that appears while zoomed. Zoom/rotate now share a
  single viewer with the citation chunk visualization.
- Diagnostics: the network inspector gains a category filter
  (LLM / Auth / System) and can deep-link straight to a single run's HTTP
  exchanges.

### Changed

- Auth/Quiz: widened the centered form/content column from 400 to 600 on
  wide viewports so server URLs, the server list, and quiz content have more
  room. The width is now a single shared constant (`formColumnMaxWidth`).
  Narrower viewports are unaffected — the column still fills the available
  width.
- Auth: the connect-flow rail now scrolls to keep the active step centered as
  the flow advances. Early and final steps that can't be centered stay pinned
  to the start/end.
- Diagnostics: the network inspector is redesigned — expandable HTTP exchange
  tiles with one de-duplicated detail view (replacing the separate run-detail
  page) under the branded top bar.
- Room info: redesigned with a branded header and Server/Room section cards;
  the room-info and documents actions now live in the header's top-right.
- Versions/about screens now use the branded top bar.

### Fixed

- Room: image previews can be zoomed with a trackpad two-finger scroll, not
  only mouse wheel and pinch (`InteractiveViewer.trackpadScrollCausesScale`).
  Zoom is sized to the image's exact aspect ratio for every format, so scaling
  no longer magnifies surrounding whitespace.
- Lobby: a room's "last activity" now reflects the user's most recent run in
  that room (served by the backend stats API), not the newest thread's
  creation time — so a long-lived thread used minutes ago no longer reads as
  stale. Activity loads in one batched request per server.
- Room rail: a permission-denied (403) room list shows a distinct,
  non-retryable lock affordance instead of a generic "try again" error, and an
  expired session during the rail's room or identity fetch redirects to login
  rather than flashing an error.
- Room rail: the account menu's signed-in identity resolves more robustly —
  whitespace-only profile fields are ignored, a malformed claim no longer
  discards its valid siblings, and an email standing in for a missing name no
  longer renders twice.
- Lobby: server tiles no longer show an auth status dot for no-auth servers.

## [0.89.0+59] - 2026-06-12

### Added

- Auth: redesigned the onboarding/connect flow to the mockup — a persistent
  branded top bar (`HomeShellHeader`: logo, app name, version, and an
  about/versions action) wrapping a width-capped content column, a
  `ConnectFlowRail` breadcrumb that mirrors the connect state machine,
  connect-flow bodies reshaped per state, and the same top bar on the OAuth
  callback and server-list screens.
- Design: re-export `ClassificationTheme` and `ClassificationLevel` from the
  public API so adopters can configure classification without a direct
  `soliplex_design` dependency.
- Lobby: branded header in the server sidebar (logo, app name, and version),
  sourced from the flavor's `SoliplexBranding`.
- Lobby: account block in the sidebar footer showing the selected server's
  signed-in identity (avatar, name, and email), with a ⋮ menu that collapses
  the Network Inspector and Versions actions.
- Lobby: an auth-status dot on each sidebar server tile — signed in, signed
  out/expired, or no authentication required.
- Lobby: sort rooms by recent activity (a dropdown beside the view toggle),
  grouping them under "Today"/"Yesterday"/… section headers, and show each
  room's most-recent-thread time as a relative label ("3h ago") fronted by a
  muted clock icon on its card.

### Changed

- Lobby: select a single server in the sidebar to view its rooms, replacing the
  multi-server show/hide model; the last selection persists across launches,
  and server actions (Sign in / Log out / Remove) live in a per-tile ⋮ menu
  rather than a separate server-list screen.
- Lobby: switch the two-pane layout at the desktop breakpoint (840) instead of
  a hardcoded width.
- Auth: the insecure-connection screen reads as a warning rather than an error
  (it doesn't block "Connect anyway"); free-standing body text is themed
  through `textTheme`.
- Room: hide the document filter button in rooms with no filterable documents.
- Bumped `go_router` to 17.3.0.

### Fixed

- Auth: persist the last-connected backend URL after a web OIDC sign-in, so the
  empty home screen prefills it the same way it does after a native sign-in.
- Lobby: adding and signing in to a new server now selects that server on
  return, instead of restoring the previously viewed one. The connected server
  is persisted as the active selection at each connect-success point.
- Lobby: a signed-out or inactivity-timed-out server keeps an inline "Sign in"
  panel instead of blanking the content pane; show a loading indicator while
  the persisted selection resolves on launch.
- Lobby: align list-card gutters and spacing to the design mockup, give grid
  cards equal height with a pinned footer, and match list-card title/subtitle
  styles to the grid card.
- Lobby: keep the sidebar's brand header and account bar clear of the status
  bar, notch, and home indicator by wrapping the two-pane body and the drawer
  in a safe area.
- Lobby: surface a failed server log-out as a persistent per-tile error menu
  (Try again / Show error detail / Remove server) instead of a transient
  message, so the preserved local session stays visible and a server whose IdP
  log-out keeps failing can still be removed.
- Design: scale the `SoliplexGlow` halo with its child so the brand mark reads
  correctly at any size.
- Design: round `SegmentedButton` to the `md` radius (the lobby view-mode and
  diagnostics stream toggles) instead of Material's full-pill default.
- soliplex_client: pin the `ag_ui` git dependency to a fixed ref for
  deterministic resolution; a floating HEAD pulled an incompatible release that
  broke web builds.
- Room: render document and thread timestamps in the viewer's local time zone.
  Backend timestamps are UTC, so the document card's date and time showed the
  wrong time-of-day, and a week-old thread's date could be off by one, for any
  viewer not in UTC.

## [0.88.0+58] - 2026-06-03

### Added

- Design: configurable `ClassificationTheme` with classification resolution
  logic, a `ClassificationBadge` component, and a `Pill` primitive shared with
  the badge family.
- Lobby: show a classification marking on room cards.

### Changed

- Upgraded within-constraint dependencies: `flutter_appauth` 12.0.1,
  `objective_c` 9.4.1, `json_annotation` 4.12.0, `url_launcher_android` 6.3.30,
  `vector_graphics` 1.2.2, `hooks` 2.0.1, `code_assets` 1.2.1.

## [0.87.2+57] - 2026-06-01

### Added

- Lobby: filter rooms by name, list/grid view toggle, and per-server
  show/hide of rooms via a sidebar eye toggle.
- Design: `SoliplexButton.text` alignment axis; `SoliplexInput` `focusNode`
  and `readOnly` passthroughs.

### Changed

- Adopted the `soliplex_design` component library across room (composer,
  dialogs, document picker, room-info cards, thread sidebar), quiz, and
  diagnostics.

### Fixed

- Room: cap chat-input growth to prevent layout overflow.
- Room: show the citation source URL at the top of the expanded view.
- Room: offer sign-in instead of retry on auth errors.
- Room: launch markdown links on tap.

## [0.87.1+56] - 2026-05-29

### Added

- Inactivity auto-logout: `InactivityMonitor` with warning and grace timers,
  an `InactivityDialog` mm:ss countdown, and `InactivityConfig` threaded
  through the shell; re-auth forces `prompt=login`.
- Design component library: `SoliplexButton`, `SoliplexBadge`, `SoliplexChip`,
  `SoliplexInput`, `SoliplexDropdown`, `SoliplexDatePicker`,
  `SoliplexTimePicker`, with a gallery example app and golden coverage.
  `SoliplexButton` gains trailing-icon support.

### Changed

- The shell is bootable without the auth module.
- Adopted `SoliplexButton` across the lobby and auth UI.
- Bumped `signals` to 6.3.1 and `flutter_secure_storage` to 10.3.0; pinned the
  `ag_ui` dependency to upstream in one place; pinned CI Flutter to 3.38.7.

### Fixed

- Auth: send `prompt` and `return_to` as encoded query params on web.
- Design: wrap input helper/error text instead of truncating; keep the loading
  spinner square in tight slots.

## [0.87.0+55] - 2026-05-26

### Added

- Auth failure taxonomy: `AuthFailureKind`, `describeAuthFailure`, and OAuth
  web-callback error-code mapping to user-facing copy.
- Branding: `SoliplexGlow` radial backplate, brand-accent palette derivation,
  and a `SoliplexBranding` API with `BrandLogo`.

### Changed

- Extracted the `soliplex_design` workspace package; split `ShellConfig` into
  light/dark themes wired to branding; moved markdown theming and the dark
  theme into the design layer; centralized monospace font resolution.

## [0.86.2+54] - 2026-05-22

### Fixed

- Comprehensive `AuthException` funneling across room, lobby, and auth (thread
  list/history/metadata fetches, `createThread`, `SessionSpawner`, token
  refresh, and upload-list refresh).
- Auth: wait for IdP confirmation before clearing the local session; wire
  `id_token` through the web callback; skip OIDC discovery on native logout.
- Lobby: refetch on session recovery rather than on token rotation.

## [0.86.1+53] - 2026-05-21

### Added

- Return-to-after-auth: route guard stashes the return-to target,
  `ConnectFlow`/`HomeScreen` forward it, and `PreAuthState` carries
  `frontendReturnTo` with a 30-minute TTL.
- Composer-draft persistence across auth redirects.
- Per-server route guard via `connectionRevision`; `ExpiredSession` state that
  preserves tokens across auth failures; `PermissionDeniedException` (401/403
  split); reactive cancellation on `auth.session` transitions; inline
  "sign in again" affordance for expired servers.
- Workdir preview for text, code, markdown, SVG, JSON, CSV, and HTML with
  swipe navigation.

### Changed

- Raised the token refresh threshold to 5 minutes.

## [0.86.0+52] - 2026-05-19

### Added

- Markdown image support: data-URI decoder, broken-image placeholder, and a
  source toggle for broken data-URI images.
- Preview previewable artifacts on row tap.

### Changed

- Renamed `design_handoff/` to `design_system/`; adopted design tokens across
  room, quiz, auth, lobby, and diagnostics; codified design hard rules and the
  accessor cheat sheet in `CLAUDE.md`.

### Fixed

- Isolate corrupt page images in chunk visualization.
- Diagnostics: remove force-unwraps in HTTP event readers; guard SSE parsing
  against a missing stream-end body.

## [0.85.5+51] - 2026-05-17

### Added

- Web file uploads: `WebXhrHttpClient` (FormData/XHR), a JS-interop folder
  picker, and web blob plumbing through to the API.
- User-facing cancel of in-flight or queued uploads; a single global FIFO
  upload queue; per-file progress reporting; folder pick that walks a chosen
  directory; friendlier error messages for many failure modes.
- Streaming multipart encoder, `Stream<List<int>>` request bodies, and a
  `CancelToken` on the one-shot `request()` interface.

## [0.85.4+50] - 2026-05-14

### Changed

- Renamed `ActivityType` to `RunPhase`.

### Fixed

- Nested activity rows: apply `ACTIVITY_DELTA` patches so nested activities
  update and complete; decode `skill_tool_result`; keep the execution bubble
  after reload for trailing tool-yield runs; carry `skill_tool_call` args
  across the AG-UI replace boundary; resolve the phantom-row regression;
  isolate an absorbed `ExecutionTracker` from the session-owned signal.

## [0.85.3+49] - 2026-05-11

### Added

- In-app preview of workdir image artifacts; copy buttons for citations.

### Changed

- Per-row copy beside the citation chevron; `CopyButton` idle-icon override;
  bumped `flutter_svg` 2.3.0, `flutter_secure_storage` 10.1.0, `go_router`
  17.2.3.

### Fixed

- Room: stop leaking raw exceptions (distinct 404 branch); lift preview error
  UI out of `InteractiveViewer`.

## [0.85.2+48] - 2026-05-08

### Added

- Dropped-event tiles: render undecodable or replay-failed AG-UI events as
  low-emphasis tiles; synthesize a no-response reply tile and clear the stuck
  thinking spinner via a `NoResponseTile` sealed `ChatMessage`.

### Fixed

- Harden the AG-UI envelope against shape drift and surface history-replay
  drift to the UI; close subscription and drain leaks on resume; terminal-state
  hardening; surface empty-thinking failed runs as an `ErrorMessage`.

## [0.85.1+47] - 2026-05-06

### Added

- Workdir files: `WorkdirFile` model and `getRunWorkdirFiles`, file listing and
  downloads in chat tiles, a `WorkdirFilesSection` widget, an authenticated
  bytes download path, and inline tap feedback with a tooltip.

### Fixed

- Switch downloads to `file_picker` so cancel actually cancels; use a save
  dialog on native platforms; grant the macOS write entitlement for
  user-selected files.

## [0.85.0+46] - 2026-05-04

### Added

- SSE resume: cancel-aware backoff, an in-flight reconnect banner, reconnect
  status mirroring, and friendly resume-failure copy; gate the Stop button
  during the orchestrator's idle window.

### Fixed

- Route `CancelledException` to `CancelledState`; honor cancel during
  tool-yield resume; clamp post-jitter backoff; cancel the underlying timer in
  `raceBackoff`.

## [0.84.1+45] - 2026-05-01

### Added

- Versions page and `AppRoutes` constants.
- GenUI foundation: `Surface` + `StateProjection` + `StateBus`, a reactive
  `agentState` signal on `AgentSession`, `HumanApproval`/`ToolApproval`
  extensions, `ToolCallsExtension`, a thread-tile spinner while running,
  `SessionCoordinator` + `StatefulSessionExtension`, and an `AppModule`
  lifecycle replacing `ModuleContribution`.

### Fixed

- Stop stacking approval dialogs; guard disposed sessions; propagate async
  dispose through `ShellConfig`.

## [0.84.0+44] - 2026-04-23

### Added

- Persist per-message expansion state across rebuilds.

### Changed

- Support haiku.rag 0.40 and 0.42 RAG state in one client; harden RAG snapshot
  parsing.

## [0.83.2+43] - 2026-04-21

### Added

- Unified `ExecutionTimeline` with nested activities and source preview;
  hydrate `ExecutionTracker`s from historical runs on thread reload; persist
  `ActivitySnapshotEvent`s on `Conversation`; typed `SkillToolCallActivity`
  view; an `ActivityLog` widget.

## [0.83.1+42] - 2026-04-20

### Added

- Inline upload event pills above the composer; GET list endpoints for rooms
  and threads; a `FileUpload` domain model; merged the server list into
  `UploadTracker` via a shared registry; a Dockerfile and nginx config.

### Fixed

- Surface silent upload failures; correct the thread-list GET path; refresh on
  room entry and thread selection.

## [0.83.0+41] - 2026-04-16

### Added

- `ConcurrencyLimitingHttpClient` decorator wired into the agent stack;
  `NetworkInspector` concurrency-wait events and a summary panel; handle new
  ag_ui reasoning and activity events.

## [0.82.8+40] - 2026-04-14

### Added

- LaTeX math rendering in markdown; a copy button on the execution thinking
  block header.

### Fixed

- Scope `MessageTimeline` state per thread; update the sidebar locally on
  thread create/delete/spawn; tighten rename validation.

## [0.82.7+39] - 2026-04-11

### Fixed

- Add `NSPhotoLibraryUsageDescription` to the iOS `Info.plist`.

## [0.82.7+38] - 2026-04-10

### Added

- File upload: `UploadTracker`, `uploadFileToRoom`/`uploadFileToThread` API,
  buffered multipart encoding, a paperclip attach button, a consolidated file
  indicator, and a room-info upload card; added `file_picker` and `mime`.

### Changed

- CI runs package tests with a unified coverage script; replaced the
  `HaikuRagChat` schema with `Rag`.

## [0.82.6+37] - 2026-04-09

### Changed

- Re-enabled document filtering with chunk-id-based deduplication.

## [0.82.5+36] - 2026-04-09

### Added

- Thread rename/delete: an overflow menu on `ThreadTile`, rename/delete
  dialogs, `RoomState`/`ThreadListState` mutations, and an
  `updateThreadMetadata` API method.

### Fixed

- Harden thread operations against backend edge cases.

## [0.82.4+35] - 2026-04-08

### Added

- Quiz module: quiz screen/module/flavor registration, start/question/results
  widgets, multiple-choice and free-text input, a signal-based session
  controller, deep-linkable quiz URLs, and entry points in room info, the
  lobby card, the welcome screen, and the sidebar.

### Fixed

- Gate the document-filter UI behind the `enableDocumentFilter` flag; refresh
  thread names on navigation and add pull-to-refresh.

## [0.82.3+34] - 2026-04-08

### Added

- Document filtering for RAG searches, with collapsible document chips.

### Fixed

- AG-UI event handling (equality, error recovery, `ActivitySnapshot`); prevent
  the Enter key from sending during an active session.

## [0.82.2+33] - 2026-04-06

### Fixed

- Reverted `very_good_analysis` and `test` bumps for Flutter 3.38.4
  compatibility.

## [0.82.1+32] - 2026-04-06

### Fixed

- Differentiate user and assistant message bubbles; fully populate
  `ColorScheme` from `SoliplexColors`.

## [0.82.0+31] - 2026-04-03

### Added

- Design-system tokens: `SoliplexColors`, spacing/radii/breakpoints, a
  typography builder with platform-specific monospace, a `SymbolicColors`
  extension, a `SoliplexTheme` extension, a `soliplexLightTheme` builder, and a
  barrel export.
- An "Add Server" button on the lobby sidebar; server URL in the room-info
  screen.

### Changed

- Decouple session concurrency from bridge concurrency; replace
  `HttpStatusColors` with `SymbolicColors`.

### Fixed

- Preserve AG-UI state across threads, failures, and session restores; fix a
  chunk-visualization crash spanning multiple pages and allow Esc/barrier
  dismiss; show full attempted URLs in connection errors.

## [0.80.1+30] - 2026-04-02

### Added

- Citations UI: a source-references resolver and adaptive chunk visualization
  (dialog on desktop, full page on mobile).
- Room-info screen with full feature display and navigation; a `RoomSkill`
  model; file-type icon utilities; exposed `toolRegistryResolver`.

### Changed

- Ported the `soliplex_agent` packages into the workspace monorepo.

### Fixed

- Extract citations during live runs, not just history replay; preserve
  expand state on scroll; eliminate whitespace on zoom.

## [0.80.0+29] - 2026-03-31

### Changed

- Bumped `flutter_secure_storage` to 10.0.0 and `shared_preferences` to 2.5.5.

### Fixed

- iOS code signing; public `ConsentNotice` export.

## [0.80.0+28] - 2026-03-30

- Baseline release. Earlier history predates this changelog.
