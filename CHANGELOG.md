# Changelog

All notable changes to the Soliplex frontend app are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the `version+build` scheme from `pubspec.yaml`, bumped via
`dart run tool/bump_version.dart`.

## [Unreleased]

### Added

- Design: re-export `ClassificationTheme` and `ClassificationLevel` from the
  public API so adopters can configure classification without a direct
  `soliplex_design` dependency.
- Lobby: branded header in the server sidebar (logo, app name, and version),
  sourced from the flavor's `SoliplexBranding`.
- Lobby: account block in the sidebar footer showing the selected server's
  signed-in identity (avatar, name, and email), with a ⋮ menu that collapses
  the Network Inspector and Versions actions.
- Lobby: sort rooms by recent activity (a dropdown beside the view toggle),
  grouping them under "Today"/"Yesterday"/… section headers, and show each
  room's most-recent-thread time as a relative label ("3h ago") on its card.

### Changed

- Lobby: select a single server in the sidebar to view its rooms, replacing the
  multi-server show/hide model; the last selection persists across launches,
  and server management moves to a settings icon in the list header.
- Lobby: switch the two-pane layout at the desktop breakpoint (840) instead of
  a hardcoded width.
- Room: hide the document filter button in rooms with no filterable documents.

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
- soliplex_client: pin the `ag_ui` git dependency to a fixed ref for
  deterministic resolution; a floating HEAD pulled an incompatible release that
  broke web builds.

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
