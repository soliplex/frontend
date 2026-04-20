import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

void main() {
  group('ConsoleSink', () {
    test('can be created with default enabled state', () {
      final sink = ConsoleSink();
      expect(sink.enabled, isTrue);
    });

    test('can be created disabled', () {
      final sink = ConsoleSink(enabled: false);
      expect(sink.enabled, isFalse);
    });

    test('write does nothing when disabled', () {
      final captured = <LogRecord>[];
      final sink = ConsoleSink(enabled: false, testWriter: captured.add);
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
      final sink = ConsoleSink();
      await expectLater(sink.flush(), completes);
    });

    test('close disables the sink', () async {
      final sink = ConsoleSink();
      expect(sink.enabled, isTrue);

      await sink.close();
      expect(sink.enabled, isFalse);
    });

    group('testWriter', () {
      test('captures records when provided', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);

        final record = LogRecord(
          level: LogLevel.debug,
          message: 'test message',
          timestamp: DateTime.now(),
          loggerName: 'TestLogger',
        );

        sink.write(record);

        expect(captured, hasLength(1));
        expect(captured.first.level, LogLevel.debug);
        expect(captured.first.message, 'test message');
        expect(captured.first.loggerName, 'TestLogger');
      });

      test('captures multiple records', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
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
        expect(captured[0].level, LogLevel.info);
        expect(captured[1].level, LogLevel.warning);
        expect(captured[2].level, LogLevel.error);
      });

      test('captures records with span context', () {
        final captured = <LogRecord>[];
        ConsoleSink(testWriter: captured.add).write(
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
        expect(captured.first.spanId, 'span-123');
        expect(captured.first.traceId, 'trace-456');
      });

      test('respects enabled flag', () {
        final captured = <LogRecord>[];
        ConsoleSink(enabled: false, testWriter: captured.add).write(
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
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add)..write(
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
        expect(captured.first.message, 'before close');
      });
    });

    group('exception logging', () {
      test('captures Exception with message', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
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
        expect(captured.first.error, exception);
        expect(
          captured.first.error.toString(),
          contains('Something went wrong'),
        );
      });

      test('captures Error with stackTrace', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
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
        expect(captured.first.error, error);
        expect(captured.first.stackTrace, stackTrace);
        expect(captured.first.error.toString(), contains('Invalid state'));
      });

      test('captures FormatException with details', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
        const exception = FormatException('Invalid JSON', '{"broken', 5);

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Parse failed',
            timestamp: DateTime.now(),
            loggerName: 'JsonParser',
            error: exception,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.error, isA<FormatException>());
        final capturedError = captured.first.error! as FormatException;
        expect(capturedError.message, 'Invalid JSON');
        expect(capturedError.source, '{"broken');
        expect(capturedError.offset, 5);
      });

      test('captures ArgumentError', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
        final error = ArgumentError.value(-1, 'count', 'must be non-negative');

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Invalid argument',
            timestamp: DateTime.now(),
            loggerName: 'Validator',
            error: error,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.error, isA<ArgumentError>());
        expect(
          captured.first.error.toString(),
          contains('must be non-negative'),
        );
      });

      test('captures RangeError', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
        final error = RangeError.range(10, 0, 5, 'index');

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Index out of range',
            timestamp: DateTime.now(),
            loggerName: 'List',
            error: error,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.error, isA<RangeError>());
      });

      test('captures custom exception class', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
        final exception = _CustomException('Custom error', 42);

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Custom exception',
            timestamp: DateTime.now(),
            loggerName: 'Custom',
            error: exception,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.error, isA<_CustomException>());
        final capturedError = captured.first.error! as _CustomException;
        expect(capturedError.message, 'Custom error');
        expect(capturedError.code, 42);
      });

      test('captures error with null stackTrace', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
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
        expect(captured.first.error, error);
        expect(captured.first.stackTrace, isNull);
      });

      test('captures stackTrace without error', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
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
        expect(captured.first.error, isNull);
        expect(captured.first.stackTrace, stackTrace);
      });

      test('captures nested exception', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
        final innerException = Exception('Inner error');
        final outerException = _WrappedException('Outer error', innerException);

        sink.write(
          LogRecord(
            level: LogLevel.error,
            message: 'Nested exception',
            timestamp: DateTime.now(),
            loggerName: 'Test',
            error: outerException,
          ),
        );

        expect(captured, hasLength(1));
        expect(captured.first.error, isA<_WrappedException>());
        final capturedError = captured.first.error! as _WrappedException;
        expect(capturedError.innerException, innerException);
      });

      test('captures multiple errors in sequence', () {
        final captured = <LogRecord>[];
        final sink = ConsoleSink(testWriter: captured.add);
        final now = DateTime.now();

        sink
          ..write(
            LogRecord(
              level: LogLevel.error,
              message: 'First error',
              timestamp: now,
              loggerName: 'Test',
              error: Exception('First'),
            ),
          )
          ..write(
            LogRecord(
              level: LogLevel.error,
              message: 'Second error',
              timestamp: now,
              loggerName: 'Test',
              error: StateError('Second'),
            ),
          )
          ..write(
            LogRecord(
              level: LogLevel.fatal,
              message: 'Third error',
              timestamp: now,
              loggerName: 'Test',
              error: ArgumentError('Third'),
            ),
          );

        expect(captured, hasLength(3));
        expect(captured[0].error, isA<Exception>());
        expect(captured[1].error, isA<StateError>());
        expect(captured[2].error, isA<ArgumentError>());
      });
    });
  });
}

/// Custom exception for testing.
class _CustomException implements Exception {
  _CustomException(this.message, this.code);
  final String message;
  final int code;

  @override
  String toString() => 'CustomException: $message (code: $code)';
}

/// Wrapped exception for testing nested exceptions.
class _WrappedException implements Exception {
  _WrappedException(this.message, this.innerException);
  final String message;
  final Exception innerException;

  @override
  String toString() => 'WrappedException: $message\nCaused by: $innerException';
}
