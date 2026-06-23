import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/core/log_sinks.dart';

void main() {
  tearDown(LogManager.instance.reset);

  test('installLogSinks registers a console sink and a stdout sink', () {
    installLogSinks(LogManager.instance);

    final sinks = LogManager.instance.sinks;
    // Console sink → DevTools/IDE logging view (via dart:developer); stdout
    // sink → terminal / platform console. Both, so logs are visible regardless
    // of what's attached to the process.
    expect(sinks.whereType<ConsoleSink>(), hasLength(1));
    expect(sinks.whereType<StdoutSink>(), hasLength(1));
  });
}
