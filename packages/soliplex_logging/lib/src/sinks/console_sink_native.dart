import 'dart:developer' as developer;

import 'package:soliplex_logging/src/log_level.dart';
import 'package:soliplex_logging/src/log_record.dart';
import 'package:soliplex_logging/src/sinks/log_format.dart';

/// Writes a log record to the native console via dart:developer.
///
/// Called by `ConsoleSink.write` via conditional import on native platforms
/// (iOS, macOS, Android, Windows, Linux).
void writeToConsole(LogRecord record) {
  // Only pass stackTrace if non-empty to avoid "Stack:" with no content.
  final stackStr = record.stackTrace?.toString();
  final stackTrace = (stackStr != null && stackStr.isNotEmpty)
      ? record.stackTrace
      : null;

  developer.log(
    formatLogMessage(record),
    name: record.loggerName,
    level: _mapLevel(record.level),
    time: record.timestamp,
    error: record.error,
    stackTrace: stackTrace,
  );
}

/// Maps LogLevel to dart:developer log levels.
///
/// dart:developer uses numeric levels where higher values indicate
/// more severe log messages (0-2000 range).
int _mapLevel(LogLevel level) {
  return switch (level) {
    .trace => 300,
    .debug => 500,
    .info => 800,
    .warning => 900,
    .error => 1000,
    .fatal => 1200,
  };
}
