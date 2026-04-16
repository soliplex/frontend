import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Fake platform client with configurable responses and errors.
class FakePlatformClient implements SoliplexHttpClient {
  HttpResponse? nextResponse;
  SoliplexException? nextRequestError;

  StreamedHttpResponse? nextStreamResponse;
  SoliplexException? nextStreamError;
  StreamController<List<int>>? activeStreamController;

  Map<String, String>? lastRequestHeaders;
  int requestCount = 0;
  bool closed = false;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    requestCount++;
    lastRequestHeaders = headers;
    if (nextRequestError != null) throw nextRequestError!;
    return nextResponse!;
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    requestCount++;
    lastRequestHeaders = headers;
    cancelToken?.throwIfCancelled();
    if (nextStreamError != null) throw nextStreamError!;
    return nextStreamResponse!;
  }

  @override
  void close() {
    closed = true;
  }
}

/// Observer that records all HTTP events for verification.
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

  List<T> ofType<T extends HttpEvent>() => events.whereType<T>().toList();
}

/// Fake refresher that tracks calls and allows configurable failure.
class FakeTokenRefresher implements TokenRefresher {
  int refreshCallCount = 0;
  bool refreshResult = true;

  @override
  bool needsRefresh = false;

  @override
  Future<void> refreshIfExpiringSoon() async {}

  @override
  Future<bool> tryRefresh() async {
    refreshCallCount++;
    return refreshResult;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakePlatformClient platform;
  late RecordingObserver observer;
  late FakeTokenRefresher refresher;
  late HttpTransport transport;

  final testUri = Uri.parse('https://api.example.com/v1/test');

  setUp(() {
    platform = FakePlatformClient();
    observer = RecordingObserver();
    refresher = FakeTokenRefresher();

    final observable = ObservableHttpClient(
      client: platform,
      observers: [observer],
    );
    final authenticated = AuthenticatedHttpClient(
      observable,
      () => 'test-token',
    );
    final refreshing = RefreshingHttpClient(
      inner: authenticated,
      refresher: refresher,
    );
    transport = HttpTransport(client: refreshing);
  });

  group('REST path integration', () {
    test('successful GET flows through all decorators', () async {
      platform.nextResponse = HttpResponse(
        statusCode: 200,
        bodyBytes: Uint8List.fromList(utf8.encode('{"key":"value"}')),
        headers: const {'content-type': 'application/json'},
      );

      final result = await transport.request<Map<String, dynamic>>(
        'GET',
        testUri,
      );

      expect(result, equals({'key': 'value'}));
      expect(
        platform.lastRequestHeaders?['Authorization'],
        equals('Bearer test-token'),
      );

      final requests = observer.ofType<HttpRequestEvent>();
      expect(requests, hasLength(1));
      expect(requests.first.method, equals('GET'));

      final responses = observer.ofType<HttpResponseEvent>();
      expect(responses, hasLength(1));
      expect(responses.first.statusCode, equals(200));
    });

    test('401 response throws AuthException', () async {
      platform.nextResponse = HttpResponse(
        statusCode: 401,
        bodyBytes: Uint8List.fromList(utf8.encode('Unauthorized')),
      );

      Object? caughtError;
      try {
        await transport.request<void>('GET', testUri);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<AuthException>());
      expect((caughtError! as AuthException).statusCode, equals(401));
    });

    test('404 response throws NotFoundException', () async {
      platform.nextResponse = HttpResponse(
        statusCode: 404,
        bodyBytes: Uint8List.fromList(utf8.encode('Not Found')),
      );

      Object? caughtError;
      try {
        await transport.request<void>('GET', testUri);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<NotFoundException>());
    });

    test(
      'NetworkException from platform propagates through all layers',
      () async {
        platform.nextRequestError = const NetworkException(
          message: 'Connection refused',
        );

        Object? caughtError;
        try {
          await transport.request<void>('GET', testUri);
        } catch (e) {
          caughtError = e;
        }

        expect(caughtError, isA<NetworkException>());
        expect(
          (caughtError! as NetworkException).message,
          equals('Connection refused'),
        );

        // Observer should record error event
        final errors = observer.ofType<HttpErrorEvent>();
        expect(errors, hasLength(1));
        expect(errors.first.exception, isA<NetworkException>());
      },
    );

    test('CancelToken cancels before request reaches platform', () async {
      final token = CancelToken()..cancel('user abort');

      platform.nextResponse = HttpResponse(
        statusCode: 200,
        bodyBytes: Uint8List(0),
      );

      Object? caughtError;
      try {
        await transport.request<void>('GET', testUri, cancelToken: token);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<CancelledException>());
      expect(platform.requestCount, equals(0));
    });
  });

  group('Stream path integration', () {
    test('successful SSE returns StreamedHttpResponse', () async {
      final controller = StreamController<List<int>>();
      platform.nextStreamResponse = StreamedHttpResponse(
        statusCode: 200,
        body: controller.stream,
      );

      final response = await transport.requestStream(
        'GET',
        testUri,
        headers: {'Accept': 'text/event-stream'},
      );

      expect(response.statusCode, equals(200));

      final sub = response.body.listen((_) {});
      await controller.close();
      await sub.cancel();
    });

    test(
      'SSE stream data flows through observer with correct byte counts',
      () async {
        final controller = StreamController<List<int>>();
        platform.nextStreamResponse = StreamedHttpResponse(
          statusCode: 200,
          body: controller.stream,
        );

        final response = await transport.requestStream('GET', testUri);

        final chunks = <List<int>>[];
        final completer = Completer<void>();
        response.body.listen(chunks.add, onDone: completer.complete);

        controller
          ..add([1, 2, 3])
          ..add([4, 5]);
        await controller.close();
        await completer.future;

        expect(chunks, hasLength(2));
        expect(chunks[0], equals([1, 2, 3]));
        expect(chunks[1], equals([4, 5]));

        // Observer should record stream start and end
        final starts = observer.ofType<HttpStreamStartEvent>();
        expect(starts, hasLength(1));

        final ends = observer.ofType<HttpStreamEndEvent>();
        expect(ends, hasLength(1));
        expect(ends.first.isSuccess, isTrue);
        expect(ends.first.bytesReceived, equals(5));
      },
    );

    test('SSE 401 on connection throws AuthException from transport', () async {
      final controller = StreamController<List<int>>();
      platform.nextStreamResponse = StreamedHttpResponse(
        statusCode: 401,
        reasonPhrase: 'Unauthorized',
        body: controller.stream,
      );

      Object? caughtError;
      try {
        await transport.requestStream('GET', testUri);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<AuthException>());
      expect((caughtError! as AuthException).statusCode, equals(401));
      await controller.close();
    });

    test('CancelToken cancels SSE before connection', () async {
      final token = CancelToken()..cancel('abort');

      Object? caughtError;
      try {
        await transport.requestStream('GET', testUri, cancelToken: token);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<CancelledException>());
      expect(platform.requestCount, equals(0));
    });

    test('CancelToken cancels SSE during body consumption', () async {
      final token = CancelToken();
      final controller = StreamController<List<int>>();
      platform.nextStreamResponse = StreamedHttpResponse(
        statusCode: 200,
        body: controller.stream,
      );

      final response = await transport.requestStream(
        'GET',
        testUri,
        cancelToken: token,
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

      // Send some data then cancel
      controller.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);

      token.cancel('mid-stream abort');
      await completer.future;

      expect(errors, hasLength(1));
      expect(errors.first, isA<CancelledException>());

      await controller.close();
    });

    test(
      'observer receives onStreamStart and onStreamEnd for successful stream',
      () async {
        final controller = StreamController<List<int>>();
        platform.nextStreamResponse = StreamedHttpResponse(
          statusCode: 200,
          body: controller.stream,
        );

        final response = await transport.requestStream('GET', testUri);

        final completer = Completer<void>();
        response.body.listen((_) {}, onDone: completer.complete);

        controller.add([1, 2, 3]);
        await controller.close();
        await completer.future;

        final starts = observer.ofType<HttpStreamStartEvent>();
        expect(starts, hasLength(1));
        expect(starts.first.method, equals('GET'));
        expect(starts.first.uri, equals(testUri));

        final ends = observer.ofType<HttpStreamEndEvent>();
        expect(ends, hasLength(1));
        expect(ends.first.isSuccess, isTrue);
      },
    );

    test(
      'connection error during requestStream emits both onStreamStart and '
      'onStreamEnd(error)',
      () async {
        platform.nextStreamError = const NetworkException(
          message: 'Stream setup failed',
        );

        try {
          await transport.requestStream('GET', testUri);
        } catch (_) {}

        final starts = observer.ofType<HttpStreamStartEvent>();
        expect(starts, hasLength(1));

        final ends = observer.ofType<HttpStreamEndEvent>();
        expect(
          ends,
          hasLength(1),
          reason: 'onStreamEnd must fire even when the inner requestStream '
              'throws, so observers do not see a dangling open request',
        );
        expect(ends.single.error, isA<NetworkException>());
      },
    );
  });

  group('Resource cleanup', () {
    test(
      'cancelling stream subscription triggers observer onStreamEnd',
      () async {
        final controller = StreamController<List<int>>();
        platform.nextStreamResponse = StreamedHttpResponse(
          statusCode: 200,
          body: controller.stream,
        );

        final response = await transport.requestStream('GET', testUri);

        final subscription = response.body.listen((_) {});

        controller.add([1, 2, 3]);
        await Future<void>.delayed(Duration.zero);

        await subscription.cancel();
        await Future<void>.delayed(Duration.zero);

        final ends = observer.ofType<HttpStreamEndEvent>();
        expect(ends, hasLength(1));

        await controller.close();
      },
    );

    test('platform client close propagates through decorator chain', () {
      transport.close();
      expect(platform.closed, isTrue);
    });
  });
}
