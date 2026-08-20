import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:soliplex_logging/soliplex_logging.dart';

/// Registers the app's log sinks and sets the level floor.
///
/// Three sinks, each on its own transport:
///
/// - [ConsoleSink] goes through `dart:developer` to the VM-service logging
///   stream, so it reaches whatever client is attached — the DevTools
///   "Logging" view or an IDE debugger. On a native release build it is
///   effectively inert (AOT runs no VM service); on web it also writes the
///   browser console, which is present even in a release build.
/// - [StdoutSink] writes raw stdout via `dart:io`, which goes to whoever owns
///   the process: a terminal under `flutter run` or the launching tool under
///   `flutter run --machine`. A packaged GUI app has no attached terminal, so
///   its stdout is typically discarded (it is not Console.app / logcat — those
///   carry the `dart:developer`/OS-logging path, not raw process stdout), and
///   on web the sink is a no-op. For a view that doesn't depend on what's
///   attached, route to a file (a disk sink, or shell redirection of stdout).
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
/// stays quiet, while debug keeps [LogLevel.info]. Shipping logs *off* the
/// device (a backend sink) is a separate decision that needs redaction and
/// consent handling, since records can carry server URLs and error details.
/// Host apps that embed this package as a library configure their own sinks.
void installLogSinks(LogManager manager) {
  manager.minimumLevel = kReleaseMode ? LogLevel.warning : LogLevel.info;
  manager
    ..addSink(ConsoleSink())
    ..addSink(StdoutSink())
    ..addSink(MemorySink());
}
