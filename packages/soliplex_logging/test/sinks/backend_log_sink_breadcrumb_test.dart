import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_logging/src/sinks/disk_queue_io.dart';
import 'package:test/test.dart';

LogRecord makeRecord({
  LogLevel level = LogLevel.info,
  String message = 'Test message',
  String loggerName = 'Test',
  Map<String, Object> attributes = const {},
}) {
  return LogRecord(
    level: level,
    message: message,
    timestamp: DateTime.utc(2026, 2, 6, 12),
    loggerName: loggerName,
    attributes: attributes,
  );
}

void main() {
  late Directory tempDir;
  late PlatformDiskQueue diskQueue;
  late List<http.Request> capturedRequests;
  late http.Client mockClient;
  late MemorySink memorySink;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('breadcrumb_test_');
    diskQueue = PlatformDiskQueue(directoryPath: tempDir.path);
    capturedRequests = [];
    memorySink = MemorySink();

    mockClient = http_testing.MockClient((request) async {
      capturedRequests.add(request);
      return http.Response('', 200);
    });
  });

  tearDown(() async {
    await diskQueue.close();
    await memorySink.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  BackendLogSink createSink({
    bool withMemorySink = true,
    int maxBreadcrumbs = 20,
  }) {
    return BackendLogSink(
      endpoint: 'https://api.example.com/logs',
      client: mockClient,
      installId: 'install-001',
      sessionId: 'session-001',
      diskQueue: diskQueue,
      memorySink: withMemorySink ? memorySink : null,
      maxBreadcrumbs: maxBreadcrumbs,
      flushInterval: const Duration(hours: 1),
    );
  }

  group('breadcrumbs', () {
    test('error records include breadcrumbs from memorySink', () async {
      // Write some info records to memorySink.
      for (var i = 0; i < 5; i++) {
        memorySink.write(makeRecord(message: 'breadcrumb $i'));
      }

      final sink =
          createSink()
            ..write(makeRecord(level: LogLevel.error, message: 'crash'));
      // Error-level write triggers flush(force: true) internally.
      // Wait for that to complete, then close.
      await sink.close();

      expect(capturedRequests, isNotEmpty);
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;

      expect(record['breadcrumbs'], isA<List<Object?>>());
      final breadcrumbs = record['breadcrumbs']! as List<Object?>;
      expect(breadcrumbs, hasLength(5));

      final first = breadcrumbs.first! as Map<String, Object?>;
      expect(first['message'], 'breadcrumb 0');
      expect(first['level'], 'info');
      expect(first['category'], isA<String>());
    });

    test('info records do not include breadcrumbs', () async {
      memorySink.write(makeRecord(message: 'breadcrumb'));

      final sink = createSink()..write(makeRecord(message: 'normal'));
      await sink.flush();
      await sink.close();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;

      expect(record.containsKey('breadcrumbs'), isFalse);
    });

    test('breadcrumbs capped at 20 records', () async {
      for (var i = 0; i < 30; i++) {
        memorySink.write(makeRecord(message: 'crumb $i'));
      }

      final sink =
          createSink()
            ..write(makeRecord(level: LogLevel.error, message: 'crash'));
      await sink.flush();
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;
      final breadcrumbs = record['breadcrumbs']! as List<Object?>;

      expect(breadcrumbs, hasLength(20));
      // First breadcrumb should be crumb 10 (30 - 20).
      final first = breadcrumbs.first! as Map<String, Object?>;
      expect(first['message'], 'crumb 10');
    });

    test('no breadcrumbs when memorySink is null', () async {
      final sink = createSink(withMemorySink: false)
        ..write(makeRecord(level: LogLevel.error, message: 'crash'));
      await sink.flush();
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;

      expect(record.containsKey('breadcrumbs'), isFalse);
    });

    test('fatal records include breadcrumbs', () async {
      memorySink.write(makeRecord(message: 'context'));

      final sink =
          createSink()
            ..write(makeRecord(level: LogLevel.fatal, message: 'fatal crash'));
      await sink.flush();
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;

      expect(record['breadcrumbs'], isA<List<Object?>>());
    });

    test('empty memorySink produces empty breadcrumbs list', () async {
      final sink =
          createSink()
            ..write(makeRecord(level: LogLevel.error, message: 'crash'));
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;

      expect(record['breadcrumbs'], isA<List<Object?>>());
      expect(record['breadcrumbs']! as List<Object?>, isEmpty);
    });

    test('fewer than maxBreadcrumbs includes all available', () async {
      for (var i = 0; i < 3; i++) {
        memorySink.write(makeRecord(message: 'crumb $i'));
      }

      final sink =
          createSink()
            ..write(makeRecord(level: LogLevel.error, message: 'crash'));
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;
      final breadcrumbs = record['breadcrumbs']! as List<Object?>;

      expect(breadcrumbs, hasLength(3));
      final first = breadcrumbs.first! as Map<String, Object?>;
      expect(first['message'], 'crumb 0');
    });

    test('custom maxBreadcrumbs limits count', () async {
      for (var i = 0; i < 10; i++) {
        memorySink.write(makeRecord(message: 'crumb $i'));
      }

      final sink = createSink(maxBreadcrumbs: 5)
        ..write(makeRecord(level: LogLevel.error, message: 'crash'));
      await sink.close();

      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, Object?>;
      final logs = body['logs']! as List<Object?>;
      final record = logs.first! as Map<String, Object?>;
      final breadcrumbs = record['breadcrumbs']! as List<Object?>;

      expect(breadcrumbs, hasLength(5));
      // First breadcrumb should be crumb 5 (10 - 5).
      final first = breadcrumbs.first! as Map<String, Object?>;
      expect(first['message'], 'crumb 5');
    });
  });

  group('deriveBreadcrumbCategory', () {
    test('returns explicit category from attributes', () {
      final record = makeRecord(attributes: {'breadcrumb_category': 'custom'});
      expect(deriveBreadcrumbCategory(record), 'custom');
    });

    test('maps Router logger to ui', () {
      final record = makeRecord(loggerName: 'Router');
      expect(deriveBreadcrumbCategory(record), 'ui');
    });

    test('maps Router.Home sub-logger to ui', () {
      final record = makeRecord(loggerName: 'Router.Home');
      expect(deriveBreadcrumbCategory(record), 'ui');
    });

    test('maps Http logger to network', () {
      final record = makeRecord(loggerName: 'Http');
      expect(deriveBreadcrumbCategory(record), 'network');
    });

    test('maps Auth logger to user', () {
      final record = makeRecord(loggerName: 'Auth');
      expect(deriveBreadcrumbCategory(record), 'user');
    });

    test('maps Lifecycle logger to system', () {
      final record = makeRecord(loggerName: 'Lifecycle');
      expect(deriveBreadcrumbCategory(record), 'system');
    });

    test('falls back to system for unknown logger', () {
      final record = makeRecord(loggerName: 'SomeOther');
      expect(deriveBreadcrumbCategory(record), 'system');
    });
  });
}
