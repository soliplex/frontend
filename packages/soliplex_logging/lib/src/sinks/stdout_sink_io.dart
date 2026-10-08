import 'dart:io';

import 'package:soliplex_logging/src/log_level.dart';
import 'package:soliplex_logging/src/log_record.dart';

/// ANSI color codes for terminal output.
const _reset = '\x1B[0m';
const _red = '\x1B[31m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _gray = '\x1B[90m';

/// Writes a log record to stdout via `dart:io`.
///
/// Called by `StdoutSink.write` via conditional import on native platforms
/// (iOS, macOS, Android, Windows, Linux).
///
/// The line is the record's message, span context and attributes, followed by
/// its error and stack trace on separate lines (see [formatStdoutRecord]).
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
    // Single atomic write to prevent interleaving.
    stdout.write(formatStdoutRecord(record, useColors: useColors));
  } on Object {
    // Suppress all errors - logging must never crash the app.
    // Common failure: broken pipe when piped to another process.
  }
}

/// Builds the text [writeToStdout] writes for [record].
///
/// The record's own line ends with its attributes as `{key=value, ...}` when
/// it has any. Line breaks inside an attribute are collapsed so attributes
/// never split the line.
String formatStdoutRecord(LogRecord record, {required bool useColors}) {
  final buffer = StringBuffer();

  // Format the log line directly (not using formatLogMessage to avoid
  // parsing the string back for colorization).
  if (useColors) {
    final color = _colorForLevel(record.level);
    buffer.write('$color[${record.level.label}]$_reset ');
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

  if (record.attributes.isNotEmpty) {
    final pairs = record.attributes.entries
        .map((e) => '${_singleLine(e.key)}=${_singleLine('${e.value}')}')
        .join(', ');
    buffer.write(' {$pairs}');
  }

  buffer.writeln();

  // Add error and stack trace on separate lines.
  if (record.error != null) {
    if (useColors) {
      buffer.writeln('$_red  Error: ${record.error}$_reset');
    } else {
      buffer.writeln('  Error: ${record.error}');
    }
  }
  // Only show stack trace if it's non-null and non-empty.
  final stackStr = record.stackTrace?.toString();
  if (stackStr != null && stackStr.isNotEmpty) {
    if (useColors) {
      buffer.writeln('$_gray  Stack: $stackStr$_reset');
    } else {
      buffer.writeln('  Stack: $stackStr');
    }
  }

  return buffer.toString();
}

/// Collapses line breaks and ESC to a single space. A bare `\r` would
/// otherwise paint the rest of the record over the start of its own line, and
/// an ESC would let a value write terminal escape sequences.
String _singleLine(String value) => value.replaceAll(
      RegExp(r'[\r\n\v\f\u001b\u0085\u001c-\u001e\u2028\u2029]+'),
      ' ',
    );

/// Returns the ANSI color code for a given log level.
String _colorForLevel(LogLevel level) {
  return switch (level) {
    LogLevel.trace => _gray,
    LogLevel.debug => _gray,
    LogLevel.info => _cyan,
    LogLevel.warning => _yellow,
    LogLevel.error => _red,
    LogLevel.fatal => _red,
  };
}
