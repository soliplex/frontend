import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthenticatedHttpClient,
        ConcurrencyLimitingHttpClient,
        RefreshingHttpClient;
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements SoliplexHttpClient {}

class _MockObserver extends Mock implements HttpObserver {}

class _MockTokenRefresher extends Mock implements TokenRefresher {}

class _ConcurrencyTrackingInner implements SoliplexHttpClient {
  int _inFlight = 0;
  int maxInFlight = 0;
  final _gate = Completer<void>();

  void releaseAll() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await _gate.future;
      return HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async =>
      const StreamedHttpResponse(statusCode: 200, body: Stream.empty());

  @override
  void close() {}
}

class _RecordingConcurrencyObserver
    implements HttpObserver, ConcurrencyObserver {
  final events = <HttpConcurrencyWaitEvent>[];

  @override
  void onConcurrencyWait(HttpConcurrencyWaitEvent event) => events.add(event);
  @override
  void onRequest(HttpRequestEvent event) {}
  @override
  void onResponse(HttpResponseEvent event) {}
  @override
  void onError(HttpErrorEvent event) {}
  @override
  void onStreamStart(HttpStreamStartEvent event) {}
  @override
  void onStreamEnd(HttpStreamEndEvent event) {}
}

void main() {
  group('createAgentHttpClient', () {
    test('no args wraps a DartHttpClient in a ConcurrencyLimitingHttpClient',
        () {
      final client = createAgentHttpClient();
      addTearDown(client.close);
      expect(client, isA<ConcurrencyLimitingHttpClient>());
    });

    test('with innerClient wraps the provided client in the concurrency layer',
        () {
      final inner = _MockHttpClient();
      final client = createAgentHttpClient(innerClient: inner);
      expect(client, isA<ConcurrencyLimitingHttpClient>());
      expect(client, isNot(same(inner)));
    });

    test('with observers wraps in ObservableHttpClient and concurrency', () {
      final observer = _MockObserver();
      final client = createAgentHttpClient(observers: [observer]);
      addTearDown(client.close);
      // Outermost is the concurrency layer (observers are inside it).
      expect(client, isA<ConcurrencyLimitingHttpClient>());
    });

    test('with empty observers still wraps in ConcurrencyLimitingHttpClient',
        () {
      final client = createAgentHttpClient(observers: <HttpObserver>[]);
      addTearDown(client.close);
      expect(client, isA<ConcurrencyLimitingHttpClient>());
    });

    test('close cascades through decorator stack', () {
      final inner = _MockHttpClient();
      createAgentHttpClient(
        innerClient: inner,
        observers: [_MockObserver()],
      ).close();
      verify(inner.close).called(1);
    });

    test('enforces concurrency limit via ConcurrencyLimitingHttpClient layer',
        () async {
      final inner = _ConcurrencyTrackingInner();
      final client = createAgentHttpClient(
        innerClient: inner,
        maxConcurrent: 2,
      );

      final futures = [
        client.request('GET', Uri.parse('https://api/1')),
        client.request('GET', Uri.parse('https://api/2')),
        client.request('GET', Uri.parse('https://api/3')),
        client.request('GET', Uri.parse('https://api/4')),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        inner.maxInFlight,
        lessThanOrEqualTo(2),
        reason: 'maxConcurrent=2 must cap in-flight to 2',
      );

      inner.releaseAll();
      await Future.wait<void>(futures);
    });

    test(
        'routes ConcurrencyObserver entries in the observers list '
        'to the limiter', () async {
      final inner = _ConcurrencyTrackingInner();
      final observer = _RecordingConcurrencyObserver();
      final client = createAgentHttpClient(
        innerClient: inner,
        observers: [observer],
        maxConcurrent: 1,
      );

      final futures = [
        client.request('GET', Uri.parse('https://api/a')),
        client.request('GET', Uri.parse('https://api/b')),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 20));
      inner.releaseAll();
      await Future.wait<void>(futures);

      expect(observer.events.length, equals(2));
    });

    group('auth', () {
      test('with getToken wraps in AuthenticatedHttpClient', () {
        final client = createAgentHttpClient(getToken: () => 'token');
        addTearDown(client.close);
        expect(client, isA<AuthenticatedHttpClient>());
      });

      test('with getToken and observers applies both layers', () {
        final client = createAgentHttpClient(
          getToken: () => 'token',
          observers: [_MockObserver()],
        );
        addTearDown(client.close);
        // Outermost is AuthenticatedHttpClient
        expect(client, isA<AuthenticatedHttpClient>());
      });

      test('with tokenRefresher wraps in RefreshingHttpClient', () {
        final client = createAgentHttpClient(
          getToken: () => 'token',
          tokenRefresher: _MockTokenRefresher(),
        );
        addTearDown(client.close);
        expect(client, isA<RefreshingHttpClient>());
      });

      test('with all parameters composes full decorator stack', () {
        final client = createAgentHttpClient(
          observers: [_MockObserver()],
          getToken: () => 'token',
          tokenRefresher: _MockTokenRefresher(),
        );
        addTearDown(client.close);
        // Outermost is RefreshingHttpClient
        expect(client, isA<RefreshingHttpClient>());
      });

      test('tokenRefresher without getToken throws assertion', () {
        expect(
          () => createAgentHttpClient(tokenRefresher: _MockTokenRefresher()),
          throwsA(isA<AssertionError>()),
        );
      });

      test('close cascades through full auth stack', () {
        final inner = _MockHttpClient();
        createAgentHttpClient(
          innerClient: inner,
          observers: [_MockObserver()],
          getToken: () => 'token',
          tokenRefresher: _MockTokenRefresher(),
        ).close();
        verify(inner.close).called(1);
      });
    });
  });
}
