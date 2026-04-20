import 'package:meta/meta.dart';
import 'package:soliplex_logging/src/log_level.dart';

/// Sentinel value to distinguish "not provided" from explicit `null` in
/// [LogRecord.copyWith].
const Object _sentinel = Object();

/// Immutable log record containing all information about a log event.
@immutable
class LogRecord {
  /// Creates a new log record.
  LogRecord({
    required this.level,
    required this.message,
    required this.timestamp,
    required this.loggerName,
    this.error,
    this.stackTrace,
    this.spanId,
    this.traceId,
    Map<String, Object?> attributes = const {},
  }) : attributes = Map.unmodifiable(attributes);

  /// Severity level of this log.
  final LogLevel level;

  /// Log message.
  final String message;

  /// When this log was created.
  final DateTime timestamp;

  /// Name of the logger that created this record.
  final String loggerName;

  /// Associated error object, if any.
  final Object? error;

  /// Stack trace for error logs.
  final StackTrace? stackTrace;

  /// Span ID for telemetry correlation.
  final String? spanId;

  /// Trace ID for telemetry correlation.
  final String? traceId;

  /// Structured key-value attributes for contextual metadata.
  final Map<String, Object?> attributes;

  /// Returns a copy of this record with the given fields replaced.
  ///
  /// Nullable fields ([error], [stackTrace], [spanId], [traceId]) can be
  /// explicitly cleared by passing `null`.
  LogRecord copyWith({
    LogLevel? level,
    String? message,
    DateTime? timestamp,
    String? loggerName,
    Object? error = _sentinel,
    Object? stackTrace = _sentinel,
    Object? spanId = _sentinel,
    Object? traceId = _sentinel,
    Map<String, Object?>? attributes,
  }) {
    return LogRecord(
      level: level ?? this.level,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      loggerName: loggerName ?? this.loggerName,
      error: error == _sentinel ? this.error : error,
      stackTrace:
          stackTrace == _sentinel ? this.stackTrace : stackTrace as StackTrace?,
      spanId: spanId == _sentinel ? this.spanId : spanId as String?,
      traceId: traceId == _sentinel ? this.traceId : traceId as String?,
      attributes: attributes ?? this.attributes,
    );
  }

  /// Whether this record has error or stack trace details.
  bool get hasDetails => error != null || stackTrace != null;

  /// Formats the timestamp as `HH:mm:ss.mmm`.
  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final buffer =
        StringBuffer()
          ..write('$formattedTimestamp [${level.label}] $loggerName: $message');

    if (spanId != null || traceId != null) {
      buffer.write(' (');
      if (traceId != null) buffer.write('trace=$traceId');
      if (spanId != null && traceId != null) buffer.write(', ');
      if (spanId != null) buffer.write('span=$spanId');
      buffer.write(')');
    }

    if (attributes.isNotEmpty) {
      buffer.write(' $attributes');
    }

    if (error != null) {
      buffer
        ..writeln()
        ..write('Error: $error');
    }

    if (stackTrace != null) {
      buffer
        ..writeln()
        ..write(stackTrace);
    }

    return buffer.toString();
  }
}
