import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_logging/src/sinks/stdout_sink_io.dart';
import 'package:test/test.dart';

LogRecord _record({
  Map<String, Object> attributes = const {},
  String? spanId,
  String? traceId,
  Object? error,
}) =>
    LogRecord(
      level: LogLevel.info,
      message: 'hello',
      timestamp: DateTime.utc(2026),
      loggerName: 'Test',
      attributes: attributes,
      spanId: spanId,
      traceId: traceId,
      error: error,
    );

void main() {
  group('formatStdoutRecord', () {
    test('appends attributes after the message', () {
      final line = formatStdoutRecord(
        _record(attributes: {'threadId': 't-1', 'tokens': 1800}),
        useColors: false,
      );

      expect(line, '[INFO] Test: hello {threadId=t-1, tokens=1800}\n');
    });

    test('omits the braces when there are no attributes', () {
      expect(
        formatStdoutRecord(_record(), useColors: false),
        '[INFO] Test: hello\n',
      );
    });

    test('keeps a value with line breaks on one line', () {
      final line = formatStdoutRecord(
        _record(attributes: {'k\nx': 'a\nb\rc'}),
        useColors: false,
      );

      expect(line, '[INFO] Test: hello {k x=a b c}\n');
    });

    test('writes the span suffix before the attributes', () {
      final line = formatStdoutRecord(
        _record(
          spanId: 's-1',
          traceId: 'tr-1',
          attributes: {'n': 1},
        ),
        useColors: false,
      );

      expect(line, '[INFO] Test: hello (trace=tr-1, span=s-1) {n=1}\n');
    });

    test('keeps the error on its own line after the attributes', () {
      final line = formatStdoutRecord(
        _record(attributes: {'n': 1}, error: 'boom'),
        useColors: false,
      );

      expect(line, '[INFO] Test: hello {n=1}\n  Error: boom\n');
    });

    test('colors the level tag, error and stack lines', () {
      final line = formatStdoutRecord(
        LogRecord(
          level: LogLevel.error,
          message: 'hello',
          timestamp: DateTime.utc(2026),
          loggerName: 'Test',
          error: 'boom',
          stackTrace: StackTrace.fromString('frame-1'),
        ),
        useColors: true,
      );

      expect(
        line,
        '\x1B[31m[ERROR]\x1B[0m Test: hello\n'
        '\x1B[31m  Error: boom\x1B[0m\n'
        '\x1B[90m  Stack: frame-1\x1B[0m\n',
      );
    });
  });
}
