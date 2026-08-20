import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/log_record_format.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

void main() {
  test('a record renders its attributes and error, not just the message', () {
    // Attributes are where the diagnostic detail lives: the resolved host, the
    // platform error code, the elapsed time.
    final record = LogRecord(
      level: LogLevel.warning,
      message: 'Probe exhausted every candidate address',
      timestamp: DateTime.utc(2026, 8, 18, 7, 51),
      loggerName: 'soliplex.connection_probe',
      error: 'NetworkException: Client error',
      attributes: {
        'hosts': ['"ai.example.mil"'],
        'platformError': '[domain=NSURLErrorDomain, code=-1003]',
        'elapsedMs': 32,
      },
    );

    final line = formatLogRecord(record);

    expect(line, contains('soliplex.connection_probe'));
    expect(line, contains('"ai.example.mil"'));
    expect(line, contains('code=-1003'));
    expect(line, contains('elapsedMs=32'));
    expect(line, contains('error: NetworkException: Client error'));
  });

  test('a line break inside a record cannot forge a new record', () {
    // Records are told apart by starting at column 0, in the list and in the
    // exported report. A bare \r is the worst case: it leaves the text intact
    // for grep while painting the record's tail over its own timestamp.
    final record = LogRecord(
      level: LogLevel.warning,
      message: 'upstream said:\r\nHTTP/1.1 500',
      timestamp: DateTime.utc(2026, 8, 18, 7, 51),
      loggerName: 'soliplex.probe',
      attributes: const {'body': 'line one\nline two'},
    );

    final line = formatLogRecord(record);

    expect(line.contains('\n'), isFalse);
    expect(line.contains('\r'), isFalse);
    expect(line, contains('HTTP/1.1 500'));
    expect(line, contains('line two'));
  });

  test('the report mode keeps the stack trace, the list mode does not', () {
    // The frames name where an unexpected error came from, which is the whole
    // reason the exported report carries them; the on-screen list keeps one
    // row per record instead.
    final record = LogRecord(
      level: LogLevel.error,
      message: 'Authentication failed',
      timestamp: DateTime.utc(2026, 8, 18, 7, 51),
      loggerName: 'soliplex.connect_flow',
      error: 'Bad state',
      stackTrace: StackTrace.fromString('#0 frameOne\n#1 frameTwo'),
    );

    expect(formatLogRecord(record).contains('frameOne'), isFalse);

    final withTrace = formatLogRecord(record, includeStackTrace: true);
    expect(withTrace, contains('frameOne'));
    expect(withTrace, contains('frameTwo'));
    // Continuation lines are indented so they cannot be read as new records.
    expect(withTrace, contains('\n    #0 frameOne'));
  });

  test('the timestamp is UTC, so a record lines up against server logs', () {
    // Fed a LOCAL DateTime on purpose, which is what the logging package
    // produces: `Logger` stamps every record with `DateTime.now()`. Asserting
    // the trailing Z is what fails if the conversion is dropped — an already
    // UTC input could not detect that, and CI runs in UTC.
    final record = LogRecord(
      level: LogLevel.warning,
      message: 'probe failed',
      timestamp: DateTime(2026, 8, 18, 7, 51),
      loggerName: 'soliplex.probe',
    );

    final line = formatLogRecord(record);

    expect(RegExp(r'^\S+Z ').hasMatch(line), isTrue,
        reason: 'the record must open with a UTC timestamp');
  });
}
