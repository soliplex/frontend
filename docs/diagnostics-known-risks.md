# Diagnostics screen: known risks

What the in-app Diagnostics screen and its saved report do *not* guarantee, and
what has never been executed. Written when the Logs pane and the report landed,
so the open questions are recorded rather than rediscovered.

## Log records are not redacted

HTTP capture is redacted before any observer sees it: `HttpRedactor` replaces
the values of `Authorization`, cookies and token-bearing query parameters, and
also redacts request bodies, SSE content and error strings
(`ObservableHttpClient`). The names remain, the values it recognises do not —
recognition is the limit. `HttpRedactor` matches fixed header and parameter
names plus a short substring list, so bearer material under a name it does not
know (`X-Amz-Signature`, `client_assertion`) passes through.

**Nothing redacts log records.** `installLogSinks` adds a bare `MemorySink`,
and `formatLogRecord` applies no redaction. Two consequences:

- Every `attributes:` site in the app today carries deployment detail —
  `discoveryUrl`, `serverUrl`, `hosts`, `alias`, `expiresAt`, `session`,
  `platformError`, `elapsedMs`, `returnTo`. None carries a credential.
  (`accessToken` / `refreshToken` / `idToken` appear in the codebase only as
  token-storage JSON keys, never as log attributes.)
- `error:` takes an arbitrary object. An IdP or plugin exception whose
  `toString()` embeds a raw token response would reach the buffer, the Logs
  pane, and the saved file.

The screen is in `_publicPaths`, so this is readable and savable without a
session — deliberately, since a user who cannot sign in is who it is for.

The standard is therefore author discipline plus a comment at the route.
Nothing fails CI when someone logs a secret. **Open question: whether
`LogRecord` should get a redaction pass before this is on many devices.**

## The report is built synchronously on the UI thread

`buildDiagnosticsReport` walks up to 1000 grouped exchanges and 2000 log
records — with stack traces — into one string, then `utf8.encode` doubles it in
memory, all in one frame. The busiest sessions are exactly the ones worth
reporting.

The action disables itself while running, so it cannot double-fire, but there
is no progress affordance and no isolate. **This has never been measured.**

## The save timeout can be wrong about a slow save

`FilePicker.saveFile` is bounded at five minutes, because a platform future
that never completes would leave the in-flight guard set and the action dead
with nothing logged (Android's picker has result codes it never resolves).

`Future.timeout` does not cancel the underlying call. A user browsing to a
network share, or using Android SAF over a cloud provider, can exceed the bound
with the dialog still open: the screen then says the dialog did not answer, and
if they finish it the file writes correctly while a stamped notice says
otherwise. Late completions are logged, so the record is recoverable.

Five minutes is a chosen number, not a measured one.

## Web export has never been executed

`kIsWeb` is a compile-time constant, so no VM test reaches the web branches.
The behaviour is reasoned from `file_picker`'s web implementation: it dispatches
an anchor click and returns null unconditionally, with no cancellation concept
and no way to observe whether the browser delivered the download. The screen
therefore claims only that a download started.

## iOS may retain a copy of every cancelled save

`file_picker`'s iOS plugin appears to write the bytes into app storage *before*
presenting the export picker, and returns nil on cancel. If so, each cancelled
save leaves a complete report — hostnames, discovery URLs, log records — on
disk under a timestamped name that nothing deletes, outside the reasoning at
`_publicPaths`.

Unverified: this was read from the plugin's Objective-C, not exercised.
**Open question: confirm, and clean up on the cancel path if it holds.**

## Smaller, recorded rather than fixed

- The report's `Requests captured: N` counts the groups it renders.
  `groupHttpEvents` drops orphans — exchanges whose start event the bounded
  buffer evicted — so a busy streaming session can omit exchanges without
  saying so.
- `HttpResponseEvent.reasonPhrase` is captured and never printed, so a server's
  own status text does not reach the report. `bodySize` is printed.
- `formatLogRecord` collapses line breaks in the message, attributes and error,
  but stack-trace frames are split on `\n` only and not sanitised. Every trace
  today is VM-generated, so no frame contains a stray `\r`.
- `capturedLogSink` returns the first `MemorySink` when several are installed.
  This app installs one; a host app that installs two gets the
  earlier-registered one and no warning.
