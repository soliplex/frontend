import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// The barrel, not `src/`: it is the only supported path for a host app, so
// importing `src/` here would let the export be dropped without a test
// failing.
import 'package:soliplex_frontend/soliplex_frontend.dart';

/// A `FormatException` carrying the input it failed on, which is the shape
/// the rule against `error:` exists for: `toString()` renders roughly 78
/// characters of that input, and an uncaught error can be thrown over
/// anything the backend or the user supplied.
Object _failureCarryingItsInput() {
  try {
    jsonDecode('{"token":"SECRET_PROJECT_VALUE","x":}');
    fail('expected a FormatException');
  } on FormatException catch (e) {
    return e;
  }
}

void main() {
  late MemorySink sink;

  setUp(() {
    sink = MemorySink();
    LogManager.instance.addSink(sink);
  });

  tearDown(LogManager.instance.reset);

  group('installUncaughtErrorLogging', () {
    // Both are process-global and the test binding owns them: restore through
    // `addTearDown` so a failing expectation cannot skip it.
    void installOverRestorableGlobals() {
      final priorFlutterOnError = FlutterError.onError;
      final priorPlatformOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = priorFlutterOnError;
        PlatformDispatcher.instance.onError = priorPlatformOnError;
      });
      installUncaughtErrorLogging();
    }

    test('a framework error is recorded without the data it carries', () {
      final delegatedTo = <FlutterErrorDetails>[];
      // Stand in for `FlutterError.presentError`, which the app is running
      // under at install time — and keep the dump out of the test output.
      FlutterError.onError = delegatedTo.add;
      installOverRestorableGlobals();

      final details = FlutterErrorDetails(
        exception: _failureCarryingItsInput(),
        stack: StackTrace.current,
        library: 'widgets library',
      );
      FlutterError.reportError(details);

      final record = sink.records.single;
      expect(record.level, LogLevel.error);
      // The offset survives; the ~78-character window of the decoded input
      // that `FormatException.toString()` would print does not.
      expect(
        record.attributes['failure'],
        'FormatException: Unexpected character (offset 36)',
      );
      // The whole record is what the diagnostics screen renders and exports.
      expect(record.toString(), isNot(contains('SECRET_PROJECT_VALUE')));
      expect(record.error, isNull);
      expect(record.stackTrace, isNotNull);
      // Logging is additive. Taking over `FlutterError.onError` without
      // passing the details on would silence the console dump app-wide, and
      // nothing about dropping the delegation fails to compile.
      expect(delegatedTo, [details]);
    });

    test('an uncaught async error is recorded without the data it carries', () {
      installOverRestorableGlobals();

      final handled = PlatformDispatcher.instance.onError!(
        _failureCarryingItsInput(),
        StackTrace.current,
      );

      // False, not true: the record is a second copy, so the platform's own
      // report of an unhandled error has to stay. On a target where no sink
      // has a transport — a packaged app, or Android, where stdout reaches
      // nobody — claiming the error was handled is what makes it disappear.
      expect(handled, isFalse);
      final record = sink.records.single;
      expect(record.level, LogLevel.error);
      expect(
        record.attributes['failure'],
        'FormatException: Unexpected character (offset 36)',
      );
      expect(record.toString(), isNot(contains('SECRET_PROJECT_VALUE')));
      expect(record.error, isNull);
      expect(record.stackTrace, isNotNull);
    });
  });
}
