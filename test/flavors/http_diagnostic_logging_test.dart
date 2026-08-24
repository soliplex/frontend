import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/flavors/standard_kit.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

void main() {
  group('logHttpDiagnostic', () {
    late MemorySink sink;

    setUp(() {
      sink = MemorySink();
      LogManager.instance.addSink(sink);
    });

    tearDown(LogManager.instance.reset);

    test('records a description, never the data the failure carries', () {
      // The shape the request-body pipes and the observer guards forward:
      // an exception this package did not construct, carrying data it was
      // thrown over.
      final Object failure;
      try {
        jsonDecode('{"token":"SECRET_PROJECT_VALUE","x":}');
        fail('expected a FormatException');
      } on FormatException catch (e) {
        failure = e;
      }

      logHttpDiagnostic(
        LogManager.instance.getLogger('http_stack'),
        failure,
        StackTrace.current,
        message: 'Response body redaction failed unexpectedly',
      );

      final record = sink.records.single;
      expect(record.message, 'Response body redaction failed unexpectedly');
      // The offset survives; the ~78-character window of the body that
      // `FormatException.toString()` would print does not.
      expect(
        record.attributes['failure'],
        'FormatException: Unexpected character (offset 36)',
      );
      // The whole record is what the diagnostics screen renders and exports.
      expect(record.toString(), isNot(contains('SECRET_PROJECT_VALUE')));
      expect(record.error, isNull);
      expect(record.stackTrace, isNotNull);
    });
  });
}
