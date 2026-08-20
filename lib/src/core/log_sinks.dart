import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:soliplex_logging/soliplex_logging.dart';

/// Registers the app's log sinks and sets the level floor.
///
/// Three sinks, each on its own transport:
///
/// - [ConsoleSink] goes through `dart:developer` to the VM-service logging
///   stream, so it reaches whatever client is attached — the DevTools
///   "Logging" view or an IDE debugger, and *not* logcat or the `flutter run`
///   console. On a native release build it is effectively inert (AOT runs no
///   VM service); on web it also writes the browser console, which is present
///   even in a release build.
/// - [StdoutSink] writes raw stdout via `dart:io`, which goes to whoever owns
///   the process. On a desktop target that is the terminal running the app, or
///   the launching tool under `flutter run --machine`. On Android it is nobody:
///   a record emitted through this sink reaches neither the `flutter run`
///   console nor logcat — measured on a device, since the process's stdout
///   belongs to the device rather than the host. A packaged GUI app likewise
///   has no attached terminal, and on web the sink is a no-op. For a view that
///   doesn't depend on what's attached, route to a file (a disk sink, or shell
///   redirection of stdout).
/// - [MemorySink] retains recent records in a ring buffer, readable in-process
///   via `LogManager.sinks`. On a *packaged* native release build it is the
///   only one whose output can be read back at all — the console sink's
///   `dart:developer` stream has no VM service to reach, and a GUI launch
///   discards stdout — which is why the in-app diagnostics screen reads it.
///   Both qualifiers matter: a release binary started from a terminal still
///   shows the stdout sink, and on web the console sink reaches the browser
///   console in release too.
///
/// All three register in every build mode; without a sink [LogManager] discards
/// every record. Release is held to [LogLevel.warning] so the on-device stream
/// stays quiet, while every other mode — debug and profile — keeps
/// [LogLevel.info]. Shipping logs *off* the device (a backend sink) is a
/// separate decision that needs redaction and consent handling, since records
/// can carry server URLs and error details.
///
/// Host apps that embed this package as a library configure their own sinks,
/// and nothing installs any on their behalf: a host that calls neither this nor
/// [LogManager.addSink] gets no logging, which is the default this package
/// leaves alone. Call this once, before building your flavor — it sets the
/// level floor unconditionally, and calling it twice registers a second set.
///
/// [LogManager.reset] is a test hook and [LogManager.close] is a shutdown
/// path. Nothing re-installs sinks after either, so a host that calls one at
/// runtime is back to discarding every record.
void installLogSinks() {
  LogManager.instance
    ..minimumLevel = kReleaseMode ? LogLevel.warning : LogLevel.info
    ..addSink(ConsoleSink())
    ..addSink(StdoutSink())
    ..addSink(MemorySink());
}
