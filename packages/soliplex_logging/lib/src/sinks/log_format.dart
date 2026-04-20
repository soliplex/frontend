import 'package:soliplex_logging/src/log_record.dart';

/// Formats the basic log message (level, logger, message, spans).
///
/// Error and stackTrace are handled separately by each platform implementation
/// since they have different capabilities:
/// - Native: `dart:developer` accepts them as separate parameters
/// - Web: Browser console can display them as expandable objects
String formatLogMessage(LogRecord record) {
  final buffer =
      StringBuffer()..write(
        '[${record.level.label}] ${record.loggerName}: ${record.message}',
      );

  if (record.spanId != null || record.traceId != null) {
    buffer.write(' (');
    if (record.traceId != null) buffer.write('trace=${record.traceId}');
    if (record.spanId != null && record.traceId != null) buffer.write(', ');
    if (record.spanId != null) buffer.write('span=${record.spanId}');
    buffer.write(')');
  }

  return buffer.toString();
}
