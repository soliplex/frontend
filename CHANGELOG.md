# Changelog

All notable changes to the Soliplex frontend app are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the `version+build` scheme from `pubspec.yaml`, bumped via
`dart run tool/bump_version.dart`.

## [Unreleased]

### Fixed

- Reopening a thread no longer resets every step time in its events timeline to
  `0.0s`. The times were measured with a clock started when the timeline was
  rebuilt, and rebuilding replays a finished run far faster than it happened,
  so everything that had read correctly while the run was live collapsed to zero
  the moment the thread was loaded again. Step times now come from the times
  the events were emitted with, so the figures on a reopened thread reflect
  time the run spent rather than time the rebuild took. Each reply is measured
  from the moment its own stretch of the run began, so a thread with several
  replies starts each one's figures afresh rather than counting from the
  thread's beginning. A step the stored events cannot place in time — the
  run's error path records some events without one — shows no figure at all
  rather than a zero it cannot stand behind.
- A message carrying no text no longer animates a loading placeholder forever.
  A reply can be closed without any words ever going into it, and every one of
  those sat in the transcript pulsing as though it were still being written —
  several in a row on a single question read as an app that had hung. Any such
  message now reports that it holds no text, while one the server is still
  writing into keeps its placeholder. Why it is empty — a turn that produced
  no words, or words lost in transit — is not something the app can tell from
  the outside, so the wording offers no reason.
- Stopping a reply before its first word no longer leaves an empty message
  behind. A run cut short between the moment a reply opened and its first
  word had nothing on screen to preserve, but one was committed anyway, so
  the transcript kept a blank assistant message that said the assistant had
  answered with nothing — where the truth was that it had been stopped or cut
  off. Nothing is committed when there is neither text nor reasoning to keep,
  which is what the cancel path always intended.
- Bold, italic and links inside a quoted passage now render as written. Any
  emphasis a reply put inside a block quote arrived on screen as plain text —
  the markup was parsed and then discarded, so a quoted sentence lost every
  distinction it carried while the same sentence outside a quote kept them.
  Quoted passages also sit a little wider in their frame and a little tighter
  above and below.

### Removed

- **Library consumers:** `TextMessage.isStreaming`, which nothing in this
  repository set or read. Whether a reply is still being written is a fact
  about the run in progress rather than about a message, and the transcript
  now takes it from the streaming state. Passing the flag to `TextMessage`,
  `TextMessage.create` or `copyWith` no longer compiles; a fork that only
  passed it can drop the argument, and one that read it back was reading
  whatever it had passed, since nothing else ever wrote it.

## [0.103.0+86] - 2026-09-02

### Added

- A module can now declare which of its own screens are reachable without a
  session, so a deployment that adds its own — an intro or welcome page — can
  put it in front of an unauthenticated visitor instead of having it bounced to
  the server list. The declaration sits beside the route it names, so the part
  of the app that builds a screen is the part that says whether it needs a
  sign-in. Declared paths match exactly, so opening one screen does not open
  anything beneath it, and a path that names no route or is written in a form
  that could never match is refused at startup rather than silently ignored.
- A deployment can also choose where a signed-out launch lands, so that screen
  can be the first thing a new user sees rather than somewhere they have to
  navigate to. It moves only that one case: someone returning mid sign-in still
  completes it, and anyone whose stored server is already connected still lands
  in their room list. Naming a screen that would turn a visitor away, or one
  that does not exist, is refused at startup on every launch — not only the
  signed-out ones that would otherwise be the first to show it, so a machine
  that already has a server connected still surfaces the mistake.
- Writing a screen of your own no longer needs a routing dependency of your
  own, for building it or for testing it: the routing types a module declares,
  navigates with and is driven by in a widget test now come from this package
  directly. It is a curated set rather than the whole routing package — the
  types the module extension point's own signatures are written in — so a
  deployment reaching past it still adds that dependency itself.

### Changed

- **Breaking:** `runSoliplexShell` now takes the function that builds the
  configuration rather than the finished configuration — pass `flavor.build`
  where you passed `flavor.build()`, and await the call. Assembling a flavor can
  fail on a configuration mistake, and that failure happened before any screen
  existed: on iOS, macOS and Android the result was not a crash anyone could
  report but a launch that never finished, with the message that named the
  faulty route going nowhere. Building inside the call puts it on screen
  instead.

- **Breaking:** a top-level route whose path omits its leading slash is now
  refused at startup. The routing package requires the slash and checks for it
  nowhere, so such a route silently never matched — a screen that was already
  dead. A deployment carrying one used to lose that screen, or, where it was
  also the route the app opens on, launch into the routing package's own
  "page not found"; it now cannot launch until the path is corrected.
- **Breaking:** `ShellConfig.redirects` is renamed `moduleRedirects` and marked
  as being for tests, and `ShellConfig.redirect` is what a router should now
  install: the same module redirects, composed, with the public-path admission
  already in front of them. Installing the uncomposed ones turned the sign-in
  guard on the screens meant to be exempt — including the sign-in callback,
  which discarded a sign-in in flight — and there was no way to notice from the
  outside. `buildRouter` is unchanged.
- A configuration that is rejected now releases the modules it had already
  built, instead of abandoning them holding a server manager, HTTP clients and
  an inspector. One consequence reaches module authors: `onDispose` can now run
  on a module whose `build()` never did, because a duplicate namespace or a
  theme without its extension is refused before any module is built. Release
  what the constructor took; anything `build()` creates has to tolerate being
  absent. Teardown also continues past a module that fails it, so one module
  throwing no longer strands the ones registered before it.
- A deployment that already depends on `go_router` may see the analyzer report
  its own import as `unnecessary_import` in files that use only the routing
  types this package now re-exports. Deleting the import resolves it; nothing
  behaves differently, and a file reaching for anything beyond those types still
  needs it.
- The line under the composer now reads "<app name> is AI and can make
  mistakes.", and it renders on every deployment. It previously named the
  room's confidentiality level, which meant it appeared only where a
  classification vocabulary had been declared — so a deployment that declared
  none carried no caveat at all, while the caveat that a model can be wrong is
  true of all of them. The marking band above the conversation is unchanged and
  still appears only where a vocabulary is configured.

## [0.102.0+85] - 2026-08-28

### Added

- A run that ended without an answer now offers to report it, from the failure's
  own place in the transcript rather than from a banner that can be dismissed
  and does not survive a reload. A run the backend reported as failed offers to
  view or add to the note already filed for it; a run that finished without
  saying anything offers to report the problem. The note on file is read before
  it is shown, because submitting replaces it — so an edit adds to what is there
  instead of destroying it, and a note that could not be read is said to be
  unread rather than shown as absent. A report that does not reach the server
  leaves the dialog open with the text intact, and the warning that submitting
  replaces an existing note stays on screen while that error shows — a retry is
  when it matters most. The dialog is wide enough for that warning to be read
  in full.
- A run that fails now files a thumbs-down feedback record for itself, so the
  failure becomes discoverable. The backend records the error as it streams but
  keeps no queryable run status, and feedback is the only table an
  application-level query reaches — so a failed run was recorded and invisible
  to every such query. Only failures the backend itself reported are filed: a
  dropped connection is not, because the backend keeps such a run alive for the
  client to reconnect to and it often completes, and filing would record a
  successful run as failed. An unclassified failure is logged against its run
  instead of filed, since it may name a fault on this side rather than a
  backend outcome. The record names the failure's classification, the run's own
  error text and the client version, so two failed runs can be told apart in a
  review queue without opening either.

### Fixed

- Stopping a run while it was still thinking no longer blanks the exchange. The
  transcript kept nothing at all — no tile, no reasoning, no error row —
  whenever the stop landed before the first reasoning content arrived or while
  a tool call was still in flight, because the only copy of what was on screen
  lived in streaming state that the stop discarded. A cancelled run now keeps
  whatever had been shown, and still records nothing when nothing had been.
- The attached-files panel no longer strands open, and no longer reopens by
  itself. The control that opens it is the only one that closes it, and it is
  withdrawn once neither upload scope has anything left to show — so dismissing
  the last row left the panel holding up to 40% of the viewport for the rest of
  the visit with nothing able to collapse it. The request to open it is now
  withdrawn with the control, so a later upload no longer springs the panel back
  open over the conversation with no tap behind it.
- A room's uploaded-file list no longer shows a permanent error row when the
  installation configures no upload path for that scope. The server reports
  that by having no list to give, which read as a failure to reach one. The same
  bare 404 also answers an unknown room and one the caller may no longer read,
  so a list already on screen is kept and the refusal recorded instead of being
  silently emptied.
- A file picked in the welcome composer, before the thread it was destined for
  exists, no longer fails silently. Such a pick is recorded against the room
  scope, there being no thread yet to route it to, and that scope's surfaces
  were shown only for rooms that accept room uploads — so in a room that
  accepts only thread uploads the failure had nowhere to render.
- The file-attach button no longer disappears from a thread once that thread
  has a finished run. Attachment support was read from a `bubble-sandbox`
  namespace in the thread's replayed AG-UI state, which the backend no longer
  writes, so any thread whose state carried another namespace resolved to a
  hard "unsupported". Both scopes now read the room's capability, which is what
  the server actually gates uploads on.
- An upload refused for lack of permission now says so. The 403 branch tested
  `AuthException`, but the transport raises `PermissionDeniedException` for
  403, so the branch never ran and the server's own wording was shown instead.
- An upload to a scope the server has no upload path configured for (405) now
  reports that, rather than passing the backend's internal wording through.
- Tearing down a cancelled SSE subscription now observes the future
  `StreamSubscription.cancel()` returns, so an error raised while the stream
  generator unwinds — the transport's injected `CancelledException` among them
  — no longer reaches the zone unhandled. Applies to the four teardown sites
  in `RunOrchestrator`; other unguarded callbacks on the cancel path are
  unchanged.
- The upload request-body pipe observes that future too, on both the Dart and
  the Cupertino client, so an error raised while the multipart body unwinds no
  longer reaches the zone.
- Cancellation is now observable to client-side tools and session extensions.
  `AgentSession` owns a cancellation signal for the session's lifetime instead
  of exposing `RunOrchestrator`'s request-scoped token, which is absent for the
  whole tool-execution window and at extension-attach time — so a tool polling
  `ToolExecutionContext.cancelToken` never saw a cancel, and a pending tool
  approval was not denied when the session was cancelled.
- Cancelling an upload on iOS and macOS reports the cancellation rather than a
  network failure. NSURLSession surfaces an aborted upload as a client error,
  so the cancel arrived as a `NetworkException` and the upload was shown as
  failed instead of cancelled.
- Pressing Stop denies a pending tool approval even when the run already
  failed, instead of leaving the approval unresolved.
- A session cancelled while its extensions are attaching no longer starts a
  backend run.
- The fallback from the native HTTP client to `DartHttpClient` is recorded
  instead of downgrading silently.
- Errors contained inside the HTTP stack reach the app's log sink from the
  platform clients, and are rendered without echoing the input they were
  thrown over.
- Pressing Stop always leaves the session in a terminal state.
  `AgentSession.cancel()` previously let a throw from the orchestrator escape
  into the widget callback that pressed the button, where Flutter printed it
  and carried on: the press did nothing, the run kept streaming with no way to
  reach it again, and the runtime waited on the session's result forever,
  stalling every queued spawn behind it.
- A run that throws instead of reaching a terminal state now settles the
  session rather than stranding it, for the same reason.
- Cancelling a spawn on a torn-down room or thread view no longer crashes.
  `RoomState.cancelSpawn` and `ThreadViewState.cancelRun` wrote a signal their
  own `dispose` had already disposed, which raises rather than being ignored;
  every other method on both classes already returned early.

### Added

- `Room.acceptsRoomUploads` and `Room.acceptsThreadUploads` carry the server's
  per-scope upload capability, each folding in the sandbox skill and the
  installation's upload path for that scope. They replace inferring the answer
  from the room's skill list, which could not see the upload path at all.
- Uploading to a room is offered only to administrators, and only once the server
  has said so. The server has always required one, and the refusal used to
  arrive after the user had chosen a file. Members still see the room's
  uploaded files — the agent cites them — and the controls are replaced in
  place by a line naming who adds them, so a room that already has files
  explains the absence as readily as an empty one. The answer is asked once per
  signed-in session and dropped both when that session ends and when the
  signed-in identity changes — signing in from an expired session never passes
  through a signed-out state, so neither trigger covers the other.

  A check that cannot answer withholds the controls and says only that. The
  upload authorizes through the same installation-side administrator check this
  answer comes from, so a check that cannot answer cannot authorize either, and
  offering the controls would offer an action whose every use fails — a folder
  of N files sent in full to be refused N times. It does not borrow the
  refusal's wording, which names who does add the files and so asserts
  something about the user that nothing established; a retry sits beside it
  instead. The controls render in their loading state for at most three
  seconds, because the request queues behind every other one to that server —
  but the bound does not end the request, and an answer arriving later still
  replaces what the bound wrote, in either direction. A refusal the server
  delivers over 403 is an answer and withholds the controls, but unlike one
  delivered over 200 it is not kept for the session: that one is the
  installation's, while a 403 may be a gateway's, so the next screen asks again
  rather than locking out an administrator it was never about. Failures are
  recorded.

- A server that reports no upload capability is recorded once, rather than
  silently withholding every attach control. Both the room listing and a
  single-room fetch report it, so a deep link into a room is covered too, and a
  field of the wrong type costs its own value instead of dropping the whole
  room from the lobby.
- `installUncaughtErrorLogging()` records errors no `catch` in the app saw —
  the framework's, via `FlutterError.onError`, and the root zone's unhandled
  asynchronous ones, via `PlatformDispatcher.onError` — into the same log sinks
  the diagnostics screen reads. Both are additive: the framework's own console
  dump and the platform's report of an unhandled error still happen. Host apps
  embedding this package as a library can call it alongside `installLogSinks()`.

### Changed

- **Breaking (library):** `Room.supportsAttachments` is replaced by
  `Room.acceptsRoomUploads` and `Room.acceptsThreadUploads`. The server gates
  room and thread uploads on separate installation settings, so an unqualified
  name had to silently pick one.
- **Breaking (library):** `sandboxSkillName` is removed. Nothing infers upload
  capability from the skill list any more, so it named a wire key no decision
  reads. This requires a backend that publishes `has_room_uploads` and
  `has_thread_uploads`.
- **Breaking (library):** `ThreadHistory.supportsAttachments` is removed.
  Nothing produces the state it read, and it has no replacement — attachment
  support is a property of the room, not of one of its threads.
- Room Information reports attachments per scope, as `Room attachments` and
  `Thread attachments`, instead of a single row that could not show a
  deployment configured for one scope but not the other.
- **Breaking (library):** `AgentSession.cancelToken` is now scoped to the
  session rather than the active request: it is one instance for the session's
  lifetime, cancelled by `cancel()` or `dispose()`. It previously answered a
  fresh, never-cancelled token whenever no request was in flight.
- `DartHttpClient`, `CupertinoHttpClient`, `WebXhrHttpClient` and
  `createPlatformClient` accept an optional `onDiagnostic` handler, defaulting
  to `dart:developer` as the other clients in the stack already did.

## [0.101.0+84] - 2026-08-21

### Added

- Public logging API for apps embedding this package as a library:
  `installLogSinks()`, `LogManager`, `Logger`, `LogRecord`, `LogLevel`, the
  `LogSink` interface, the console, stdout and memory sinks, and
  `LoggerFactory` — which carries `LogManager.getLogger`, and without which the
  exported `Logger` could never be obtained.
- `describeFailure` in the logging API, which renders a caught exception for a
  log record without echoing the input it was thrown over.

### Fixed

- Decode failures no longer carry the data they failed on into the log buffer
  the diagnostics screen displays and can export to a file.
  `FormatException.toString()` embeds roughly 78 characters of its source, so a
  corrupt stored session logged its access and refresh tokens and a corrupt
  composer entry logged the user's unsent draft. Thirteen sites now record the
  failure's reason and position instead of the exception object, and keep the
  stack trace.
- A token refresh that fails for an unexpected reason now records what
  happened. `unknownError` collapsed five distinct failures and the exception
  was discarded, so the log could report that a refresh failed but never why —
  the case behind sessions that could only be recovered by deleting and
  re-adding the server.
- A response body that cannot be decoded is now reported by its content type
  and size instead of by quoting the body, which named a credential when the
  endpoint returning it was the MCP token, and which surfaced in the on-screen
  error text as well as the log.
- Apps embedding this package as a library can now get logging. `LogManager`
  discards every record when no sink is registered, and the function that
  registers them was reachable only through a `src/` path with the logging
  package not re-exported, so a host writing its own `main()` had no supported
  way to turn logging on. Installing sinks stays the host's decision — nothing
  is registered on its behalf.
- The file picker's boot-time cache cleanup (Android and iOS) no longer fails
  silently. The plugin reports a failed delete by resolving with `false`, or
  `null` when Android has no attached activity, so the result is now checked as
  well as the throw.

## [0.100.0+83] - 2026-08-20

### Changed

- The Diagnostics screen now shows the app's own log records beside the
  network requests, and can save both as a single plain-text report. The
  records are the half of a failure the request list cannot show — why a probe
  gave up, what the platform error behind a friendly message actually was,
  whether a name resolves — and reading them used to mean attaching a debugger
  or launching from a terminal, neither of which is true of an installed app
  on a device. A `Requests` / `Logs` switch chooses the pane; clearing takes
  whichever one is showing, while the saved report always carries both,
  unfiltered, so nothing looks absent that was only filtered out. The report
  gives every exchange an outcome, including one still in flight, since a
  request that never came back is usually the reason for saving a report at
  all, and it times everything in UTC so it can be read beside a server's own
  logs. The sign-in screen's ⓘ button becomes a ⋮ menu offering Diagnostics
  and Versions, the same pair the room and lobby menus already offer, so the
  screen can be reached without a connected server — a user who cannot sign in
  has no route through the lobby, and that is exactly when the records are
  worth reading.

- A failed sign-in or connection now leaves a record behind. Until now the app
  logged through `dart:developer`, whose entries only exist while a debugger is
  attached, so nothing survived in the builds where these failures actually get
  reported — the user saw one friendly sentence and there was no way to tell a
  name that does not resolve from a name that resolves while something above DNS
  blocks the request, or from a session the app already believed was live. Log
  records are now retained in the app itself, and a failed connection attempt
  records every address it tried, the platform error behind the friendly message,
  how long it took, and whether the name resolves when asked directly. A server
  restored as connected on credentials that had already expired — which opens the
  app as if signed in and then fails every call — is called out specifically.

- The developer menu entry that opens the captured HTTP traffic is now
  called Diagnostics, matching the module behind it, and the route it opens
  is `/diagnostics` rather than `/diagnostics/network`. The screen shows the
  same captured requests it always has.

- The iOS build declares one minimum OS version throughout. The app has
  required iOS 16 since the platform was configured, but the bundled
  `App.framework` still announced 13.0, so the two disagreed about the oldest
  system the build supports. Both now read 16.0. Apple reads only the app's own
  value, so the version the App Store enforces is unchanged.

## [0.99.3+82] - 2026-08-19

### Changed

- Failure messages can now be selected and copied. Until now the transcript was
  the only place text could be selected, which left the strings worth reporting
  — the exception behind a failed load or send, the reason a connection or
  sign-in was refused, an upload's error, the detail behind a failed sign-out —
  readable but impossible to get out of the app except by retyping. The
  send-failure banner also gains a copy button, because it shows at most two
  lines and a drag can only take the text that was painted. Server maintenance
  and outage notices are selectable for the same reason: they are written to be
  acted on elsewhere. Attached filenames can be selected alongside the upload
  errors beside them. A room's details are selectable throughout — the model
  name, provider, tool kinds and skill fields a user would quote when asking
  about a room's setup.
- Typing on the connect screen while the URL field has lost focus no longer
  swallows the first character. The field only takes focus after the keystroke
  has been dispatched, so until now that character went nowhere; it is now
  entered along with the focus. A keystroke only counts as typing, so a shortcut
  chord keeps its meaning and leaves any selection alone, control keys enter
  nothing, and a keystroke aimed at a dialog over the screen no longer reaches
  the field behind it.
- The full-size image and SVG viewer now has a close button in its top-right
  corner. Tapping the backdrop already dismissed it, but nothing said so: on a
  full-bleed image there is no visible backdrop to aim at, and a screen reader
  user had nothing to land on at all. The viewer's own rotate and reset controls
  move to the opposite corner to keep both reachable.
- The information level under the composer now reads "Information level is:
  LEVEL" and sits tighter to the composer, so the level itself is what the line
  ends on rather than trailing off into words that repeat what the screen
  already shows.

### Fixed

- A status message that operators withdraw now clears within one poll instead
  of lingering for hours. The app asked for the same address on every poll, so
  a browser or system HTTP cache was free to answer from the copy it already
  held; with the file served without any statement of how long it stays good,
  those caches fall back to a guess proportional to the file's age, which for a
  message posted days earlier runs to hours. Each poll now carries a value no
  earlier poll used, which no cache can have an answer for. Edits to a posted
  message reach readers on the same schedule.

## [0.99.2+81] - 2026-08-17

### Added

- The room's confidentiality marking is shown inside the chat, where until now
  it could only be read from the lobby: as a band across the conversation in
  the level's own colors, directly under whatever names the room, and as a line
  under the composer — "Information level is X for this room" — in the slot
  other chat products give their standing caveat, so the marking is the last
  thing read before a message is sent. The marking gets a row of its own rather
  than a place in the header, because a marking is a fixed cost and a header's
  width is not: sharing that width, a long marking leaves nothing of the room
  name at the sizes phones and split-screen tablets run at. Both are suppressed
  on a deployment that configures no markings, as the lobby's badge already is.
  Like every other marking in the app, both show the deployment's default
  level: no per-room value exists yet.

### Changed

- A server's address now reads without its `http(s)://` scheme everywhere it
  names a server compactly — the room header, the lobby's app bar title on
  narrow layouts, and the server sidebar tile — so the same server reads the
  same way on both sides of the layout breakpoint. In the room header a link
  glyph leads the line in the scheme's place. A server that reports a
  human-readable name still shows that name, untouched.
- The lobby's two-pane layout drops the title band that named the selected
  server above the room list. The sidebar beside it already names the server,
  so the band repeated what was on screen.

### Fixed

- A deployment whose marking ladder starts at the design system's neutral
  built-in level no longer suppresses every marking in the app. Whether a
  marking is shown now follows from what the deployment declared rather than
  from what its lowest level happens to look like, so a room sitting at the
  bottom rung reads as marked instead of as unmarked.
- The room header no longer clips the server address at enlarged OS text sizes.
  An app bar's toolbar is a fixed-height box that clips an oversized title
  without reporting anything, and the header stacks the room name over the
  server it belongs to; past a certain system text size those two lines stop
  fitting and the address loses its descenders. The toolbar now sizes itself to
  the title it has to carry. It reproduces only with the OS text size raised, so
  a stock emulator does not show it.
- The app bar no longer takes on a blue cast once content scrolls beneath it.
  Material tints a scrolled-under bar toward the brand's own accent color, so on
  mobile the bar shifted away from the surfaces around it the moment the
  conversation moved under it. The bar now stays flat on every platform and at
  every scroll position, with its bottom border as the only separator.

## [0.99.1+80] - 2026-08-06

### Added

- Attached images are numbered, so one can be referred to in conversation —
  "what does the sign in image 7 say?". The number runs across the whole thread
  rather than restarting each message, so it names one image for as long as the
  thread lasts. It is badged on the thumbnail, and carried on the marker in the
  sentence wherever the message has text for a marker to sit in. The same number
  is sent to the model as a short text label beside each image, which is what
  gives it a name to answer to: an image block's own metadata is not shown to
  the model. An attachment that cannot be shown still spends its number, so
  nothing after it is renumbered into a number already used, and it is sent as
  neither an image nor a note that one is missing — asked about a number nothing
  carries, a model can only say it has no such image, whereas announcing the
  absence invites it to guess at what it cannot see. An attachment that was
  never numbered — from a payload that carries none — is shown and sent without
  one.

### Changed

- A user message's images no longer sit inline in the sentence at full size.
  The attachments now form a row of thumbnails above the message, and each one
  leaves a small marker in the sentence at the spot it was written, so the text
  reads exactly as it was typed and the order the images were placed in stays
  visible. The marker is text-scale deliberately — a thumbnail set into a line
  of body text makes that one line as tall as the picture, which breaks the
  paragraph around it. A message carrying attachments and no text of its own
  shows the thumbnails alone — with no sentence to hold a place in, markers
  would be the same row twice. Tapping an image's thumbnail or its marker opens
  every image in that message in the zoomable browser, starting at the one
  tapped. An image whose bytes will not decode, and an attachment that could not
  be rebuilt at all, each keep both their thumbnail and their marker so neither
  the row nor the sentence shifts around a loss, though neither opens anything;
  the tooltip and screen-reader announcement naming what is missing are
  unchanged.

## [0.99.0+79] - 2026-08-06

### Added

- Images can be attached to a message. An add-image button beside the composer
  opens the platform's image picker, and each image picked lands at the caret as
  a chip, so a sentence can be written around its images and reaches the model
  in the order they sit in. Several can be picked at once; on iOS a multi-pick
  may arrive in a different order from the one it was chosen in, which the
  platform does not report. The button is offered in every room: an inline image
  is a property of the model, not of the room's skills, so it does not depend on
  the paperclip's sandbox capability. Once picked, bytes are sent untouched —
  nothing in the app decodes, re-encodes, or scales them, so a PNG cannot be
  inflated, a photo's EXIF cannot be stripped, and an animated GIF keeps its
  frames. PNG, JPEG, WebP and GIF are accepted, up to four images and 15 MB a
  message; an image is typed by what its bytes hold rather than by its name, so
  one saved under a misleading extension is recognised for what it is. Anything
  the message cannot carry is left out rather than sent, and said so in a line
  under the composer that a screen reader announces — by name where the file
  itself is the problem, as a limit where the message is. On iOS the picker is
  asked for a compatible representation, so a photo an iPhone shot as HEIC
  arrives as JPEG — re-encoded by the system before the app sees it — and the
  copy the picker leaves behind is discarded as soon as the app is done with it,
  whether or not it could be read.
- On a composer narrower than a tablet, the document filter and thread upload
  now share one menu of labelled items — `Filter documents` and `Upload
  files…`, plus `Upload folder…` wherever folders can be picked — so the text
  field keeps a usable width with the add-image button beside it. At tablet
  width and above all three stay separate buttons.

- **Library consumers:** `soliplex_client` exports a `MessagePart` type —
  `TextPart` for a run of text, `ImagePart` for image bytes with their MIME
  type — and an optional `parts` list on `TextMessage`. A user message carrying
  parts is sent as AG-UI multimodal content with each image inlined as base64,
  so text and images reach the model interleaved in the order given. A message
  without parts is unchanged on the wire. The multimodal form is used only when
  a part is not text: a list holding nothing but text, or nothing at all, falls
  back to the plain string, because an empty content array makes the backend
  discard the message's turn without reporting an error. A message composed as
  plain text carries a single text run, so no screen behaves differently.
- **Library consumers:** `TextMessage.fromParts` builds a user message from an
  ordered part list, deriving `text` from the parts so a caller of it cannot let
  the two disagree, and a `plainText` getter on `List<MessagePart>` flattens a
  part list to its text alone — runs concatenated in order, images dropped.
  `fromParts` throws `ArgumentError` for a part list carrying neither an
  attachment nor any text, because such a payload reaches the wire as empty
  content and the backend discards the turn without reporting an error.
- **Library consumers:** `MissingAttachmentPart` is a third `MessagePart`
  alongside `TextPart` and `ImagePart`, standing in for an attachment a message
  was sent with whose content cannot be rebuilt, and carrying the declared MIME
  type and a `MissingAttachmentReason` (`undecodable`, `unsupportedType`,
  `remoteSource`). It has no wire form and is dropped when a message is
  converted for sending. A `hasAttachment` getter on `List<MessagePart>`
  reports whether any part carries something other than text. Code that
  switches over `MessagePart` exhaustively gains a case.
- A user message carrying image parts now renders them in its bubble: text runs
  read as text and each image sits inline where it was placed, so a sentence
  written around its images still reads as one sentence. Tapping an image opens
  every image in that message in the zoomable browser, starting at the tapped
  one, so a photo that arrived sideways can be rotated. An image whose bytes
  will not decode, and an attachment that could not be rebuilt at all, each show
  a placeholder in their own slot. Because the glyph looks the same whichever
  loss produced it, the slot says what is missing — and the kind of file it was
  — as a tooltip on hover or long-press, and as the screen reader's
  announcement. A message with no parts renders exactly as before.

### Changed

- The chat composer's controller can carry images inline in its text — one
  code unit each, rendered as a chip and split back out into an ordered part
  list on send. A composer holding none delegates its rendering whole to
  `TextEditingController`, IME composition underline included, so a screen
  without images behaves exactly as before.
- A composer draft held across a failed send or an authentication round trip
  keeps each image's position, as a placeholder the user removes before
  sending. Bytes are
  deliberately not persisted — drafts live in `SharedPreferences`, which
  Android reads whole into memory at first access — and the source images are
  still on the device. Dropping the images silently instead would send a
  sentence written around pictures that are no longer in it. A draft of images
  and no caption is kept too, where an image-only payload previously flattened
  to an empty string and left an older draft in the slot to be restored in its
  place.
- **Breaking (library consumers):** the send path carries an ordered
  `List<MessagePart>` where it previously carried a `String`. This affects
  `AgentRuntime.spawn` and `MultiServerRuntime.spawn` (`prompt`), and
  `AgentSession.start` (`userMessage`). Wrap an existing call's text in a
  single part to migrate: `prompt: 'Hello'` becomes
  `prompt: [TextPart('Hello')]`. The text-only APIs for spawning a child agent
  from a tool — `spawnChild`, `delegateTask` — and the `AgentApi` platform
  callback are unchanged, since a prompt from those sources is always text.
  Nothing about a sent message changes on the wire, and no screen behaves
  differently: a message composed as plain text still travels as a bare string.
  A draft held across an authentication round trip still restores its text.
  Code reading a conversation does see one difference: the echo of a sent
  message now always carries `parts`, where it previously carried none.
- **Library consumers:** thread history no longer fabricates
  `TEXT_MESSAGE_START` / `CONTENT` / `END` events for a user message. The
  backend never streams the user's own turn, so history now rebuilds that
  message directly from the run's persisted input and appends it ahead of the
  run's real events — the same shape the live path already used, where the
  message is seeded into the conversation before the stream opens. The messages
  a thread reconstructs to are unchanged, including their order and timestamps.
  Two consequences for code reading `ThreadHistory.runs`: a run's event list no
  longer carries those three synthetic events, and for any run whose input
  carried a user message, the ids of its `DroppedEventMessage`s
  (`dropped-<runId>-<index>`) shift by three, since the index now refers to the
  run's actual wire payload.

### Fixed

- Reloading a thread now restores the images a user message was sent with. A
  message whose content was an ordered list of parts previously lost all of it,
  its text included, and came back blank; it now hydrates into the same ordered
  parts with its text re-derived from them. Content the app has no way to hold —
  an image given as a URL instead of bytes, audio, video or a document, or bytes
  that will not decode — becomes a placeholder in the slot it occupied, so the
  message reports what it was sent with instead of reading as though it never
  carried an attachment. Such a placeholder has no content to send, so a
  reloaded message goes back to the model without that attachment.
- A malformed piece of a user message costs no more than itself. Each element of
  an ordered payload is read on its own, so one entry this protocol version
  cannot name leaves its siblings intact — the message's text and its readable
  images alike — where before a single unreadable element blanked the whole
  message. Whatever cannot be read is logged with the message, run and thread it
  belongs to, and no single message or run can fail a thread's history load.
- A user message whose id is blank on the wire no longer swallows the turns
  after it. Such an id was taken at face value and keyed every blank-id turn in
  a thread to the same message, so all but the first lost its bubble and their
  citations piled onto one turn; a blank id is now treated as absent and the
  message is keyed to its run instead. A run entry whose own `run_id` is blank
  is rejected for the same reason, since that id is what a message without one
  falls back to.
- A run whose stored events end before any terminal event no longer hands its
  half-streamed reply to the run after it, where that run's terminal event
  committed the text under the wrong run and out of order. Streaming state is
  now scoped to the run it belongs to, since each run is its own stream.
- Pressing the platform's paste chord in a room — Cmd+V on macOS and iOS, Ctrl+V
  elsewhere — no longer does nothing when the composer is unfocused. One keypress
  now moves focus to the composer and inserts the clipboard's text, over the
  composer's selection when it has one. Every other chord keeps its meaning: copy
  and select-all still belong to the transcript, and a chord that is not the
  running platform's paste chord is left alone. Only text is read: with no text
  on the clipboard focus still moves and nothing is inserted. The chord does
  nothing at all while a thread is still loading its messages or while a reply is
  streaming, since the composer takes no text in either state. Each press inserts
  the clipboard once, including a second press made while the first is still
  waiting on a slow clipboard; holding the chord down repeats through the
  platform's own paste, as it does in any focused field. On browsers that withhold
  clipboard reads from a page, the first press moves focus and a second pastes
  through the browser's own path.
- Typing or pasting with the navigation drawer open no longer moves focus to the
  composer behind it, or routes clipboard text there.

## [0.98.2+78] - 2026-08-04

### Changed

- The execution timeline renders an activity from the AG-UI envelope rather than
  from a skill-specific schema. AG-UI defines an activity as an id-keyed store of
  opaque `content`, and names no vocabulary for what is inside it — so
  `skill_tool_call` / `skill_tool_result`, with their `tool_name` / `args` /
  `result` / `status` keys, were one backend's convention riding inside a spec
  envelope, and that backend no longer emits them. Any `activityType` now gets a
  row, labelled by its type, disclosing its content; previously every type but
  those two was dropped before reaching the screen. One reading of the old
  convention survives, because it is what keeps threads recorded before the
  backend change legible: a row takes its label from `content['tool_name']` when
  that is a non-empty string, so those rows still read `search` and `cite` rather
  than `skill_tool_call`. Absent or wrong-typed, the label falls back to the
  activity type rather than the row vanishing.
- An activity row discloses its whole content, so replaying an older thread shows
  every key the record carried. It used to show a single argument picked out of an
  `args` payload, which hid the rest of the record — and which only had an `args`
  payload to read because the fold synthesized one (see below).
- An activity row no longer shows a status icon or a status word, and its label
  no longer shimmers while the activity is in flight. AG-UI's activity events
  carry no status field and no stored record carries a `status` key, so all three
  were synthesized from the `activityType` string: a settled row showed a success
  check because its type read `skill_tool_result`, a value that did not
  distinguish a completed call from a failed one. The row no longer reserves the
  icon's width either; a nested row's indent already lands its chevron on the
  label of the step it belongs to.
- A replacing activity snapshot now stores its content verbatim. The fold used to
  carry a call phase's `args` onto the result snapshot that replaced it, to keep
  one row rendering its inputs across the boundary. AG-UI's `replace` is
  destructive, so carrying a key across it presented a record state no backend
  ever sent; with content opaque, nothing in that layer can know which keys would
  be worth carrying anyway. A key the new snapshot omits now stays omitted. A
  stored call/result pair still renders as one row, disclosing the result.
- An activity snapshot no longer sets the streaming phase label. It was read from
  `content['tool_name']`, announcing a tool call from a payload the protocol says
  nothing about; `TOOL_CALL_START` is the event that names a tool, and it already
  sets the label.
- A citation is labelled by its document's filename in preference to the
  document's title; the title is the fallback when the URI names no file — a
  URI that is an id rather than a path included, so a document addressed by a
  bare UUID still reads by its title rather than by the id. A title that is
  only whitespace is no longer a label either; such a citation reads
  `Unknown Document` instead of rendering an empty one. The
  filename identifies the file a chunk came from — it names an embedded file
  rather than the PDF it was found in, and it matches how the same document is
  labelled in the list and the picker. *The preference itself* has no visible
  effect unless the backend is configured to generate document titles, since it
  otherwise sends none; **a deployment that does have titles will see every
  citation relabelled**, in the citation row, in a copied citation, and in the
  chunk preview's heading.
- Every document's display name is percent-decoded and has any query string or
  fragment dropped, not just an attachment's, since all of them now read one
  parse of the URI. `annual%20report.pdf` reads `annual report.pdf`, and
  `handbook.pdf#page=3` reads `handbook.pdf`. A URI that carries its filename in
  a query string rather than its path shows the last path segment instead —
  `/download?file=report.pdf` shows `download`. A filename holding an unescaped
  `#` is cut there, so `invoice#1234.xlsx` reads `invoice`: from the URI string
  alone that `#` and a `#page=` fragment are the same shape, and two such
  documents differing only after the `#` become one label and one glyph.

- An expanded citation shows the cited document's title, which nothing displayed
  before: the row's own label is the filename, so a title had no home. The row
  is absent entirely — its label included — for a document with no title, which
  is every document unless the backend is configured to generate them, and for
  one whose row label is already the title, so the same string is never printed
  twice.
- A citation's PDF preview affordance reads the cited file's name rather than
  the raw URI, so a PDF addressed with a page fragment or a trailing escape —
  `handbook.pdf#page=3` — keeps its preview button instead of losing it to a
  URI that no longer ends in `.pdf`. This was the last file-type check not
  routed through the URI parse; an embedded file is still typed as itself, so a
  spreadsheet inside a PDF offers no page preview.
- A document's origin link carries its whole address on hover, wherever that
  link appears — a citation, the document picker, the room's document list. The
  link text keeps host and path alone — dropping the scheme, any credentials
  and port, the query and the fragment — and then ellipsizes what remains, so
  the address actually being opened could not be read. Two addresses differing
  only by port read identically without it.

### Fixed

- An expanded activity row's body clamps to eight lines with a "Show more"
  control, the way a tool call's arguments and result already did. It rendered in
  full before, on the assumption that an activity's detail was a short query —
  true while the row showed a query, false once it showed a whole content payload
  with a retrieval result inside, at which point one open row buried every row
  below it.
- A file embedded in a PDF is named and typed as itself. The backend ingests one
  as its own document and records the relationship in the document URI, which
  three separate places used to interpret three different ways: the document list
  and picker showed the container's name with the whole URI fragment glued on, the
  file-type glyph described the container rather than the embedded file, and a
  citation of the embedded file was labelled with the container's name. All three
  now read one parse of the URI, so an attachment shows its own decoded filename
  and its own glyph wherever it appears, and a citation names the document the
  text actually came from.
- A citation of an embedded file names the documents containing it, beneath the
  file's own name — `in annual-report.pdf`, chaining through each level when a
  file is embedded two deep. Now that a citation names the embedded file rather
  than its container, nothing else said where it lives: a configured browser
  link drops the URI fragment the relationship is encoded in, and the raw URI
  shown in that link's absence is one ellipsized line of percent-encoded text.
  Each line holds to one line, so a citation is the same height whatever its
  names run to, and one hover covers both — which also recovers a long filename
  on a citation of a document that is embedded in nothing, where before there
  was no way to read a name once it was cut.
- A document whose URI names no file — one ending in a slash — no longer renders a
  blank label in the list, the picker or the attachment chips, and no longer
  renders a blank citation. In the list it falls back to the document's title,
  then to the raw URI, which is the only string left that tells one such row from
  another; a citation with no title reads "Unknown Document". A title that reads
  as nothing but whitespace is passed over rather than taken, and a name that
  decodes to nothing falls back the same way, rather than rendering as an
  invisible label.
- A display name is trimmed, so a filename delivered with escaped padding
  (`report.pdf%20`) no longer renders with invisible whitespace, nor loses its
  file-type glyph to an extension that still carried the padding.
- A row for an embedded file names the document containing it, in the room's
  document list and in the document picker — `in annual-report.pdf`, chaining
  through each level when a file is embedded two deep. Searching a container's
  name has always returned the files embedded in it too, because an embedded
  file's URI contains its container's; those rows arrived labelled only with
  their own filename, with nothing saying why they matched.
- A row name too long for its column can be read in full by hovering it, on both
  surfaces, and on the composer's document chips. Each name holds to one line so
  a row's height does not depend on what it is called, and the URI beneath it is
  percent-encoded, so a cut name had no decoded form to be read anywhere.
- Expanding a document in the room's document list shows its title, when the
  backend supplied one and it says something the row's own label does not. Nothing
  displayed the title once the filename became the label; with title generation
  off — the default — this shows nothing.
- A document the backend sent no title for now carries none, rather than carrying
  its own URI as a stand-in title. Apart from the whitespace case above, the name
  every surface renders is unchanged: the fallback to the URI moved to where the
  label is chosen, so asking whether the backend titled a document now has a
  straight answer.

## [0.98.1+77] - 2026-07-31

### Fixed

- Citations render again. The backend now carries a run's cited set in a single
  `STATE_SNAPSHOT` emitted just before `RUN_FINISHED`, in place of the
  per-invocation `STATE_DELTA` stream it used to emit. Both frontend
  accumulation sites were gated on `STATE_DELTA`, so every turn resolved zero
  sources — live and on reload, with nothing logged. A turn now seeds the
  run-scoped state keys (`citations`, `searches`, `executions`) empty, which
  makes any namespace carrying citations in the terminal snapshot definitionally
  that run's, and both the live orchestrator and thread replay accumulate the
  snapshot. Requests shrink as a side effect: `searches` carries base64 figure
  bytes and `executions` captured stdout, and neither is echoed back for the
  backend to discard any more.
- The state-delta path is unchanged and still needed — the run-feedback tool
  emits a state delta of its own, and a thread recorded before the backend
  change replays as deltas. One limitation comes with replaying such a thread in
  a room that routes more than one retrieval capability: its stored snapshot
  really does echo a prior run's `citations`, and nothing in the record
  distinguishes that echo from a genuine retrieval, so a turn whose namespace
  was never invoked can show the stale sources that namespace last cited. Rooms
  with a single retrieval capability are unaffected.
- Chunk previews no longer inherit a server-side default. `expand` was declared
  `true` on `getChunkVisualization` but only transmitted when it was `false`, so
  the default path sent no parameter at all and took whatever the server picked
  — a default that has since flipped to `false`. The client now always transmits
  the value and declares `false`, so the value on the wire is the value applied
  and it agrees with the backend rather than depending on it. `expand` has an
  effect only when no doc item refs are supplied, which is exactly the bare
  chunk-id preview in room info; that preview highlights the chunk itself rather
  than re-expanding the section around it. Previews opened from a citation
  supply refs and are unaffected.
- The execution timeline carries a tool call's arguments and result again. The
  nested detail rows were fed by `skill_tool_call` / `skill_tool_result`
  `ACTIVITY_SNAPSHOT` events emitted by the sub-agent runtime the backend
  replaced; nothing constructs one any more, so no nested row was produced at
  all and the timeline was a flat list of tool names. Retrievals now arrive as
  ordinary tool calls, so the detail comes from `TOOL_CALL_ARGS` and
  `TOOL_CALL_RESULT` and expands from the step row that already represents that
  call — one row per call rather than a row nested beneath itself, because the
  two-level call tree the nesting mirrored no longer exists. Arguments display
  the field carrying the intent when there is one (a script, executed code, a
  search query, a shell command) and the whole object otherwise; a tool that
  takes no arguments yields no block rather than an empty one, and while a call
  is still streaming its arguments are a JSON prefix, which renders as-is rather
  than being withheld until it parses. The result body is included because it is
  the only place in the chat UI a tool's failure message reaches the user at
  all: AG-UI has no way to express a failed outcome, so a search that hit its
  limit or a code execution that raised returns its message through the ordinary
  result field, indistinguishable from success. Both blocks clamp to eight lines
  with a show-more control, since a retrieval result runs to tens of thousands
  of characters and would otherwise bury every row after it; the control appears
  only when the body is measured — at the text scale it will render at — to
  overflow, and copying still takes the whole body.
- A tool call's result and its completion tick now settle on the same row. Both
  are addressed by tool-call id, where completion previously settled whichever
  step started most recently; a toolset that does not declare itself sequential
  can overlap calls, so one call's result arriving would put a check mark and an
  elapsed time on a sibling call's row that was still running. A result for a
  call the timeline never opened now settles nothing at all, rather than
  crediting whichever row happened to be last. A run that finishes having opened
  a call whose result never arrived logs it, so detail lost in transit is not
  silent.

## [0.98.0+76] - 2026-07-30

### Changed

- The `ag_ui` dependency moved to hosted `^0.3.0` (from a git ref on 0.1.0),
  which adds multimodal `UserMessage` input, fractional `timestamp` coercion,
  and `encryptedValue` snake_case parity. On the SSE path this app uses, 0.3.0
  also flushes a final unterminated event at end-of-stream, corrects WHATWG
  handling of an empty leading `data:` line and of repeated `event:` lines, and
  strips a byte-order mark only at the start of the stream rather than from
  every line.
- **Breaking (library consumers):** `LlmUserMessage.content` and the `content`
  field of `ChatFn`'s message records are now `String?`. A null means a **user**
  message whose wire content was a parts list rather than text (AG-UI returns
  null for any such message, keeping the parts on
  `UserMessage.messageContent`), or — in `ChatFn`'s records only — an
  **assistant** turn carrying neither text nor tool calls. Neither coalesces to
  `''`, which is itself a sendable message that several chat APIs reject:
  callers substitute a placeholder or reject the turn. The app itself is
  unaffected — it neither implements `ChatFn` nor reads `LlmUserMessage`.
- An activity snapshot whose `content` is not a JSON object still surfaces as a
  dropped-event tile. 0.3.0 widened `ActivitySnapshotEvent.content` to `Object?`
  and dropped the decoder's Map validation, so a payload that 0.1.0 rejected at
  the wire boundary now decodes cleanly; Soliplex stores activity content as a
  JSON object, so it has nowhere to go. The guard moved to the application seam
  to keep the tile. Without it the row would strand — a dropped
  `skill_tool_result` leaves its `skill_tool_call` at in-progress with nothing on
  screen saying why.
- A `MESSAGES_SNAPSHOT` event is now logged on arrival. It carries AG-UI's
  authoritative message list, which this client does not reconcile against, so a
  server-side prune or rewrite of history would otherwise leave a divergent view
  with no trace.
- A response body that closes cleanly part-way through an SSE event no longer
  discards the partial payload: 0.3.0's parser flushes it at end-of-stream, so
  it surfaces as a dropped-event tile. If the cut lands mid-multi-byte
  character the stream errors instead, which resume recovers from when a
  `Last-Event-ID` cursor is available.
- AG-UI messages the in-process LLM providers do not project into their text
  transcript (`DeveloperMessage`, `ActivityMessage`, `ReasoningMessage`) are now
  logged when dropped, and the conversion switches enumerate every `Message`
  subtype so a type added upstream is a compile error rather than a silent
  omission. `ReasoningMessage` is new in 0.3.0; on 0.1.0 the role did not exist,
  so such a message failed to decode and became a drop tile.
- SSE parsing now goes through AG-UI's public `SseClient` rather than a deep
  import of its private `src/sse/sse_parser.dart`, so this package depends only
  on ag_ui's semver-covered surface. Both routes reach the same parser, so the
  swap changes nothing beyond the `data:` cap described below.
- A single SSE event's `data:` is now capped at roughly 8M UTF-16 code units
  (ag_ui's default; 0.1.0 had no cap). The cap bounds **inbound** events that
  carry conversation state — a `MESSAGES_SNAPSHOT` or `TOOL_CALL_RESULT`
  echoing image data — and leaves room for roughly 6 MB of binary after base64.
  Outbound attachments travel in the request body and are unaffected.
- A stream that fails at the same point on every resume attempt now ends after
  the retry budget instead of reconnecting forever. The budget resets only when
  an attempt advances the `Last-Event-ID` cursor, so a drop that follows fresh
  progress gets a full budget while a permanently rejected event — one over the
  new `data:` cap, which the server re-sends verbatim on each resume — is
  allowed to exhaust it and surface as a resume failure carrying the parser's
  message. The cursor is an imperfect proxy for progress: a server that emits
  `id:` sparsely charges real progress against the budget, as does a drop that
  lands before the first new id.
- **Breaking (library consumers), transitively:** `soliplex_client`'s barrel
  re-exports `package:ag_ui/ag_ui.dart` (less `CancelToken`), so every ag_ui
  0.3.0 breaking change reaches anything importing it — not just the two `String?`
  types above. Notably `RunStartedEvent` and `UserMessage`'s text constructor
  are no longer `const` (`UserMessage.fromContent` still is),
  `ActivitySnapshotEvent.content` widened to `Object?`, and
  `StateDeltaEvent.delta` / `ActivityDeltaEvent.patch` narrowed to
  `List<Map<String, dynamic>>`. Library code here needed no changes for the
  `const` break; forks should expect it to reach their tests and any
  `const`-constructed events.
- A message's sources now start expanded, so each cited source's filename and
  pages are readable without opening the "N sources" section first. The header
  still collapses the section, and an individual source's transcript still
  starts collapsed.
- A room's welcome screen no longer repeats the room name above its welcome
  message — the room header already carries the name directly above it. Its
  sections (welcome message, suggestions, quizzes) are now separated only from
  one another, so a room without a welcome message no longer opens with an
  extra gap above its first section.

### Fixed

- The chat screen no longer shows the room title twice at phone and narrow web
  widths. The app bar title was repeated by an in-page header directly beneath
  it; narrow layouts now drop that header and move its controls — the
  attached-files toggle and room info — up beside the app bar title. Wide
  layouts, which have no app bar, keep the in-page header as before.
- An expanded citation's transcript no longer traps thread scrolling. The
  transcript now renders as a short, non-scrolling preview with a bottom fade,
  and a "Show full transcript" toggle lifts it into a bounded, internally
  scrollable band, so the reader opts into the inner scroll for one passage
  rather than every expanded citation swallowing the thread's scroll. The
  toggle shows a pointer cursor, a tooltip, and a hover highlight.
- The lobby's "Filter rooms" row now keeps a gutter above the room list once
  the list is scrolled, so room titles and descriptions no longer butt flush
  against the filter row and read as clipped.
- Dialogs, the mobile drawer, and the room rail's avatars now take their corner
  radius from the brand shape instead of keeping Material's rounded defaults,
  so a square brand squares them. Rail avatars previously mixed a full circle
  when unselected with a squared selected one.

## [0.97.2+75] - 2026-07-28

### Fixed

- A reply now shows every source it cited. Previously a source cited again from
  an earlier turn could be dropped, and a reply whose agent searched several
  times kept only its last batch of sources; both now render in full, and a
  thread shows the same sources live and after a reload.
- A cited source's inline figures now render even when the reply's agent
  searched several times. Previously, when a later search reused the retrieval
  slot, figures for a source found by an earlier search of the same reply were
  dropped and it rendered text-only; those figures are now preserved, live and
  after a reload.

## [0.97.1+74] - 2026-07-24

### Fixed

- The file-attachment button no longer disappears on a freshly created thread.
  A new thread's attachment support cannot be read from its history until its
  first reply arrives, and that undetermined state was being treated as
  "unsupported"; the composer now keeps the room's attachment capability in
  that window instead of hiding the button.

## [0.97.0+73] - 2026-07-24

### Changed

- A document's source link is now derived from the document URI when the
  backend provides no `source_url`, with a deployment-injected resolver
  (`standard(documentBrowserUrl: ...)`) as the fallback. A document with
  neither shows its document URI as non-clickable text.
- File attachments now appear based on the `bubble-sandbox` skill — the room's
  configured skills for room-level (admin) uploads, and a thread's AG-UI state
  for thread-level uploads — instead of an `enable_attachments` room flag the
  backend no longer sends. Attachments were effectively unreachable while gated
  on that flag.
- The lobby sort options are shortened to "None", "Recent", and "Unread".

### Fixed

- Citations now appear for agents whose sources arrive under a non-`rag` state
  namespace (such as the analysis agent). Citation extraction reads every
  citation-bearing namespace in the agent state rather than only `rag`, so a
  reply that cites sources renders its citations regardless of which retrieval
  skill produced them.

## [0.96.0+72] - 2026-07-23

### Added

- Removing a server now asks for confirmation first — on both the home-screen
  server list and the lobby sidebar's server menu — so a server and its sign-in
  session can't be dropped by a stray tap. For a signed-in server the prompt
  notes that removing also signs you out.

### Changed

- A citation's source link now comes from the backend document's `source_url`
  metadata when the backend carries it, rather than only from the
  deployment-injected resolver.
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
- The insecure-connection warning ("This connection is not encrypted") makes
  Cancel the prominent (filled) action and "Connect anyway" a quieter
  danger-styled text button, so the safe choice carries the emphasis.
- In an expanded citation, the cited figures now appear above the source text
  rather than below it.

## [0.95.0+71] - 2026-07-21

### Added

- Document origin URLs (`source_url`) now render as clickable links across the
  room document listing, document filter, citations, and the
  chunk-visualization page, replacing the internal file path — which remains
  only in the document listing's metadata dialog. Where the backend does not
  yet carry `source_url` (citations, chunks), the link comes from a resolver a
  deployment injects via `standard(documentBrowserUrl: ...)`.

## [0.94.2+70] - 2026-07-21

### Added

- Room and lobby: the current server's name (or its address when unnamed) now
  shows alongside the room name in the room view header, and as a title band at
  the top of the lobby's room pane, so a user connected to several servers can
  tell which one they are viewing.
- Room info: a "View chunk" card lets you enter a chunk id and open its
  rendered page images, so a chunk can be viewed directly from an id (e.g. one
  taken from logs) rather than only by tapping a PDF citation. Expanded
  citations now also surface the chunk id and document provenance, each
  copyable.
- Tapping an inline image in chat or other markdown now opens a full-size
  pan/zoom/rotate view; SVG code blocks open the same view on tap.
- A citation's figures open in a pageable browser over all of that citation's
  figures, with previous/next chevrons, page dots, and left/right arrow-key
  navigation, instead of a single figure at a time.

### Changed

- The image and SVG preview surfaces — chunk visualization, workdir file
  preview, citation figures, and SVG previews — share a single
  pan/zoom/rotate/reset viewer, so those interactions behave consistently and
  zooming out returns to a centered fit.

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
