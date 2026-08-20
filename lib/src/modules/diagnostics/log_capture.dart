import 'package:soliplex_logging/soliplex_logging.dart';

/// The log records the diagnostics screen shows, alongside the HTTP exchanges
/// `NetworkInspector` collects.
///
/// Null when no [MemorySink] is installed, which is a different thing from a
/// sink holding no records — a host app embedding this package configures its
/// own sinks and need not include one, and then there is nothing to show
/// rather than nothing having happened. Callers are expected to render that
/// difference, not collapse it.
///
/// Returns the first sink when several are installed. [LogManager] permits
/// that, and this app installs exactly one of these (see `installLogSinks`,
/// which adds three sinks of which one is a MemorySink), but a host app that
/// installs two gets the earlier-registered one and no warning.
MemorySink? capturedLogSink(LogManager manager) =>
    manager.sinks.whereType<MemorySink>().firstOrNull;
