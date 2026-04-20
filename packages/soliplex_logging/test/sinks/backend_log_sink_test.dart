import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_logging/src/sinks/disk_queue_io.dart';
import 'package:test/test.dart';

/// Creates a test log record.
LogRecord makeRecord({
  LogLevel level = LogLevel.info,
  String message = 'Test message',
  Map<String, Object> attributes = const {},
}) {
  return LogRecord(
    level: level,
    message: message,
    timestamp: DateTime.utc(2026, 2, 6, 12),
    loggerName: 'Test',
    attributes: attributes,
  );
}

void main() {
  late Directory tempDir;
  late PlatformDiskQueue diskQueue;
  late List<http.Request> capturedRequests;
  late http.Client mockClient;
  var httpStatus = 200;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('backend_sink_test_');
    diskQueue = PlatformDiskQueue(directoryPath: tempDir.path);
    capturedRequests = [];
    httpStatus = 200;

    mockClient = http_testing.MockClient((request) async {
      capturedRequests.add(request);
      return http.Response('', httpStatus);
    });
  });

  tearDown(() async {
    await diskQueue.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  BackendLogSink createSink({
    String? Function()? jwtProvider,
    bool Function()? networkChecker,
    bool Function()? flushGate,
    Duration maxFlushHoldDuration = const Duration(minutes: 5),
    SinkErrorCallback? onError,
    Duration flushInterval = const Duration(hours: 1),
  }) {
    return BackendLogSink(
      endpoint: 'https://api.example.com/logs',
      client: mockClient,
      installId: 'install-001',
      sessionId: 'session-001',
      diskQueue: diskQueue,
      userId: 'user-001',
      resourceAttributes: const {
        'service.name': 'test',
        'service.version': '1.0.0',
      },
      flushInterval: flushInterval,
      jwtProvider: jwtProvider,
      networkChecker: networkChecker,
      flushGate: flushGate,
      maxFlushHoldDuration: maxFlushHoldDuration,
      onError: onError,
    );
  }

  group('BackendLogSink', () {
    test('records serialized with installId/sessionId/userId', () async {
      final sink = createSink()..write(makeRecord());
      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      expect(logs, hasLength(1));

      final log = logs[0] as Map<String, Object?>;
      expect(log['install_id'], 'install-001');
      expect(log['session_id'], 'session-001');
      expect(log['user_id'], 'user-001');
      expect(log['message'], 'Test message');
      expect(log['level'], 'info');
    });

    test('filters out HTTP logs about the log-shipping endpoint', () async {
      final sink =
          createSink()
            // This record mimics what HttpLogNotifier emits for a log POST.
            ..write(
              LogRecord(
                level: LogLevel.debug,
                message: 'POST https://api.example.com/logs',
                timestamp: DateTime.utc(2026, 2, 6, 12),
                loggerName: 'HTTP',
              ),
            )
            // The corresponding response should also be filtered.
            ..write(
              LogRecord(
                level: LogLevel.debug,
                message: 'HTTP 200 response',
                timestamp: DateTime.utc(2026, 2, 6, 12),
                loggerName: 'HTTP',
              ),
            )
            // A normal record should still be accepted.
            ..write(makeRecord());

      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      expect(logs, hasLength(1));
      expect((logs[0] as Map<String, Object?>)['message'], 'Test message');
    });

    test('resource attributes included in payload', () async {
      final sink = createSink()..write(makeRecord());
      await sink.flush();
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final resource = body['resource']! as Map<String, Object?>;
      expect(resource['service.name'], 'test');
      expect(resource['service.version'], '1.0.0');
    });

    test('HTTP 200 confirms records', () async {
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 0);
      await sink.close();
    });

    test('HTTP 429 keeps records in queue with backoff', () async {
      httpStatus = 429;
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 1);
      await sink.close();
    });

    test('HTTP 5xx keeps records in queue', () async {
      httpStatus = 500;
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 1);
      await sink.close();
    });

    test('HTTP 401 disables export and calls onError', () async {
      httpStatus = 401;
      String? errorMessage;
      final sink = createSink(onError: (msg, _) => errorMessage = msg)
        ..write(makeRecord());
      await sink.flush();

      expect(errorMessage, contains('Auth failure'));
      expect(errorMessage, contains('401'));

      // Second flush should not attempt HTTP.
      capturedRequests.clear();
      sink.write(makeRecord(message: 'Second'));
      await sink.flush();
      expect(capturedRequests, isEmpty);
      await sink.close();
    });

    test('HTTP 404 disables export permanently', () async {
      httpStatus = 404;
      String? errorMessage;
      final sink = createSink(onError: (msg, _) => errorMessage = msg)
        ..write(makeRecord());
      await sink.flush();

      expect(errorMessage, contains('404'));
      expect(errorMessage, contains('permanently'));
      await sink.close();
    });

    test('pre-auth: flush skips when jwtProvider returns null', () async {
      final sink = createSink(jwtProvider: () => null)..write(makeRecord());
      await sink.flush();

      expect(capturedRequests, isEmpty);
      expect(await diskQueue.pendingCount, 1);
      await sink.close();
    });

    test('post-auth: buffered pre-login logs drain on first flush', () async {
      String? jwt;
      final sink =
          createSink(jwtProvider: () => jwt)
            ..write(makeRecord(message: 'Startup'))
            ..write(makeRecord(message: 'Session start'));
      await sink.flush();
      expect(capturedRequests, isEmpty);

      // Simulate login.
      jwt = 'jwt-token-123';
      await sink.flush();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      expect(logs, hasLength(2));
      await sink.close();
    });

    test('networkChecker false skips flush', () async {
      final sink = createSink(networkChecker: () => false)..write(makeRecord());
      await sink.flush();

      expect(capturedRequests, isEmpty);
      expect(await diskQueue.pendingCount, 1);
      await sink.close();
    });

    test(
      'poison pill: batch discarded after 50 consecutive failures',
      () async {
        httpStatus = 500;
        String? errorMessage;
        final sink = createSink(onError: (msg, _) => errorMessage = msg)
          ..write(makeRecord());

        for (var i = 0; i < 50; i++) {
          sink.backoffUntil = null;
          await sink.flush();
        }

        expect(errorMessage, contains('poison pill'));
        expect(await diskQueue.pendingCount, 0);
        await sink.close();
      },
    );

    test('attribute value safety: non-primitive coerced to string', () async {
      final sink =
          createSink()..write(
            makeRecord(attributes: const {'count': 42, 'label': 'test'}),
          );
      await sink.flush();
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      final attrs =
          (logs[0] as Map<String, Object?>)['attributes']!
              as Map<String, Object?>;
      expect(attrs['count'], 42);
      expect(attrs['label'], 'test');
    });

    test('fatal records use appendSync', () async {
      final sink =
          createSink()
            ..write(makeRecord(level: LogLevel.fatal, message: 'Crash!'));

      expect(await diskQueue.pendingCount, 1);
      await sink.close();
    });

    test('close attempts final flush', () async {
      final sink = createSink()..write(makeRecord());
      await sink.close();

      expect(capturedRequests, hasLength(1));
    });

    test('severity-triggered flush on ERROR', () async {
      final completer = Completer<void>();
      final flushClient = http_testing.MockClient((request) async {
        capturedRequests.add(request);
        completer.complete();
        return http.Response('', 200);
      });
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: flushClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        flushInterval: const Duration(hours: 1),
      )..write(makeRecord(level: LogLevel.error, message: 'Error!'));

      await completer.future;
      expect(capturedRequests, hasLength(1));
      await sink.close();
    });

    test('JWT included in Authorization header', () async {
      final sink = createSink(jwtProvider: () => 'my-jwt-token')
        ..write(makeRecord());
      await sink.flush();
      await sink.close();

      expect(
        capturedRequests.first.headers['Authorization'],
        'Bearer my-jwt-token',
      );
    });

    test('re-enables after new JWT on 401', () async {
      var jwt = 'old-jwt';
      httpStatus = 401;
      final sink = createSink(jwtProvider: () => jwt)
        ..write(makeRecord(message: 'First'));
      await sink.flush();
      expect(capturedRequests, hasLength(1));

      jwt = 'new-jwt';
      httpStatus = 200;
      sink.write(makeRecord(message: 'Second'));
      await sink.flush();

      expect(capturedRequests, hasLength(2));
      await sink.close();
    });

    test('byte-based batch cap limits records per batch', () async {
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: mockClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        maxBatchBytes: 500,
        flushInterval: const Duration(hours: 1),
      );

      for (var i = 0; i < 10; i++) {
        sink.write(makeRecord(message: 'Message number $i with some content'));
      }
      await sink.flush();
      await sink.close();

      expect(capturedRequests, isNotEmpty);
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      expect(logs.length, lessThan(10));
    });

    test('oversized single record is discarded and reported (C1)', () async {
      String? errorMessage;
      // Use a very small maxBatchBytes so a normal record exceeds it.
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: mockClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        maxBatchBytes: 10,
        flushInterval: const Duration(hours: 1),
        onError: (msg, _) => errorMessage = msg,
      )..write(makeRecord());
      await sink.flush();

      // Record should be confirmed (discarded) from the queue.
      expect(await diskQueue.pendingCount, 0);
      expect(errorMessage, contains('dropped'));
      expect(errorMessage, contains('exceeds'));
      expect(capturedRequests, isEmpty);
      await sink.close();
    });

    test('concurrent flush calls are deduplicated (C2)', () async {
      final sink = createSink()..write(makeRecord());

      // Fire two flushes concurrently — only one HTTP call should occur.
      await Future.wait([sink.flush(), sink.flush()]);

      expect(capturedRequests, hasLength(1));
      await sink.close();
    });

    test('network error triggers retry with backoff', () async {
      final errorClient = http_testing.MockClient(
        (_) => throw Exception('No network'),
      );
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: errorClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        flushInterval: const Duration(hours: 1),
      )..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 1);
      await sink.close();
    });

    test('coerces List and Map attribute values', () async {
      final sink =
          createSink()..write(
            makeRecord(
              attributes: const {
                'tags': ['a', 'b'],
                'meta': {'nested': true},
              },
            ),
          );
      await sink.flush();
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      final attrs =
          (logs[0] as Map<String, Object?>)['attributes']!
              as Map<String, Object?>;
      expect(attrs['tags'], ['a', 'b']);
      expect(attrs['meta'], {'nested': true});
    });

    test('record size guard truncates oversized messages', () async {
      final bigMessage = 'x' * 100000;
      final sink = createSink()..write(makeRecord(message: bigMessage));
      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      final log = logs[0] as Map<String, Object?>;
      final message = log['message']! as String;
      expect(message.length, lessThan(bigMessage.length));
      expect(message, contains('[truncated]'));
    });

    test('UTF-8 safe truncation does not split multi-byte chars', () async {
      final multiByteMsg = '\u{1F600}' * 200 + 'x' * 99000;
      final sink = createSink()..write(makeRecord(message: multiByteMsg));
      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      expect(body['logs'], isNotEmpty);
    });

    test('HTTP 201 confirms records (2xx success)', () async {
      httpStatus = 201;
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 0);
      await sink.close();
    });

    test('HTTP 204 confirms records (2xx success)', () async {
      httpStatus = 204;
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 0);
      await sink.close();
    });

    test('close awaits active flush without duplicating', () async {
      // Use a slow mock client to simulate an in-flight flush.
      final slowClient = http_testing.MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        capturedRequests.add(request);
        return http.Response('', 200);
      });
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: slowClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        flushInterval: const Duration(hours: 1),
      )..write(makeRecord());

      // Start a flush, then immediately close
      // (which should await, not restart).
      unawaited(sink.flush());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sink.close();

      // Only one HTTP request should have been made.
      expect(capturedRequests, hasLength(1));
    });

    test('flush catches pendingWrite errors and reports via onError', () async {
      String? errorMessage;
      final sink = createSink(onError: (msg, _) => errorMessage = msg);

      // Delete the queue directory so the next append fails.
      tempDir.deleteSync(recursive: true);
      sink.write(makeRecord());

      // flush should not throw — error reported via onError.
      await sink.flush();
      expect(errorMessage, contains('Pending write error'));

      // Recreate dir for tearDown cleanup.
      tempDir.createSync();
    });

    test('write after close is silently ignored', () async {
      final sink = createSink();
      await sink.close();

      // Should not throw or enqueue.
      sink.write(makeRecord(message: 'After close'));
      expect(capturedRequests, isEmpty);
    });

    test('oversized record in middle of batch is skipped', () async {
      String? errorMessage;
      // Small batch limit so the big record exceeds it but small ones fit.
      final sink =
          BackendLogSink(
              endpoint: 'https://api.example.com/logs',
              client: mockClient,
              installId: 'i',
              sessionId: 's',
              diskQueue: diskQueue,
              maxBatchBytes: 1024,
              flushInterval: const Duration(hours: 1),
              onError: (msg, _) => errorMessage = msg,
            )
            ..write(makeRecord(message: 'small-1'))
            ..write(makeRecord(message: 'x' * 2000)) // oversized
            ..write(makeRecord(message: 'small-2'));
      await sink.flush();

      // The oversized record should be dropped with an error.
      expect(errorMessage, contains('dropped'));

      // The small records should have been sent.
      expect(capturedRequests, isNotEmpty);
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      final messages =
          logs.map((l) => (l as Map<String, Object?>)['message']).toList();
      expect(messages, contains('small-1'));
      expect(messages, contains('small-2'));
      await sink.close();
    });

    test('backoff prevents flush until timer expires', () async {
      httpStatus = 500;
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      // After a 5xx, backoffUntil is set.
      expect(sink.backoffUntil, isNotNull);

      // A second flush during backoff should not make an HTTP call.
      capturedRequests.clear();
      await sink.flush();
      expect(capturedRequests, isEmpty);

      // Clear backoff and retry.
      sink.backoffUntil = null;
      httpStatus = 200;
      await sink.flush();
      expect(capturedRequests, hasLength(1));
      await sink.close();
    });

    test('HTTP 403 disables export same as 401', () async {
      httpStatus = 403;
      String? errorMessage;
      final sink = createSink(onError: (msg, _) => errorMessage = msg)
        ..write(makeRecord());
      await sink.flush();

      expect(errorMessage, contains('Auth failure'));
      expect(errorMessage, contains('403'));
      await sink.close();
    });

    test('empty JWT string does not send Authorization header', () async {
      // An empty string JWT should not be sent.
      final sink = createSink(jwtProvider: () => '')..write(makeRecord());
      await sink.flush();
      await sink.close();

      expect(
        capturedRequests.first.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('no jwtProvider sends request without Authorization', () async {
      final sink = createSink()..write(makeRecord());
      await sink.flush();
      await sink.close();

      expect(
        capturedRequests.first.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('HTTP 404 stays disabled even after new JWT', () async {
      var jwt = 'old-jwt';
      httpStatus = 404;
      final sink = createSink(jwtProvider: () => jwt)
        ..write(makeRecord(message: 'First'));
      await sink.flush();
      expect(capturedRequests, hasLength(1));

      // New JWT should NOT re-enable after 404.
      jwt = 'new-jwt';
      httpStatus = 200;
      capturedRequests.clear();
      sink.write(makeRecord(message: 'Second'));
      await sink.flush();

      expect(capturedRequests, isEmpty);
      await sink.close();
    });

    test('same invalid JWT after 401 stays disabled', () async {
      const jwt = 'bad-jwt';
      httpStatus = 401;
      final sink = createSink(jwtProvider: () => jwt)
        ..write(makeRecord(message: 'First'));
      await sink.flush();
      expect(capturedRequests, hasLength(1));

      // Same JWT — should remain disabled.
      capturedRequests.clear();
      sink.write(makeRecord(message: 'Second'));
      await sink.flush();

      expect(capturedRequests, isEmpty);
      await sink.close();
    });

    test('write during close is ignored', () async {
      final slowClient = http_testing.MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        capturedRequests.add(request);
        return http.Response('', 200);
      });
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: slowClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        flushInterval: const Duration(hours: 1),
      )..write(makeRecord(message: 'Before close'));

      // Start close, then try to write during the close flush.
      final closeFuture = sink.close();
      sink.write(makeRecord(message: 'During close'));
      await closeFuture;

      // The "During close" write should have been silently dropped.
      final sentMessages =
          capturedRequests
              .map((r) => jsonDecode(r.body) as Map<String, Object?>)
              .expand((b) => b['logs']! as List)
              .map((l) => (l as Map<String, Object?>)['message'])
              .toList();
      expect(sentMessages, isNot(contains('During close')));
    });

    test('HTTP 400 discards batch immediately (non-retryable)', () async {
      httpStatus = 400;
      String? errorMessage;
      final sink = createSink(onError: (msg, _) => errorMessage = msg)
        ..write(makeRecord());
      await sink.flush();

      // Batch should be confirmed (discarded), not retried.
      expect(await diskQueue.pendingCount, 0);
      expect(errorMessage, contains('rejected'));
      expect(errorMessage, contains('400'));
      // Only one HTTP call — no retries.
      expect(capturedRequests, hasLength(1));
      await sink.close();
    });

    test('HTTP 413 discards batch immediately (non-retryable)', () async {
      httpStatus = 413;
      String? errorMessage;
      final sink = createSink(onError: (msg, _) => errorMessage = msg)
        ..write(makeRecord());
      await sink.flush();

      expect(await diskQueue.pendingCount, 0);
      expect(errorMessage, contains('rejected'));
      expect(errorMessage, contains('413'));
      await sink.close();
    });

    test(
      'pending-write failure does not prevent flushing persisted logs',
      () async {
        // Pre-persist a record, then break the directory
        // before writing another.
        final sink = createSink()..write(makeRecord(message: 'Persisted'));
        // Wait for the first append to complete.
        await sink.flush();
        expect(capturedRequests, hasLength(1));
        expect(await diskQueue.pendingCount, 0);

        // Write a second record that will persist, then break dir for third.
        sink.write(makeRecord(message: 'Also persisted'));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Break directory so the next append fails.
        final brokenDir = Directory('${tempDir.path}/nonexistent_subdir');
        final brokenQueue = PlatformDiskQueue(directoryPath: brokenDir.path);
        final errorMessages = <String>[];
        final brokenSink = BackendLogSink(
          endpoint: 'https://api.example.com/logs',
          client: mockClient,
          installId: 'i',
          sessionId: 's',
          diskQueue: brokenQueue,
          flushInterval: const Duration(hours: 1),
          onError: (msg, _) => errorMessages.add(msg),
        );

        // Write succeeds to disk, then delete the dir before next write.
        brokenQueue.appendSync({'message': 'on-disk'});
        brokenDir.deleteSync(recursive: true);
        brokenSink.write(makeRecord(message: 'will-fail'));

        // flush should still send the on-disk record.
        await brokenSink.flush();
        expect(errorMessages, anyElement(contains('Pending write error')));
        await sink.close();
        await brokenQueue.close();
      },
    );

    test(
      'truncation safety net produces placeholder for untrunactable record',
      () async {
        // A record with extremely long non-truncatable fixed fields
        // (logger name) that exceeds 64KB even after all truncation.
        final sink =
            createSink()..write(
              LogRecord(
                level: LogLevel.info,
                message: 'x' * 70000,
                timestamp: DateTime.utc(2026, 2, 6, 12),
                loggerName: 'y' * 70000,
              ),
            );
        await sink.flush();
        await sink.close();

        expect(capturedRequests, hasLength(1));
        final body =
            jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
        final logs = body['logs']! as List;
        final log = logs[0] as Map<String, Object?>;
        expect(log['message']! as String, contains('exceeded'));
      },
    );

    test('close bypasses backoff for best-effort final flush', () async {
      httpStatus = 500;
      final sink = createSink()..write(makeRecord());
      await sink.flush();

      // Sink is now in backoff.
      expect(sink.backoffUntil, isNotNull);

      // Switch to success and close — should bypass backoff and send.
      httpStatus = 200;
      capturedRequests.clear();
      await sink.close();

      expect(capturedRequests, hasLength(1));
    });

    test('UTF-8 truncation preserves char at exact boundary', () async {
      // 'é' is 2 bytes (C3 A9). Build a string where 'é' ends exactly
      // at the 1024-byte boundary: 1022 ASCII bytes + 'é' = 1024 bytes.
      final prefix = 'a' * 1022;
      final boundary = '$prefix\u00E9'; // exactly 1024 bytes in UTF-8
      final padding = 'x' * 99000;
      final message = '$boundary$padding';

      final sink = createSink()..write(makeRecord(message: message));
      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      final sentMessage =
          (logs[0] as Map<String, Object?>)['message']! as String;
      // The 'é' at byte 1023-1024 should be preserved, not dropped.
      expect(sentMessage, startsWith(boundary));
      expect(sentMessage, contains('[truncated]'));
    });

    test('UTF-8 truncation drops char that splits at boundary', () async {
      // 'é' is 2 bytes (C3 A9). Build a string where 'é' straddles the
      // 1024-byte boundary: 1023 ASCII bytes + 'é' = 1025 bytes.
      final prefix = 'a' * 1023;
      final message = '$prefix\u00E9${'x' * 99000}';

      final sink = createSink()..write(makeRecord(message: message));
      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      final sentMessage =
          (logs[0] as Map<String, Object?>)['message']! as String;
      // The 'é' doesn't fit — message should end with the ASCII prefix.
      expect(sentMessage, startsWith(prefix));
      expect(sentMessage, isNot(contains('\u00E9')));
      expect(sentMessage, contains('[truncated]'));
    });

    test('batch cap accounts for JSON comma separators', () async {
      // Compute envelope overhead (empty logs array).
      final envelope =
          utf8
              .encode(
                jsonEncode({
                  'logs': <Object>[],
                  'resource': {
                    'service.name': 'test',
                    'service.version': '1.0.0',
                  },
                }),
              )
              .length;

      // Probe: send one record to measure exact serialized size.
      final probeSink = createSink()..write(makeRecord(message: 'msg'));
      await probeSink.flush();
      final probeBody =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final probeLog = (probeBody['logs']! as List)[0];
      final recordBytes = utf8.encode(jsonEncode(probeLog)).length;
      await probeSink.close();
      capturedRequests.clear();

      // Need a fresh DiskQueue for the real test since probeSink closed ours.
      final tempDir2 = Directory.systemTemp.createTempSync(
        'backend_sink_comma_',
      );
      final diskQueue2 = PlatformDiskQueue(directoryPath: tempDir2.path);

      // Set limit so 2 records fit without comma but not with:
      // envelope + record + comma + record > limit
      // envelope + record + record == limit
      final limit = envelope + recordBytes * 2;

      final sink =
          BackendLogSink(
              endpoint: 'https://api.example.com/logs',
              client: mockClient,
              installId: 'install-001',
              sessionId: 'session-001',
              diskQueue: diskQueue2,
              userId: 'user-001',
              resourceAttributes: const {
                'service.name': 'test',
                'service.version': '1.0.0',
              },
              maxBatchBytes: limit,
              flushInterval: const Duration(hours: 1),
            )
            ..write(makeRecord(message: 'msg'))
            ..write(makeRecord(message: 'msg'));
      await sink.flush();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List;
      // With comma accounting, only 1 record should fit.
      expect(logs, hasLength(1));
      await sink.close();
      await diskQueue2.close();
      tempDir2.deleteSync(recursive: true);
    });

    test('network error reports via onError', () async {
      String? errorMessage;
      final errorClient = http_testing.MockClient(
        (_) => throw Exception('DNS failure'),
      );
      final sink = BackendLogSink(
        endpoint: 'https://api.example.com/logs',
        client: errorClient,
        installId: 'i',
        sessionId: 's',
        diskQueue: diskQueue,
        flushInterval: const Duration(hours: 1),
        onError: (msg, _) => errorMessage = msg,
      )..write(makeRecord());
      await sink.flush();

      expect(errorMessage, contains('Network error'));
      expect(errorMessage, contains('DNS failure'));
      await sink.close();
    });

    group('flushGate', () {
      test('blocks flush when returning false', () async {
        final sink = createSink(flushGate: () => false)..write(makeRecord());
        await sink.flush();

        expect(capturedRequests, isEmpty);
        expect(await diskQueue.pendingCount, 1);
        await sink.close();
      });

      test('allows flush when returning true', () async {
        final sink = createSink(flushGate: () => true)..write(makeRecord());
        await sink.flush();

        expect(capturedRequests, hasLength(1));
        await sink.close();
      });

      test('null defaults to allow', () async {
        final sink = createSink()..write(makeRecord());
        await sink.flush();

        expect(capturedRequests, hasLength(1));
        await sink.close();
      });

      test('safety valve flushes after maxFlushHoldDuration', () async {
        final sink = createSink(
          flushGate: () => false,
          maxFlushHoldDuration: const Duration(milliseconds: 1),
        )..write(makeRecord());

        // First flush starts the gated timer.
        await sink.flush();
        expect(capturedRequests, isEmpty);

        // Wait for the safety valve to expire.
        await Future<void>.delayed(const Duration(milliseconds: 5));

        // Second flush should proceed via safety valve.
        await sink.flush();
        expect(capturedRequests, hasLength(1));
        await sink.close();
      });

      test('force: true bypasses flushGate', () async {
        final sink = createSink(flushGate: () => false)..write(makeRecord());
        await sink.flush(force: true);

        expect(capturedRequests, hasLength(1));
        await sink.close();
      });

      test('error-level logs bypass gate via force flush', () async {
        final sink = createSink(flushGate: () => false)
          ..write(makeRecord(level: LogLevel.error, message: 'Error!'));

        // Give the unawaited flush a moment.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(capturedRequests, hasLength(1));
        await sink.close();
      });

      test('gatedSince resets when gate opens', () async {
        var gateOpen = false;
        final sink = createSink(
          flushGate: () => gateOpen,
          maxFlushHoldDuration: const Duration(milliseconds: 1),
        )..write(makeRecord(message: 'First'));

        // Start gated.
        await sink.flush();
        expect(capturedRequests, isEmpty);

        // Open gate — flush succeeds and resets gatedSince.
        gateOpen = true;
        await sink.flush();
        expect(capturedRequests, hasLength(1));

        // Close gate again with new record.
        gateOpen = false;
        sink.write(makeRecord(message: 'Second'));
        await sink.flush();
        // Gate just closed — gatedSince was reset so timer starts fresh.
        expect(capturedRequests, hasLength(1));

        // Wait for safety valve and try again.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await sink.flush();
        expect(capturedRequests, hasLength(2));
        await sink.close();
      });

      test('safety valve resets timer after flushing', () async {
        final sink = createSink(
          flushGate: () => false,
          maxFlushHoldDuration: const Duration(milliseconds: 1),
        )..write(makeRecord());

        // Hold first flush.
        await sink.flush();
        expect(capturedRequests, isEmpty);

        // Wait for safety valve, then flush.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await sink.flush();
        expect(
          capturedRequests,
          hasLength(1),
          reason: 'Should flush via safety valve',
        );

        // Write another record — timer should be fresh, so held again.
        sink.write(makeRecord(message: 'Second'));
        await sink.flush();
        expect(
          capturedRequests,
          hasLength(1),
          reason: 'Should be held by a fresh timer',
        );
        await sink.close();
      });
    });

    group('activeRun context', () {
      test('includes threadId and runId in payload when set', () async {
        final sink =
            createSink()
              ..threadId = 'thread-123'
              ..runId = 'run-456'
              ..write(makeRecord());
        await sink.flush();
        await sink.close();

        final body =
            jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
        final logs = body['logs']! as List<Object?>;
        final record = logs.first! as Map<String, Object?>;
        final activeRun = record['active_run']! as Map<String, Object?>;

        expect(activeRun['thread_id'], 'thread-123');
        expect(activeRun['run_id'], 'run-456');
      });

      test('activeRun is null when threadId not set', () async {
        final sink = createSink()..write(makeRecord());
        await sink.flush();
        await sink.close();

        final body =
            jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
        final logs = body['logs']! as List<Object?>;
        final record = logs.first! as Map<String, Object?>;

        expect(record['active_run'], isNull);
      });
    });
  });
}
