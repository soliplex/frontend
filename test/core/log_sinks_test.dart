import 'package:flutter_test/flutter_test.dart';

// The barrel, not `src/`: it is the only supported path for a host app, so
// importing `src/` here would let the export be dropped without a test
// failing.
import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  tearDown(LogManager.instance.reset);

  test('installLogSinks registers console, stdout, and memory sinks', () {
    // Not the value `reset` restores, so the floor assignment is observable.
    LogManager.instance.minimumLevel = LogLevel.error;

    installLogSinks();

    // Debug and profile only: `kReleaseMode` is a compile-time constant, so
    // the release floor cannot be reached from a test.
    expect(LogManager.instance.minimumLevel, LogLevel.info);
    final sinks = LogManager.instance.sinks;
    // Console sink → DevTools/IDE logging view (via dart:developer); stdout
    // sink → a terminal, on the platforms that hand the process one. Two
    // transports, so a record does not depend on a single one being attached.
    expect(sinks.whereType<ConsoleSink>(), hasLength(1));
    expect(sinks.whereType<StdoutSink>(), hasLength(1));
    // The memory sink is the only one that survives a native release build —
    // the other two ride transports a packaged AOT app does not have — so it
    // is what the in-app diagnostics screen reads. Losing it silently disables
    // field diagnosis entirely, which is why it is pinned here.
    expect(sinks.whereType<MemorySink>(), hasLength(1));
  });

  test('a host can compose a sink and name a logger through the barrel alone',
      () {
    final sink = _RecordingSink();
    LogManager.instance.addSink(sink);

    // `Logger`'s only constructor is private, so `LoggerFactory` — the
    // extension carrying `getLogger` — has to be exported too or the exported
    // `Logger` type is unobtainable. Dart `show` clauses gate extensions by
    // name, so dropping it from the barrel breaks this line.
    final Logger logger = LogManager.instance.getLogger('host.app');
    logger.warning('from the host');

    final LogRecord record = sink.records.single;
    expect(record.message, 'from the host');
  });
}

/// The whole point of exporting [LogSink]: a host implements its own sink
/// against the barrel, with no `soliplex_logging` dependency of its own.
class _RecordingSink implements LogSink {
  final records = <LogRecord>[];

  @override
  void write(LogRecord record) => records.add(record);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
