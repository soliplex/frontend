import 'dart:io';

import 'package:soliplex_logging/src/log_level.dart';
import 'package:soliplex_logging/src/log_record.dart';

/// ANSI color codes for terminal output.
const _kReset = '\x1B[0m';
const _kRed = '\x1B[31m';
const _kYellow = '\x1B[33m';
const _kCyan = '\x1B[36m';
const _kGray = '\x1B[90m';

/// Writes a log record to stdout via `dart:io`.
///
/// Called by `StdoutSink.write` via conditional import on native platforms
/// (iOS, macOS, Android, Windows, Linux).
///
/// When [useColors] is true, output includes colored level tags:
/// - trace/debug: gray
/// - info: cyan
/// - warning: yellow
/// - error/fatal: red
///
/// Uses a single `stdout.write` call to ensure atomic output (prevents
/// interleaving with other stdout writes).
///
/// Wrapped in try-catch to ensure logging never crashes the app (e.g.,
/// broken pipe when piped to another process).
void writeToStdout(LogRecord record, {required bool useColors}) {
  try {
    final buffer = StringBuffer();

    // Format the log line directly (not using formatLogMessage to avoid
    // parsing the string back for colorization).
    if (useColors) {
      final color = _colorForLevel(record.level);
      buffer.write('$color[${record.level.label}]$_kReset ');
    } else {
      buffer.write('[${record.level.label}] ');
    }

    buffer.write('${record.loggerName}: ${record.message}');

    // Add span context if present.
    if (record.spanId != null || record.traceId != null) {
      buffer.write(' (');
      if (record.traceId != null) buffer.write('trace=${record.traceId}');
      if (record.spanId != null && record.traceId != null) buffer.write(', ');
      if (record.spanId != null) buffer.write('span=${record.spanId}');
      buffer.write(')');
    }

    buffer.writeln();

    // Add error and stack trace on separate lines.
    final error = record.error;
    if (error != null) {
      if (useColors) {
        buffer.writeln('$_kRed  Error: $error$_kReset');
      } else {
        buffer.writeln('  Error: $error');
      }
    }
    // Only show stack trace if it's non-null and non-empty.
    final stackStr = record.stackTrace?.toString();
    if (stackStr != null && stackStr.isNotEmpty) {
      if (useColors) {
        buffer.writeln('$_kGray  Stack: $stackStr$_kReset');
      } else {
        buffer.writeln('  Stack: $stackStr');
      }
    }

    // Single atomic write to prevent interleaving.
    stdout.write(buffer.toString());
  } on Object {
    // Suppress all errors - logging must never crash the app.
    // Common failure: broken pipe when piped to another process.
  }
}

/// Returns the ANSI color code for a given log level.
String _colorForLevel(LogLevel level) {
  return switch (level) {
    .trace || .debug => _kGray,
    .info => _kCyan,
    .warning => _kYellow,
    .error || .fatal => _kRed,
  };
}
