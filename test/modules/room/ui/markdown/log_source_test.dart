import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/log_source.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

void main() {
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    sink = MemorySink();
    LogManager.instance.addSink(sink);
    logger = LogManager.instance.getLogger('test.log_source');
  });

  tearDown(() => LogManager.instance.removeSink(sink));

  group('safeSourceForLog', () {
    test('redacts a data: URI payload to a length marker', () {
      final safe = safeSourceForLog('data:image/png;base64,AAAA');

      expect(safe, 'data:image/png;base64,<4 chars redacted>');
      expect(safe, isNot(contains('AAAA')));
    });

    test('marks a data: URI with no payload separator', () {
      expect(safeSourceForLog('data:image/png'), 'data:<no payload separator>');
    });

    test('truncates a long non-data URI and appends its length', () {
      final long = 'http://example.com/${'a' * 200}';

      final safe = safeSourceForLog(long);

      expect(safe, startsWith(long.substring(0, 120)));
      expect(safe, endsWith('…(${long.length} chars)'));
    });
  });

  group('logFailedSourceOnce', () {
    test('logs a source once and drops repeats', () {
      logFailedSourceOnce(logger, 'boom', 'source-once');
      logFailedSourceOnce(logger, 'boom again', 'source-once');

      expect(
        sink.records.where((r) => r.message.startsWith('boom')),
        hasLength(1),
      );
    });

    test('logs distinct sources separately', () {
      logFailedSourceOnce(logger, 'first', 'source-distinct-a');
      logFailedSourceOnce(logger, 'second', 'source-distinct-b');

      expect(sink.records.where((r) => r.message == 'first'), hasLength(1));
      expect(sink.records.where((r) => r.message == 'second'), hasLength(1));
    });

    test(
        'two data: URIs sharing a header and payload length but differing bytes '
        'each log', () {
      // Same mime header and identical base64 length; only the payload bytes
      // differ. Deduping on the redacted form (which replaces the payload with
      // just its length) would collapse these two distinct failures into one.
      logFailedSourceOnce(
          logger, 'decode failed', 'data:image/png;base64,AAAA');
      logFailedSourceOnce(
          logger, 'decode failed', 'data:image/png;base64,BBBB');

      expect(
        sink.records.where((r) => r.message == 'decode failed'),
        hasLength(2),
      );
    });
  });
}
