# Changelog

All notable changes to the Soliplex frontend app are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the `version+build` scheme from `pubspec.yaml`, bumped via
`dart run tool/bump_version.dart`.

## [Unreleased]

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
