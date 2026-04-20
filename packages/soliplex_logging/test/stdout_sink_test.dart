import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

void main() {
  group('StdoutSink', () {
    test('can be created with default enabled state', () {
      final sink = StdoutSink();
      expect(sink.enabled, isTrue);
    });

    test('can be created disabled', () {
      final sink = StdoutSink(enabled: false);
      expect(sink.enabled, isFalse);
    });

    test('useColors defaults to false', () {
      final sink = StdoutSink();
      expect(sink.useColors, isFalse);
    });

    test('can be created with useColors enabled', () {
      final sink = StdoutSink(useColors: true);
      expect(sink.useColors, isTrue);
    });

    test('write does nothing when disabled', () {
      final captured = <(LogRecord, bool)>[];
      final sink = StdoutSink(
        enabled: false,
        testWriter:
            (record, {required useColors}) => captured.add((record, useColors)),
      );
      final record = LogRecord(
        level: LogLevel.info,
        message: 'Test',
        timestamp: DateTime.now(),
        loggerName: 'Test',
      );

      sink.write(record);

      expect(captured, isEmpty);
    });

    test('flush completes immediately', () async {
      final sink = StdoutSink();
      await expectLater(sink.flush(), completes);
    });

    test('close disables the sink', () async {
      final sink = StdoutSink();
      expect(sink.enabled, isTrue);

      await sink.close();
      expect(sink.enabled, isFalse);
    });

    group('testWriter', () {
      test('captures records when provided', () {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        );

        final record = LogRecord(
          level: LogLevel.debug,
          message: 'test message',
          timestamp: DateTime.now(),
          loggerName: 'TestLogger',
        );

        sink.write(record);

        expect(captured, hasLength(1));
        expect(captured.first.$1.level, LogLevel.debug);
        expect(captured.first.$1.message, 'test message');
        expect(captured.first.$1.loggerName, 'TestLogger');
        expect(captured.first.$2, isFalse); // useColors default
      });

      test('passes useColors flag to testWriter', () {
        final captured = <(LogRecord, bool)>[];
        StdoutSink(
          useColors: true,
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        ).write(
          LogRecord(
            level: LogLevel.info,
            message: 'colored message',
            timestamp: DateTime.now(),
            loggerName: 'Test',
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$2, isTrue); // useColors enabled
      });

      test('captures multiple records', () {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        );
        final now = DateTime.now();

        sink
          ..write(
            LogRecord(
              level: LogLevel.info,
              message: 'first',
              timestamp: now,
              loggerName: 'Test',
            ),
          )
          ..write(
            LogRecord(
              level: LogLevel.warning,
              message: 'second',
              timestamp: now,
              loggerName: 'Test',
            ),
          )
          ..write(
            LogRecord(
              level: LogLevel.error,
              message: 'third',
              timestamp: now,
              loggerName: 'Test',
            ),
          );

        expect(captured, hasLength(3));
        expect(captured[0].$1.level, LogLevel.info);
        expect(captured[1].$1.level, LogLevel.warning);
        expect(captured[2].$1.level, LogLevel.error);
      });

      test('captures records with span context', () {
        final captured = <(LogRecord, bool)>[];
        StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        ).write(
          LogRecord(
            level: LogLevel.info,
            message: 'traced message',
            timestamp: DateTime.now(),
            loggerName: 'Test',
            spanId: 'span-123',
            traceId: 'trace-456',
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$1.spanId, 'span-123');
        expect(captured.first.$1.traceId, 'trace-456');
      });

      test('respects enabled flag', () {
        final captured = <(LogRecord, bool)>[];
        StdoutSink(
          enabled: false,
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        ).write(
          LogRecord(
            level: LogLevel.info,
            message: 'should not appear',
            timestamp: DateTime.now(),
            loggerName: 'Test',
          ),
        );

        expect(captured, isEmpty);
      });

      test('stops capturing after close', () async {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        )..write(
          LogRecord(
            level: LogLevel.info,
            message: 'before close',
            timestamp: DateTime.now(),
            loggerName: 'Test',
          ),
        );

        await sink.close();

        sink.write(
          LogRecord(
            level: LogLevel.info,
            message: 'after close',
            timestamp: DateTime.now(),
            loggerName: 'Test',
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$1.message, 'before close');
      });
    });

    group('exception logging', () {
      test('captures Exception with message', () {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        );
        final exception = Exception('Something went wrong');

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Operation failed',
            timestamp: DateTime.now(),
            loggerName: 'Test',
            error: exception,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$1.error, exception);
        expect(
          captured.first.$1.error.toString(),
          contains('Something went wrong'),
        );
      });

      test('captures Error with stackTrace', () {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        );
        final error = StateError('Invalid state');
        final stackTrace = StackTrace.current;

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'State error occurred',
            timestamp: DateTime.now(),
            loggerName: 'Test',
            error: error,
            stackTrace: stackTrace,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$1.error, error);
        expect(captured.first.$1.stackTrace, stackTrace);
        expect(captured.first.$1.error.toString(), contains('Invalid state'));
      });

      test('captures error with null stackTrace', () {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        );
        final error = Exception('No stack trace');

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Error without stack',
            timestamp: DateTime.now(),
            loggerName: 'Test',
            error: error,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$1.error, error);
        expect(captured.first.$1.stackTrace, isNull);
      });

      test('captures stackTrace without error', () {
        final captured = <(LogRecord, bool)>[];
        final sink = StdoutSink(
          testWriter:
              (record, {required useColors}) =>
                  captured.add((record, useColors)),
        );
        final stackTrace = StackTrace.current;

        sink.write(
          LogRecord(
            level: LogLevel.warning,
            message: 'Warning with stack',
            timestamp: DateTime.now(),
            loggerName: 'Test',
            stackTrace: stackTrace,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.$1.error, isNull);
        expect(captured.first.$1.stackTrace, stackTrace);
      });
    });
  });
}
