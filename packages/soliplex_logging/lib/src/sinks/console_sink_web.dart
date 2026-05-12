import 'dart:developer' as developer;
import 'dart:js_interop';

import 'package:soliplex_logging/src/log_level.dart';
import 'package:soliplex_logging/src/log_record.dart';
import 'package:soliplex_logging/src/sinks/log_format.dart';

@JS('console')
external JSConsole get _console;

/// Extension type for browser console with flexible argument types.
///
/// Uses [JSAny?] to preserve object references for browser inspection.
/// The browser console can display these as expandable objects.
extension type const JSConsole(JSObject _) implements JSObject {
  /// Logs a debug message (often hidden by default in browsers).
  external void debug(JSAny? message, [JSAny? arg1, JSAny? arg2]);

  /// Logs an info message (distinct icon in some browsers).
  external void info(JSAny? message, [JSAny? arg1, JSAny? arg2]);

  /// Logs a standard message.
  external void log(JSAny? message, [JSAny? arg1, JSAny? arg2]);

  /// Logs a warning message (yellow styling).
  external void warn(JSAny? message, [JSAny? arg1, JSAny? arg2]);

  /// Logs an error message (red styling).
  external void error(JSAny? message, [JSAny? arg1, JSAny? arg2]);
}

/// Writes a log record to both browser console and dart:developer.
///
/// Called by `ConsoleSink.write` via conditional import on web platform.
///
/// Dual output ensures logs are visible in:
/// - Browser F12 Console (for web developers)
/// - Dart DevTools (when connected for debugging)
///
/// Maps log levels to appropriate browser console methods:
/// - trace/debug -> console.debug (often hidden by default)
/// - info -> console.info (distinct icon)
/// - warning -> console.warn (yellow styling)
/// - error/fatal -> console.error (red styling)
///
/// Stack traces are appended to the message for guaranteed visibility.
void writeToConsole(LogRecord record) {
  final msgString = formatLogMessage(record);

  // 1. Write to browser JavaScript console.
  var browserMsg = msgString;
  if (record.stackTrace != null) {
    browserMsg += '\n${record.stackTrace}';
  }

  final message = browserMsg.toJS;
  final errorArg = _convertError(record.error);

  switch (record.level) {
    case .trace:
    case .debug:
      _console.debug(message, errorArg);
    case .info:
      _console.info(message, errorArg);
    case .warning:
      _console.warn(message, errorArg);
    case .error:
    case .fatal:
      _console.error(message, errorArg);
  }

  // 2. Also write to dart:developer for DevTools visibility.
  developer.log(
    msgString,
    name: record.loggerName,
    level: _mapLevel(record.level),
    time: record.timestamp,
    error: record.error,
    stackTrace: record.stackTrace,
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

/// Converts a Dart error to a JS object for browser inspection.
///
/// Creates a structured object with type and message that browsers
/// can display as an expandable tree structure.
///
/// Returns null if conversion fails to ensure logging never crashes the app.
JSAny? _convertError(Object? error) {
  if (error == null) return null;

  // Create a JS object with error details that browsers can inspect.
  // Wrapped in try-catch because a logging library must never crash the app,
  // even if the error object has problematic toString() implementations.
  try {
    return <String, Object?>{
      'type': error.runtimeType.toString(),
      'message': error.toString(),
    }.jsify();
  } on Object {
    // If conversion fails (e.g., problematic toString), return a safe fallback.
    return '[Error conversion failed]'.toJS;
  }
}
