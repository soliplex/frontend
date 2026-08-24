import 'package:flutter/foundation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Records errors no `catch` in this app saw.
///
/// Two intakes, because Flutter splits them:
///
/// - [FlutterError.onError] takes what the framework catches on the app's
///   behalf — a throw out of `build`, a layout assertion, a gesture callback.
///   A throw out of `onPressed` is one of these: the framework prints it and
///   the app carries on, so without an intake here the press leaves no record.
/// - [PlatformDispatcher.onError] takes an unhandled error that reached the
///   root zone: a `Future` nobody awaited, an error delivered to a stream with
///   no `onError`. It sees the **root zone only**, which is the right intake
///   here because nothing in this app runs under `runZonedGuarded` — and it is
///   preferable to wrapping `runApp`, which would put the whole app in a child
///   zone for no other reason.
///
/// This is detection, not repair. Neither intake can unstick whatever the
/// error left half-done; what they buy is that a broken invariant leaves a
/// record on the diagnostics screen instead of a line on a console nobody is
/// attached to.
///
/// Both records go through `describeFailure` rather than `error:`. An uncaught
/// error is thrown over whatever the app happened to be holding — a
/// `FormatException` off a backend payload renders roughly 78 characters of it
/// — and these records land in the buffer the diagnostics screen displays and
/// can export.
///
/// Call this after [installLogSinks]; without a sink [LogManager] discards
/// every record. Calling it twice chains a second framework handler onto the
/// first and logs each framework error twice.
void installUncaughtErrorLogging() {
  final logger = LogManager.instance.getLogger('uncaught');

  // Whatever the app is already running under — `FlutterError.presentError` in
  // a normal launch, the test binding's collector under `flutter test`.
  // Logging is a second copy, not a replacement: dropping this delegation
  // silences the console dump app-wide and still compiles.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    logger.error(
      'Uncaught framework error',
      attributes: {'failure': describeFailure(details.exception)},
      stackTrace: details.stack,
    );
    priorOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    logger.error(
      'Uncaught asynchronous error',
      attributes: {'failure': describeFailure(error)},
      stackTrace: stackTrace,
    );
    // False: the record is a second copy, and returning true would tell the
    // engine the error is handled and suppress its own report. On a target
    // where no installed sink has a transport — a packaged release build, or
    // Android, where stdout reaches nobody — that report is the only place the
    // error still appears outside the app.
    return false;
  };
}
