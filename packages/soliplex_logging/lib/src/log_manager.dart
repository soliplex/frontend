import 'dart:developer' as developer;

import 'package:soliplex_logging/src/log_level.dart';
import 'package:soliplex_logging/src/log_record.dart';
import 'package:soliplex_logging/src/log_sink.dart';

/// Singleton manager for log sinks and configuration.
class LogManager {
  LogManager._();

  /// The singleton instance.
  static final LogManager instance = LogManager._();

  final List<LogSink> _sinks = [];

  /// Minimum log level. Logs below this level are filtered out.
  LogLevel minimumLevel = .info;

  /// Adds a sink to receive log records.
  void addSink(LogSink sink) {
    if (!_sinks.contains(sink)) {
      _sinks.add(sink);
    }
  }

  /// Removes a sink.
  void removeSink(LogSink sink) {
    _sinks.remove(sink);
  }

  /// Returns all registered sinks.
  List<LogSink> get sinks => .unmodifiable(_sinks);

  /// Emits a log record to all sinks.
  ///
  /// Sink failures are caught and printed to stderr to prevent a faulty sink
  /// from crashing the application or blocking other sinks.
  void emit(LogRecord record) {
    for (final sink in _sinks) {
      try {
        sink.write(record);
      } on Object catch (e) {
        developer.log('Sink failed to write: $e', name: 'LogManager');
      }
    }
  }

  /// Flushes all sinks.
  Future<void> flush() async {
    await Future.wait(_sinks.map((s) => s.flush()));
  }

  /// Closes all sinks.
  ///
  /// Clears the sink list before awaiting close to prevent new writes
  /// from reaching sinks that are in the process of shutting down.
  Future<void> close() async {
    final sinksToClose = List.of(_sinks);
    _sinks.clear();
    await Future.wait(sinksToClose.map((s) => s.close()));
  }

  /// Resets the manager for testing.
  void reset() {
    _sinks.clear();
    minimumLevel = .info;
  }
}
