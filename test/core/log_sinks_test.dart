import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/core/log_sinks.dart';

void main() {
  tearDown(LogManager.instance.reset);

  test('installLogSinks registers console, stdout, and memory sinks', () {
    installLogSinks(LogManager.instance);

    final sinks = LogManager.instance.sinks;
    // Console sink → DevTools/IDE logging view (via dart:developer); stdout
    // sink → terminal / platform console. Both, so logs are visible regardless
    // of what's attached to the process.
    expect(sinks.whereType<ConsoleSink>(), hasLength(1));
    expect(sinks.whereType<StdoutSink>(), hasLength(1));
    // The memory sink is the only one that survives a native release build —
    // the other two ride transports a packaged AOT app does not have — so it
    // is what the in-app diagnostics screen reads. Losing it silently disables
    // field diagnosis entirely, which is why it is pinned here.
    expect(sinks.whereType<MemorySink>(), hasLength(1));
  });
}
