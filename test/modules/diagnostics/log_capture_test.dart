import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/log_capture.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

void main() {
  tearDown(LogManager.instance.reset);

  test('reports no capture when no memory sink is installed', () {
    // The screen renders this as "nothing is being collected", which is a
    // different message from "nothing was recorded" — so null has to survive
    // the lookup rather than arriving as an empty list.
    LogManager.instance.addSink(ConsoleSink());

    expect(capturedLogSink(LogManager.instance), isNull);
  });

  test('picks the first installed sink when a host installs several', () {
    // LogManager permits several, and the screen, its clear action and the
    // export all have to agree on which one they mean. Registration order is
    // the documented tie-break; a change here silently shows one buffer while
    // clearing another.
    final first = MemorySink();
    final second = MemorySink();
    LogManager.instance
      ..addSink(first)
      ..addSink(second);

    expect(capturedLogSink(LogManager.instance), same(first));
  });
}
