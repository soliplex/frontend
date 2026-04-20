import 'package:meta/meta.dart';
import 'package:soliplex_logging/src/log_record.dart';
import 'package:soliplex_logging/src/log_sink.dart';

// IO is default, web overrides to no-op when js_interop is available.
import 'package:soliplex_logging/src/sinks/stdout_sink_io.dart'
    if (dart.library.js_interop) 'package:soliplex_logging/src/sinks/stdout_sink_web.dart'
    as platform;

/// Function type for stdout write operations.
///
/// Used for testing to capture log output without writing to actual stdout.
typedef StdoutWriter =
    void Function(
      LogRecord record, {
      required bool useColors,
    });

/// Log sink that outputs to stdout.
///
/// On native platforms (desktop, mobile), writes to stdout via `dart:io`.
/// On web, this is a no-op since stdout doesn't exist in browsers.
///
/// Primary use case: Desktop development where developers run from terminal
/// and need logs visible without IDE/DevTools attachment.
class StdoutSink implements LogSink {
  /// Creates a stdout sink.
  ///
  /// Set [enabled] to false to temporarily disable output.
  ///
  /// Set [useColors] to true to enable ANSI color codes for terminal output.
  /// Defaults to false for compatibility with terminals that don't support
  /// ANSI colors.
  ///
  /// The [testWriter] parameter is for testing only - it allows capturing
  /// log output without writing to actual stdout. When provided,
  /// records are passed to this function instead of stdout.
  StdoutSink({
    this.enabled = true,
    this.useColors = false,
    @visibleForTesting StdoutWriter? testWriter,
  }) : _testWriter = testWriter;

  /// Whether this sink is enabled.
  bool enabled;

  /// Whether to use ANSI color codes in output.
  final bool useColors;

  final StdoutWriter? _testWriter;

  @override
  void write(LogRecord record) {
    if (!enabled) return;

    // Use test writer if provided, otherwise delegate to platform.
    if (_testWriter != null) {
      _testWriter(record, useColors: useColors);
    } else {
      platform.writeToStdout(record, useColors: useColors);
    }
  }

  @override
  Future<void> flush() async {
    // Stdout output is unbuffered.
  }

  @override
  Future<void> close() async {
    enabled = false;
  }
}
