import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:test/test.dart';

class MockSoliplexHttpClient extends Mock implements SoliplexHttpClient {}

class MockHttpObserver extends Mock implements HttpObserver {}

/// Test observer that records all events for verification.
class RecordingObserver implements HttpObserver {
  final events = <HttpEvent>[];

  @override
  void onRequest(HttpRequestEvent event) => events.add(event);

  @override
  void onResponse(HttpResponseEvent event) => events.add(event);

  @override
  void onError(HttpErrorEvent event) => events.add(event);

  @override
  void onStreamStart(HttpStreamStartEvent event) => events.add(event);

  @override
  void onStreamEnd(HttpStreamEndEvent event) => events.add(event);

  List<T> eventsOfType<T extends HttpEvent>() => events.whereType<T>().toList();
}

/// Object whose toString throws. Used to exercise the redaction
/// safety-net's outermost catch: _redactRequestBody falls through to
/// body.toString() for unknown types.
class _ThrowingToStringBody {
  @override
  String toString() => throw StateError('toString is broken');
}

/// Observer that throws on every callback.
class ThrowingObserver implements HttpObserver {
  @override
  void onRequest(HttpRequestEvent event) =>
      throw Exception('Observer onRequest error');

  @override
  void onResponse(HttpResponseEvent event) =>
      throw Exception('Observer onResponse error');

  @override
  void onError(HttpErrorEvent event) =>
      throw Exception('Observer onError error');

  @override
  void onStreamStart(HttpStreamStartEvent event) =>
      throw Exception('Observer onStreamStart error');

  @override
  void onStreamEnd(HttpStreamEndEvent event) =>
      throw Exception('Observer onStreamEnd error');
}

void main() {
  late MockSoliplexHttpClient mockClient;
  late RecordingObserver recorder;
  late ObservableHttpClient observableClient;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockClient = MockSoliplexHttpClient();
    recorder = RecordingObserver();
    observableClient = ObservableHttpClient(
      client: mockClient,
      observers: [recorder],
    );

    // Setup default close behavior
    when(() => mockClient.close()).thenReturn(null);
  });

  tearDown(() {
    // Reset mock state after each test
    reset(mockClient);
  });

  group('ObservableHttpClient', () {
    group('request lifecycle - success', () {
      test('notifies observer on request start and response', () async {
        final response = HttpResponse(
          statusCode: 200,
          bodyBytes: Uint8List.fromList(const [1, 2, 3, 4]),
          headers: const {'content-type': 'application/json'},
          reasonPhrase: 'OK',
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => response);

        final result = await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
          headers: {'Authorization': 'Bearer token'},
        );

        expect(result, equals(response));
        expect(recorder.events, hasLength(2));

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.method, equals('GET'));
        expect(requestEvent.uri.toString(), equals('https://example.com/api'));
        // Headers are now redacted by ObservableHttpClient
        expect(requestEvent.headers['Authorization'], equals('[REDACTED]'));

        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;
        expect(responseEvent.requestId, equals(requestEvent.requestId));
        expect(responseEvent.statusCode, equals(200));
        expect(responseEvent.bodySize, equals(4));
        expect(responseEvent.reasonPhrase, equals('OK'));
        expect(responseEvent.duration.inMicroseconds, greaterThanOrEqualTo(0));
      });

      test('passes through response unchanged', () async {
        final response = HttpResponse(
          statusCode: 201,
          bodyBytes: Uint8List.fromList(const [65, 66, 67]),
          headers: const {'x-custom': 'value'},
          reasonPhrase: 'Created',
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => response);

        final result = await observableClient.request(
          'POST',
          Uri.parse('https://example.com/create'),
          body: {'data': 'test'},
        );

        expect(result.statusCode, equals(201));
        expect(result.body, equals('ABC'));
        expect(result.headers['x-custom'], equals('value'));
        expect(result.reasonPhrase, equals('Created'));
      });

      test('records empty headers when none provided', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request('GET', Uri.parse('https://example.com'));

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.headers, isEmpty);
      });
    });

    group('request lifecycle - network error', () {
      test('notifies observer on network error and rethrows', () async {
        const exception = NetworkException(message: 'Connection refused');

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(exception);

        await expectLater(
          observableClient.request('GET', Uri.parse('https://example.com/api')),
          throwsA(equals(exception)),
        );

        expect(recorder.events, hasLength(2));

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        final errorEvent = recorder.eventsOfType<HttpErrorEvent>().first;

        expect(errorEvent.requestId, equals(requestEvent.requestId));
        expect(errorEvent.method, equals('GET'));
        expect(errorEvent.uri.toString(), equals('https://example.com/api'));
        expect(errorEvent.exception, equals(exception));
        expect(errorEvent.duration.inMicroseconds, greaterThanOrEqualTo(0));
      });

      test('notifies observer on timeout error', () async {
        const exception = NetworkException(
          message: 'Request timed out',
          isTimeout: true,
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(exception);

        await expectLater(
          observableClient.request(
            'POST',
            Uri.parse('https://example.com/slow'),
            timeout: const Duration(seconds: 5),
          ),
          throwsA(isA<NetworkException>()),
        );

        final errorEvent = recorder.eventsOfType<HttpErrorEvent>().first;
        expect(errorEvent.exception, isA<NetworkException>());
        expect((errorEvent.exception as NetworkException).isTimeout, isTrue);
      });

      test('notifies observer on auth error', () async {
        const exception = AuthException(
          message: 'Unauthorized',
          statusCode: 401,
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(exception);

        await expectLater(
          observableClient.request('GET', Uri.parse('https://example.com')),
          throwsA(equals(exception)),
        );

        final errorEvent = recorder.eventsOfType<HttpErrorEvent>().first;
        expect(errorEvent.exception, isA<AuthException>());
      });
    });

    group('stream lifecycle - success', () {
      test('notifies observer on stream start and end', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/stream'),
        );

        final chunks = <List<int>>[];
        final completer = Completer<void>();

        response.body.listen(
          chunks.add,
          onDone: completer.complete,
          onError: completer.completeError,
        );

        // Verify stream start event was sent
        expect(recorder.eventsOfType<HttpStreamStartEvent>(), hasLength(1));
        final startEvent = recorder.eventsOfType<HttpStreamStartEvent>().first;
        expect(startEvent.method, equals('GET'));
        expect(startEvent.uri.toString(), equals('https://example.com/stream'));

        // Send data and close
        controller
          ..add([1, 2, 3])
          ..add([4, 5]);
        await controller.close();

        await completer.future;

        expect(
          chunks,
          equals([
            [1, 2, 3],
            [4, 5],
          ]),
        );

        // Verify stream end event
        expect(recorder.eventsOfType<HttpStreamEndEvent>(), hasLength(1));
        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.requestId, equals(startEvent.requestId));
        expect(endEvent.bytesReceived, equals(5));
        expect(endEvent.isSuccess, isTrue);
        expect(endEvent.error, isNull);
      });

      test('tracks bytes received correctly', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com'),
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Send varying chunk sizes
        controller
          ..add([1, 2, 3, 4, 5]) // 5 bytes
          ..add([6, 7, 8]) // 3 bytes
          ..add([9, 10, 11, 12, 13, 14, 15]); // 7 bytes
        await controller.close();

        await completer.future;

        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.bytesReceived, equals(15));
      });
    });

    group('stream lifecycle - error', () {
      test(
        'sync-throw on response.body.listen emits onStreamEnd(error) and '
        'surfaces the error to the caller',
        () async {
          // A single-subscription stream that has already been listened
          // to elsewhere will throw a synchronous StateError on the
          // ObservableHttpClient's listen call. Without protection, the
          // decorator leaks a dangling onStreamStart (no onStreamEnd).
          final innerController = StreamController<List<int>>();
          innerController.stream.listen((_) {});

          when(
            () => mockClient.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => StreamedHttpResponse(
              statusCode: 200,
              body: innerController.stream,
            ),
          );

          final response = await observableClient.requestStream(
            'GET',
            Uri.parse('https://example.com/stream'),
          );

          final errors = <Object>[];
          final completer = Completer<void>();

          response.body.listen(
            (_) {},
            onError: (Object e) {
              errors.add(e);
              if (!completer.isCompleted) completer.complete();
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
          );

          await completer.future;

          expect(
            errors,
            hasLength(1),
            reason: 'Caller must still see the synchronous listen error — '
                'the protection must not mask the bug.',
          );
          expect(errors.single, isA<StateError>());

          final endEvents = recorder.eventsOfType<HttpStreamEndEvent>();
          expect(
            endEvents,
            hasLength(1),
            reason: 'onStreamEnd must fire so observers do not see a '
                'dangling onStreamStart when the inner body is not listenable.',
          );
          expect(endEvents.single.isSuccess, isFalse);

          await innerController.close();
        },
      );

      test(
        'notifies observer on stream error with SoliplexException',
        () async {
          final controller = StreamController<List<int>>();

          when(
            () => mockClient.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async =>
                StreamedHttpResponse(statusCode: 200, body: controller.stream),
          );

          final response = await observableClient.requestStream(
            'GET',
            Uri.parse('https://example.com/stream'),
          );

          final errors = <Object>[];
          final completer = Completer<void>();

          response.body.listen(
            (_) {},
            onError: (Object e) {
              errors.add(e);
              completer.complete();
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
          );

          // Add some data before error
          controller.add([1, 2, 3]);
          await Future<void>.delayed(const Duration(milliseconds: 10));

          // Emit error
          controller.addError(
            const NetworkException(message: 'Connection lost'),
          );

          await completer.future;

          expect(errors, hasLength(1));
          expect(errors.first, isA<NetworkException>());

          final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
          expect(endEvent.bytesReceived, equals(3));
          expect(endEvent.isSuccess, isFalse);
          expect(endEvent.error, isA<NetworkException>());

          await controller.close();
        },
      );

      test('wraps non-SoliplexException errors in NetworkException', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/stream'),
        );

        final errors = <Object>[];
        final completer = Completer<void>();

        response.body.listen(
          (_) {},
          onError: (Object e) {
            errors.add(e);
            completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );

        // Emit non-SoliplexException error
        controller.addError(Exception('Generic error'));

        await completer.future;

        // Original error should be passed through
        expect(errors.first, isA<Exception>());

        // Observer should receive wrapped NetworkException
        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.error, isA<NetworkException>());
        expect(endEvent.error!.message, contains('Generic error'));

        await controller.close();
      });

      test(
        'emits only one onStreamEnd when error and done both fire',
        () async {
          final controller = StreamController<List<int>>();

          when(
            () => mockClient.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async =>
                StreamedHttpResponse(statusCode: 200, body: controller.stream),
          );

          final response = await observableClient.requestStream(
            'GET',
            Uri.parse('https://example.com/stream'),
          );

          final completer = Completer<void>();

          response.body.listen(
            (_) {},
            onError: (_) {},
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
          );

          controller
            ..add('data: hello\n\n'.codeUnits)
            ..addError(const NetworkException(message: 'Connection closed'));
          await controller.close();

          await completer.future;

          final endEvents = recorder.eventsOfType<HttpStreamEndEvent>();
          expect(
            endEvents,
            hasLength(1),
            reason: 'Should emit exactly one onStreamEnd, not two',
          );
        },
      );

      test(
        'emits onStreamEnd when requestStream itself throws after '
        'onStreamStart',
        () async {
          when(
            () => mockClient.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenThrow(const NetworkException(message: 'connect refused'));

          await expectLater(
            () => observableClient.requestStream(
              'GET',
              Uri.parse('https://example.com/stream'),
            ),
            throwsA(isA<NetworkException>()),
          );

          final startEvents = recorder.eventsOfType<HttpStreamStartEvent>();
          final endEvents = recorder.eventsOfType<HttpStreamEndEvent>();
          expect(startEvents, hasLength(1));
          expect(
            endEvents,
            hasLength(1),
            reason: 'onStreamStart must have a matching onStreamEnd; '
                'otherwise observers see a forever-open request',
          );
          expect(endEvents.first.error, isA<NetworkException>());
        },
      );

      test(
        'redacts URI secrets when wrapping non-SoliplexException in '
        'NetworkException.message',
        () async {
          final controller = StreamController<List<int>>();

          when(
            () => mockClient.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async =>
                StreamedHttpResponse(statusCode: 200, body: controller.stream),
          );

          // Auth-endpoint URI triggers full-body redaction in HttpRedactor.
          final response = await observableClient.requestStream(
            'GET',
            Uri.parse('https://example.com/oauth/token?code=secret-abc-123'),
          );

          final completer = Completer<void>();
          response.body.listen(
            (_) {},
            onError: (_) {},
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
          );

          // A non-SoliplexException whose toString contains the full URI.
          controller.addError(
            Exception(
              'fetch failed for '
              'https://example.com/oauth/token?code=secret-abc-123',
            ),
          );
          await controller.close();
          await completer.future;

          final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
          final message = (endEvent.error! as NetworkException).message;
          expect(
            message,
            isNot(contains('secret-abc-123')),
            reason: 'NetworkException.message must be URI-redacted before '
                'emission so tokens do not leak through observers',
          );
        },
      );

      test('canceling stream emits successful onStreamEnd', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/stream'),
        );

        final subscription = response.body.listen((_) {});

        // Add some data first.
        controller.add('data: hello\n\n'.codeUnits);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Consumer cancels (simulates RunOrchestrator._cleanup()).
        await subscription.cancel();

        final endEvents = recorder.eventsOfType<HttpStreamEndEvent>();
        expect(endEvents, hasLength(1));
        expect(
          endEvents.first.isSuccess,
          isTrue,
          reason: 'Cancel should emit successful end, not error',
        );
        expect(endEvents.first.bytesReceived, greaterThan(0));

        await controller.close();
      });
    });

    group('multiple observers', () {
      test('notifies all observers in order', () async {
        final recorder1 = RecordingObserver();
        final recorder2 = RecordingObserver();
        final recorder3 = RecordingObserver();

        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [recorder1, recorder2, recorder3],
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request('GET', Uri.parse('https://example.com'));

        // All observers should have same events
        expect(recorder1.events, hasLength(2));
        expect(recorder2.events, hasLength(2));
        expect(recorder3.events, hasLength(2));

        // Same request ID across all observers
        final id1 = recorder1.eventsOfType<HttpRequestEvent>().first.requestId;
        final id2 = recorder2.eventsOfType<HttpRequestEvent>().first.requestId;
        final id3 = recorder3.eventsOfType<HttpRequestEvent>().first.requestId;
        expect(id1, equals(id2));
        expect(id2, equals(id3));

        observableClient.close();
      });

      test('one observer exception does not affect others', () async {
        final recorder1 = RecordingObserver();
        final throwingObserver = ThrowingObserver();
        final recorder2 = RecordingObserver();

        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [recorder1, throwingObserver, recorder2],
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        // Should not throw despite throwing observer
        await expectLater(
          observableClient.request('GET', Uri.parse('https://example.com')),
          completes,
        );

        // Both recording observers should still receive events
        expect(recorder1.events, hasLength(2));
        expect(recorder2.events, hasLength(2));

        observableClient.close();
      });

      test(
          'request body redaction failure yields <redaction failed> '
          'placeholder, logs a diagnostic, and does not break the request',
          () async {
        // Regression for the outer try/catch around _redactRequestBody:
        // if the redactor throws on pathological input (here: an object
        // whose toString throws), observers must see a placeholder and
        // the request must still complete.
        final diagnostics = <String>[];
        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [recorder],
          onDiagnostic: (_, __, {required message}) => diagnostics.add(message),
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'POST',
          Uri.parse('https://example.com/api'),
          body: _ThrowingToStringBody(),
        );

        final requests = recorder.eventsOfType<HttpRequestEvent>();
        expect(requests, hasLength(1));
        expect(
          requests.single.body,
          '<redaction failed>',
          reason: 'Observer must receive the placeholder when redaction '
              'throws — never the raw body, never a missing event.',
        );
        expect(
          diagnostics,
          contains('Request body redaction failed unexpectedly'),
          reason: 'Redaction failure must be visible in diagnostics so '
              'the bug can be found in production logs.',
        );

        observableClient.close();
      });

      test(
          'response body redaction failure yields <redaction failed> '
          'placeholder when the body getter throws on invalid UTF-8', () async {
        // HttpResponse.body calls utf8.decode(bodyBytes); invalid UTF-8
        // throws FormatException. With content-type application/json,
        // the inner method catches FormatException from jsonDecode but
        // then calls redactString which re-invokes the body getter —
        // the second throw escapes the inner method and is caught by
        // the outer safety net.
        final diagnostics = <String>[];
        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [recorder],
          onDiagnostic: (_, __, {required message}) => diagnostics.add(message),
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList(const [0xFF, 0xFE, 0xFD]),
            headers: const {'content-type': 'application/json'},
          ),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
        );

        final responses = recorder.eventsOfType<HttpResponseEvent>();
        expect(responses, hasLength(1));
        expect(
          responses.single.body,
          '<redaction failed>',
          reason: 'Observer must receive the placeholder when body '
              'decoding fails during redaction.',
        );
        expect(
          diagnostics,
          contains('Response body redaction failed unexpectedly'),
        );

        observableClient.close();
      });

      test(
          'request completes when the diagnostic handler itself throws — the '
          'safety wrapper must contain a broken sink', () async {
        // ThrowingObserver forces the decorator to call _onDiagnostic.
        // The handler then throws, simulating a transient Sentry failure.
        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [ThrowingObserver()],
          onDiagnostic: (_, __, {required message}) {
            throw StateError('diagnostic sink down');
          },
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await expectLater(
          observableClient.request('GET', Uri.parse('https://example.com')),
          completes,
          reason: 'A broken diagnostic sink must not break request flow.',
        );

        observableClient.close();
      });
    });

    group('observer error isolation', () {
      test('observer throwing on request does not break request', () async {
        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [ThrowingObserver()],
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList([1, 2, 3]),
          ),
        );

        final result = await observableClient.request(
          'GET',
          Uri.parse('https://example.com'),
        );

        expect(result.statusCode, equals(200));
        expect(result.bodyBytes, hasLength(3));

        observableClient.close();
      });

      test('observer throwing on response does not break request', () async {
        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [ThrowingObserver()],
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 201, bodyBytes: Uint8List(0)),
        );

        final result = await observableClient.request(
          'POST',
          Uri.parse('https://example.com'),
        );

        expect(result.statusCode, equals(201));

        observableClient.close();
      });

      test('observer throwing on error does not suppress exception', () async {
        final observableClient = ObservableHttpClient(
          client: mockClient,
          observers: [ThrowingObserver()],
        );

        const originalException = NetworkException(message: 'Network failed');

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(originalException);

        await expectLater(
          observableClient.request('GET', Uri.parse('https://example.com')),
          throwsA(equals(originalException)),
        );

        observableClient.close();
      });

      test(
        'observer throwing on stream events does not break stream',
        () async {
          final observableClient = ObservableHttpClient(
            client: mockClient,
            observers: [ThrowingObserver()],
          );

          final controller = StreamController<List<int>>();

          when(
            () => mockClient.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async =>
                StreamedHttpResponse(statusCode: 200, body: controller.stream),
          );

          final response = await observableClient.requestStream(
            'GET',
            Uri.parse('https://example.com'),
          );

          final chunks = <List<int>>[];
          final completer = Completer<void>();

          response.body.listen(chunks.add, onDone: completer.complete);

          controller
            ..add([1, 2, 3])
            ..add([4, 5, 6]);
          await controller.close();

          await completer.future;

          expect(
            chunks,
            equals([
              [1, 2, 3],
              [4, 5, 6],
            ]),
          );

          observableClient.close();
        },
      );
    });

    group('request ID correlation', () {
      test('same requestId across request/response events', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request('GET', Uri.parse('https://example.com'));

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;

        expect(requestEvent.requestId, isNotEmpty);
        expect(responseEvent.requestId, equals(requestEvent.requestId));
      });

      test('same requestId across request/error events', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NetworkException(message: 'Failed'));

        try {
          await observableClient.request(
            'GET',
            Uri.parse('https://example.com'),
          );
        } on NetworkException {
          // Expected
        }

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        final errorEvent = recorder.eventsOfType<HttpErrorEvent>().first;

        expect(errorEvent.requestId, equals(requestEvent.requestId));
      });

      test('same requestId across stream start/end events', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com'),
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        await controller.close();
        await completer.future;

        final startEvent = recorder.eventsOfType<HttpStreamStartEvent>().first;
        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;

        expect(startEvent.requestId, isNotEmpty);
        expect(endEvent.requestId, equals(startEvent.requestId));
      });

      test('different requests have different IDs', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/1'),
        );
        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/2'),
        );

        final requestEvents = recorder.eventsOfType<HttpRequestEvent>();
        expect(requestEvents, hasLength(2));
        expect(
          requestEvents[0].requestId,
          isNot(equals(requestEvents[1].requestId)),
        );
      });
    });

    group('custom request ID generator', () {
      test('uses provided generator', () async {
        var callCount = 0;
        final customClient = ObservableHttpClient(
          client: mockClient,
          observers: [recorder],
          generateRequestId: () => 'custom-id-${++callCount}',
        );

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await customClient.request('GET', Uri.parse('https://example.com'));

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.requestId, equals('custom-id-1'));

        customClient.close();
      });
    });

    group('close delegation', () {
      test('delegates close to wrapped client', () {
        observableClient.close();

        verify(() => mockClient.close()).called(1);
      });

      test('does not notify observers on close', () {
        observableClient.close();

        expect(recorder.events, isEmpty);
      });
    });

    group('empty observer list', () {
      test('works correctly with no observers', () async {
        final clientNoObservers = ObservableHttpClient(client: mockClient);

        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList([1, 2, 3]),
          ),
        );

        final result = await clientNoObservers.request(
          'GET',
          Uri.parse('https://example.com'),
        );

        expect(result.statusCode, equals(200));
        expect(result.bodyBytes, hasLength(3));

        clientNoObservers.close();
      });

      test('streaming works with no observers', () async {
        final clientNoObservers = ObservableHttpClient(client: mockClient);

        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await clientNoObservers.requestStream(
          'GET',
          Uri.parse('https://example.com'),
        );

        final chunks = <List<int>>[];
        final completer = Completer<void>();

        response.body.listen(chunks.add, onDone: completer.complete);

        controller
          ..add([1, 2])
          ..add([3, 4]);
        await controller.close();

        await completer.future;

        expect(
          chunks,
          equals([
            [1, 2],
            [3, 4],
          ]),
        );

        clientNoObservers.close();
      });
    });

    group('body and header capture', () {
      test('captures and redacts request body', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'POST',
          Uri.parse('https://example.com/api'),
          body: {'username': 'john', 'password': 'secret123'},
        );

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.body, isNotNull);
        final body = requestEvent.body as Map<String, dynamic>;
        expect(body['username'], equals('john'));
        expect(body['password'], equals('[REDACTED]'));
      });

      test('captures and redacts request headers', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
          headers: {
            'Authorization': 'Bearer secret-token',
            'Content-Type': 'application/json',
          },
        );

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.headers['Authorization'], equals('[REDACTED]'));
        expect(
          requestEvent.headers['Content-Type'],
          equals('application/json'),
        );
      });

      test('redacts sensitive query parameters in URI', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api?token=secret&page=1'),
        );

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.uri.queryParameters['token'], equals('[REDACTED]'));
        expect(requestEvent.uri.queryParameters['page'], equals('1'));
      });

      test('captures and redacts response body', () async {
        const responseBody = '{"user": "john", "token": "secret-jwt"}';
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList(responseBody.codeUnits),
            headers: const {'content-type': 'application/json'},
          ),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
        );

        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;
        expect(responseEvent.body, isNotNull);
        final body = responseEvent.body as Map<String, dynamic>;
        expect(body['user'], equals('john'));
        expect(body['token'], equals('[REDACTED]'));
      });

      test('captures and redacts response headers', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List(0),
            headers: const {
              'set-cookie': 'session=abc123',
              'content-type': 'application/json',
            },
          ),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
        );

        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;
        expect(responseEvent.headers, isNotNull);
        expect(responseEvent.headers!['set-cookie'], equals('[REDACTED]'));
        expect(
          responseEvent.headers!['content-type'],
          equals('application/json'),
        );
      });

      test('redacts entire body for auth endpoints', () async {
        const responseBody = '{"access_token": "jwt", "expires_in": 3600}';
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList(responseBody.codeUnits),
            headers: const {'content-type': 'application/json'},
          ),
        );

        await observableClient.request(
          'POST',
          Uri.parse('https://example.com/oauth/token'),
          body: {'grant_type': 'password', 'username': 'user'},
        );

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;

        expect(requestEvent.body, equals('[REDACTED - Auth Endpoint]'));
        expect(responseEvent.body, equals('[REDACTED - Auth Endpoint]'));
      });

      test('handles non-JSON response body as string', () async {
        const textBody = 'Plain text response';
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList(textBody.codeUnits),
            headers: const {'content-type': 'text/plain'},
          ),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
        );

        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;
        expect(responseEvent.body, equals(textBody));
      });

      test('handles empty response body', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 204, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'DELETE',
          Uri.parse('https://example.com/api/resource'),
        );

        final responseEvent = recorder.eventsOfType<HttpResponseEvent>().first;
        expect(responseEvent.body, equals(''));
      });

      test('handles null request body for GET requests', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'GET',
          Uri.parse('https://example.com/api'),
        );

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.body, isNull);
      });

      test(
        'redacts sensitive data in non-JSON/non-text response body',
        () async {
          // e.g., application/octet-stream or unknown content type
          const body = 'token=secret123&data=value';
          when(
            () => mockClient.request(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => HttpResponse(
              statusCode: 200,
              bodyBytes: Uint8List.fromList(body.codeUnits),
              headers: const {'content-type': 'application/octet-stream'},
            ),
          );

          await observableClient.request(
            'GET',
            Uri.parse('https://example.com/api'),
          );

          final responseEvent =
              recorder.eventsOfType<HttpResponseEvent>().first;
          // Should redact sensitive form fields even in unknown content types
          expect(responseEvent.body, contains('data=value'));
          expect(responseEvent.body, isNot(contains('secret123')));
        },
      );

      test('redacts binary upload body without decoding', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(
            statusCode: 204,
            bodyBytes: Uint8List(0),
          ),
        );

        await observableClient.request(
          'POST',
          Uri.parse('https://example.com/uploads/room-1'),
          headers: {'content-type': 'multipart/form-data; boundary=abc123'},
          body: List<int>.filled(1000, 0xFF),
        );

        final requestEvent = recorder.eventsOfType<HttpRequestEvent>().first;
        expect(requestEvent.body, equals('<binary upload: 1000 bytes>'));
      });
    });

    group('SSE stream request data', () {
      test('captures redacted headers in stream start event', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'POST',
          Uri.parse('https://example.com/api/runs'),
          headers: {
            'Authorization': 'Bearer secret-token',
            'Accept': 'text/event-stream',
          },
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        await controller.close();
        await completer.future;

        final startEvent = recorder.eventsOfType<HttpStreamStartEvent>().first;
        expect(startEvent.headers['Authorization'], equals('[REDACTED]'));
        expect(startEvent.headers['Accept'], equals('text/event-stream'));
      });

      test('captures redacted body in stream start event', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'POST',
          Uri.parse('https://example.com/api/runs'),
          body: {'thread_id': 't1', 'password': 'secret123'},
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        await controller.close();
        await completer.future;

        final startEvent = recorder.eventsOfType<HttpStreamStartEvent>().first;
        expect(startEvent.body, isNotNull);
        final body = startEvent.body as Map<String, dynamic>;
        expect(body['thread_id'], equals('t1'));
        expect(body['password'], equals('[REDACTED]'));
      });

      test('handles List<int> body in stream request', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        const jsonBody = '{"thread_id": "t1", "token": "secret"}';
        final response = await observableClient.requestStream(
          'POST',
          Uri.parse('https://example.com/api/runs'),
          body: jsonBody.codeUnits,
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        await controller.close();
        await completer.future;

        final startEvent = recorder.eventsOfType<HttpStreamStartEvent>().first;
        expect(startEvent.body, isNotNull);
        final body = startEvent.body as Map<String, dynamic>;
        expect(body['thread_id'], equals('t1'));
        expect(body['token'], equals('[REDACTED]'));
      });
    });

    group('SSE stream response body redaction', () {
      test('redacts sensitive fields in SSE stream body', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/events'),
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        const event =
            'event: message\ndata: {"text": "hello", "token": "secret123"}\n\n';
        controller.add(event.codeUnits);
        await controller.close();

        await completer.future;

        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.body, contains('hello'));
        expect(endEvent.body, isNot(contains('secret123')));
      });

      test('fully redacts SSE body for auth endpoints', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'POST',
          Uri.parse('https://example.com/oauth/token'),
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        const event = 'data: {"access_token": "secret-jwt"}\n\n';
        controller.add(event.codeUnits);
        await controller.close();

        await completer.future;

        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.body, equals('[REDACTED - Auth Endpoint]'));
      });

      test('redacts SSE body on stream error', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/events'),
        );

        final completer = Completer<void>();
        response.body.listen(
          (_) {},
          onError: (_) => completer.complete(),
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );

        const event = 'data: {"message": "test", "password": "secret"}\n\n';
        controller
          ..add(event.codeUnits)
          ..addError(const NetworkException(message: 'Connection lost'));

        await completer.future;

        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.body, contains('test'));
        expect(endEvent.body, isNot(contains('secret')));

        await controller.close();
      });
    });

    group('SSE stream buffering', () {
      test('buffers SSE content in stream end event', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/events'),
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        const event1 = 'event: message\ndata: {"text": "hello"}\n\n';
        const event2 = 'event: message\ndata: {"text": "world"}\n\n';
        controller
          ..add(event1.codeUnits)
          ..add(event2.codeUnits);
        await controller.close();

        await completer.future;

        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.body, isNotNull);
        expect(endEvent.body, contains('hello'));
        expect(endEvent.body, contains('world'));
      });

      test('truncates buffer when exceeding max size', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/events'),
        );

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        // Send more than 500KB of data
        final largeChunk = List.filled(100 * 1024, 65); // 100KB of 'A's
        for (var i = 0; i < 6; i++) {
          controller.add(largeChunk);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await controller.close();

        await completer.future;

        final endEvent = recorder.eventsOfType<HttpStreamEndEvent>().first;
        expect(endEvent.body, isNotNull);
        // Buffer should be capped and contain truncation indicator
        expect(endEvent.body!.length, lessThanOrEqualTo(500 * 1024 + 100));
      });
    });

    group('parameters forwarding', () {
      test('forwards all request parameters to wrapped client', () async {
        when(
          () => mockClient.request(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
        );

        await observableClient.request(
          'POST',
          Uri.parse('https://example.com/api'),
          headers: {'X-Custom': 'value'},
          body: {'key': 'data'},
          timeout: const Duration(seconds: 10),
        );

        verify(
          () => mockClient.request(
            'POST',
            Uri.parse('https://example.com/api'),
            headers: {'X-Custom': 'value'},
            body: {'key': 'data'},
            timeout: const Duration(seconds: 10),
          ),
        ).called(1);
      });

      test('forwards all stream parameters to wrapped client', () async {
        final controller = StreamController<List<int>>();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'POST',
          Uri.parse('https://example.com/stream'),
          headers: const {'Accept': 'text/event-stream'},
          body: 'test body',
        );

        final subscription = response.body.listen((_) {});

        verify(
          () => mockClient.requestStream(
            'POST',
            Uri.parse('https://example.com/stream'),
            headers: const {'Accept': 'text/event-stream'},
            body: 'test body',
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);

        await subscription.cancel();
        await controller.close();
      });

      test('forwards cancelToken to wrapped client', () async {
        final controller = StreamController<List<int>>();
        final token = CancelToken();

        when(
          () => mockClient.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: controller.stream),
        );

        final response = await observableClient.requestStream(
          'GET',
          Uri.parse('https://example.com/stream'),
          cancelToken: token,
        );

        final subscription = response.body.listen((_) {});

        verify(
          () => mockClient.requestStream(
            'GET',
            Uri.parse('https://example.com/stream'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: token,
          ),
        ).called(1);

        await subscription.cancel();
        await controller.close();
      });
    });
  });
}
