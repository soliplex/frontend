import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show ConcurrencyLimitingHttpClient;
import 'package:test/test.dart';

/// Pumps the microtask queue repeatedly so all scheduled awaits through
/// the decorator stack settle. Deterministic alternative to wall-clock
/// `Duration(milliseconds: N)` waits.
Future<void> _pumpEventQueue([int iterations = 20]) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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
  }) async => const StreamedHttpResponse(statusCode: 200, body: Stream.empty());

  @override
  void close() {}
}

class _RecordingConcurrencyObserver
    implements HttpObserver, ConcurrencyObserver {
  final events = <ConcurrencyWaitEvent>[];

  @override
  void onConcurrencyWait(ConcurrencyWaitEvent event) => events.add(event);
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

class _ThrowingConcurrencyObserver
    implements HttpObserver, ConcurrencyObserver {
  @override
  void onConcurrencyWait(ConcurrencyWaitEvent event) {
    throw StateError('observer is broken');
  }

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

class _ThrowingHttpObserver implements HttpObserver {
  @override
  void onRequest(HttpRequestEvent event) {
    throw StateError('http observer is broken');
  }

  @override
  void onResponse(HttpResponseEvent event) {}
  @override
  void onError(HttpErrorEvent event) {}
  @override
  void onStreamStart(HttpStreamStartEvent event) {}
  @override
  void onStreamEnd(HttpStreamEndEvent event) {}
}

/// Inner client that records request order and returns 401 on the
/// first call whose URI matches [uri401], then 200 for all subsequent
/// requests (including the retry for the 401'd URI).
class _OrderedInner implements SoliplexHttpClient {
  _OrderedInner({required this.uri401});

  final Uri uri401;
  final List<String> executionOrder = [];
  bool _saw401 = false;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    executionOrder.add(uri.path);
    if (uri == uri401 && !_saw401) {
      _saw401 = true;
      return HttpResponse(statusCode: 401, bodyBytes: Uint8List(0));
    }
    return HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async => const StreamedHttpResponse(statusCode: 200, body: Stream.empty());

  @override
  void close() {}
}

/// TokenRefresher that performs its refresh by issuing an HTTP request
/// through [client]. Simulates the `TokenRefreshService(httpClient:
/// plainClient)` wiring in `standard.dart` — the refresher client MUST
/// be separate from the authed client, or the refresh deadlocks when
/// the authed client's pool is exhausted.
class _RefresherViaClient implements TokenRefresher {
  _RefresherViaClient(this.client);

  final SoliplexHttpClient client;
  int refreshCalls = 0;

  @override
  bool get needsRefresh => false;

  @override
  Future<void> refreshIfExpiringSoon() async {
    // Proactive refresh no-op: the tests care about reactive-refresh
    // behavior via tryRefresh, not proactive.
  }

  @override
  Future<bool> tryRefresh() async {
    refreshCalls++;
    await client.request('POST', Uri.parse('https://auth.example/refresh'));
    return true;
  }
}

void main() {
  group('createAgentHttpClient', () {
    test('always returns ConcurrencyLimitingHttpClient as the outermost '
        'decorator across all input combinations', () {
      final cases = <String, SoliplexHttpClient Function()>{
        'no args': createAgentHttpClient,
        'with innerClient':
            () => createAgentHttpClient(innerClient: _MockHttpClient()),
        'with observers':
            () => createAgentHttpClient(observers: [_MockObserver()]),
        'with empty observers':
            () => createAgentHttpClient(observers: <HttpObserver>[]),
        'with getToken': () => createAgentHttpClient(getToken: () => 'token'),
        'with getToken and observers':
            () => createAgentHttpClient(
              getToken: () => 'token',
              observers: [_MockObserver()],
            ),
        'with getToken and tokenRefresher':
            () => createAgentHttpClient(
              getToken: () => 'token',
              tokenRefresher: _MockTokenRefresher(),
            ),
        'with all parameters':
            () => createAgentHttpClient(
              observers: [_MockObserver()],
              getToken: () => 'token',
              tokenRefresher: _MockTokenRefresher(),
            ),
      };
      for (final entry in cases.entries) {
        final client = entry.value();
        addTearDown(client.close);
        expect(
          client,
          isA<ConcurrencyLimitingHttpClient>(),
          reason:
              '${entry.key}: concurrency limiter must be outermost so '
              'auth runs at dispatch, not enqueue',
        );
      }
    });

    test('close cascades through decorator stack', () {
      final inner = _MockHttpClient();
      createAgentHttpClient(
        innerClient: inner,
        observers: [_MockObserver()],
      ).close();
      verify(inner.close).called(1);
    });

    test(
      'enforces concurrency limit via ConcurrencyLimitingHttpClient layer',
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

        await _pumpEventQueue();

        expect(
          inner.maxInFlight,
          lessThanOrEqualTo(2),
          reason: 'maxConcurrent=2 must cap in-flight to 2',
        );

        inner.releaseAll();
        await Future.wait<void>(futures);
      },
    );

    test('default maxConcurrent caps in-flight at 6', () async {
      final inner = _ConcurrencyTrackingInner();
      final client = createAgentHttpClient(innerClient: inner);

      final futures = List.generate(
        15,
        (i) => client.request('GET', Uri.parse('https://api/$i')),
      );

      await _pumpEventQueue();

      expect(
        inner.maxInFlight,
        equals(6),
        reason:
            'default cap matches the HTTP/1.1 per-host cap shared by '
            'browsers, URLSession, and Dart HttpClient; keeps this layer '
            'authoritative and sits under the backend per-client 10-cap',
      );

      inner.releaseAll();
      await Future.wait<void>(futures);
    });

    test('decorator order: concurrency wraps auth '
        '(getToken fires at dispatch, not enqueue)', () async {
      final inner = _ConcurrencyTrackingInner();
      var getTokenCalls = 0;
      final client = createAgentHttpClient(
        innerClient: inner,
        maxConcurrent: 1,
        getToken: () {
          getTokenCalls++;
          return 'token-$getTokenCalls';
        },
      );

      final futures = [
        client.request('GET', Uri.parse('https://api/1')),
        client.request('GET', Uri.parse('https://api/2')),
        client.request('GET', Uri.parse('https://api/3')),
      ];

      await _pumpEventQueue();

      // Pins the decorator order. ConcurrencyLimitingHttpClient is the
      // outermost decorator, so getToken fires per dispatch (after a
      // slot is acquired), not per enqueue. With only 1 slot, only 1
      // request has reached the auth layer; the other 2 are still
      // queued in the concurrency layer and have NOT called getToken.
      //
      // If this assertion ever flips to 3, the decorator order was
      // reversed — tokens would be fetched at enqueue and could go
      // stale during queue wait, silently breaking streams (which
      // cannot be retried on 401).
      expect(inner.maxInFlight, 1);
      expect(
        getTokenCalls,
        1,
        reason:
            'concurrency wraps auth: only the dispatched request '
            'has hit the auth layer so far',
      );

      inner.releaseAll();
      await Future.wait<void>(futures);
      expect(
        getTokenCalls,
        3,
        reason:
            'after all 3 requests dequeue and dispatch, each should '
            'have called getToken exactly once',
      );
    });

    test('routes ConcurrencyObserver entries in the observers list '
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

      await _pumpEventQueue();
      inner.releaseAll();
      await Future.wait<void>(futures);

      expect(observer.events.length, equals(2));
    });

    group('auth', () {
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

    group('diagnostic plumbing', () {
      test('onDiagnostic fires when a concurrency observer throws', () async {
        final inner = _ConcurrencyTrackingInner();
        final captured = <String>[];
        final client = createAgentHttpClient(
          innerClient: inner,
          observers: [_ThrowingConcurrencyObserver()],
          onDiagnostic: (_, __, {required message}) => captured.add(message),
        );

        final future = client.request('GET', Uri.parse('https://api/x'));
        inner.releaseAll();
        await future;

        expect(
          captured,
          hasLength(1),
          reason:
              'onDiagnostic must be invoked by the limiter when a '
              'ConcurrencyObserver throws',
        );
        expect(captured.single, contains('ConcurrencyObserver'));
      });

      test('onDiagnostic fires when an HttpObserver throws', () async {
        final inner = _ConcurrencyTrackingInner();
        final captured = <String>[];
        final client = createAgentHttpClient(
          innerClient: inner,
          observers: [_ThrowingHttpObserver()],
          onDiagnostic: (_, __, {required message}) => captured.add(message),
        );

        final future = client.request('GET', Uri.parse('https://api/x'));
        inner.releaseAll();
        await future;

        expect(
          captured.any((m) => m.contains('_ThrowingHttpObserver')),
          isTrue,
          reason:
              'onDiagnostic must be invoked by the observable layer '
              'when an HttpObserver throws',
        );
      });
    });

    group('decorator composition invariants', () {
      test(
        'refresh via a separate client does not deadlock when the authed '
        "client's pool is exhausted",
        () async {
          // `standard.dart` creates per-server authed clients via
          // createAgentHttpClient and a refresh-service client via a
          // separate createAgentHttpClient call. Each call returns a
          // client with its OWN limiter — the refresher does not
          // contend for the authed client's slot.
          //
          // If a future refactor hoists the limiter to a shared
          // instance, the refresh path (triggered by 401) would try to
          // acquire a slot from the same pool the authed request is
          // holding → deadlock. This test would then hang and time
          // out, which is precisely the signal we want.
          final refresherInner = _OrderedInner(
            uri401: Uri.parse('https://never.fires'),
          );
          final plainClient = createAgentHttpClient(
            innerClient: refresherInner,
            maxConcurrent: 1,
          );
          addTearDown(plainClient.close);

          final authedInner = _OrderedInner(
            uri401: Uri.parse('https://api/work'),
          );
          final refresher = _RefresherViaClient(plainClient);
          final authedClient = createAgentHttpClient(
            innerClient: authedInner,
            maxConcurrent: 1,
            getToken: () => 'token',
            tokenRefresher: refresher,
          );
          addTearDown(authedClient.close);

          final response = await authedClient
              .request('GET', Uri.parse('https://api/work'))
              .timeout(
                const Duration(seconds: 2),
                onTimeout:
                    () =>
                        throw TimeoutException(
                          'refresh deadlocked — the refresher is contending for '
                          "the authed client's concurrency slot. The decorator "
                          'factory must mint an independent limiter per call; '
                          'if you refactored to share limiters across clients, '
                          'that change re-introduces the original 429 deadlock.',
                        ),
              );

          expect(response.statusCode, 200);
          expect(refresher.refreshCalls, 1);
        },
      );

      test(
        'decorator order: concurrency wraps refreshing '
        '(401 retries do not release and reacquire concurrency slots)',
        () async {
          // A single client with maxConcurrent: 1. Request A is served
          // 401 on first attempt, then 200 on the retry inside the
          // refresh path. Request B is fired concurrently.
          //
          // Correct order (Concurrency wraps Refreshing): A holds the
          // slot across its 401 → refresh → retry, so B waits the
          // entire time. Execution order at the inner is [A, A, B].
          //
          // Broken order (Refreshing wraps Concurrency): A's 401 would
          // release the slot, B would grab it, and A's retry would
          // queue behind B. Execution order becomes [A, B, A]. Failing
          // this test is the signal that the decorator stack was
          // reordered and the docstring claim about slot continuity no
          // longer holds.
          final refresherInner = _OrderedInner(
            uri401: Uri.parse('https://never.fires'),
          );
          final plainClient = createAgentHttpClient(
            innerClient: refresherInner,
            maxConcurrent: 2,
          );
          addTearDown(plainClient.close);

          final authedInner = _OrderedInner(
            uri401: Uri.parse('https://api/A'),
          );
          final authedClient = createAgentHttpClient(
            innerClient: authedInner,
            maxConcurrent: 1,
            getToken: () => 'token',
            tokenRefresher: _RefresherViaClient(plainClient),
          );
          addTearDown(authedClient.close);

          final futures = [
            authedClient.request('GET', Uri.parse('https://api/A')),
            authedClient.request('GET', Uri.parse('https://api/B')),
          ];

          await Future.wait<HttpResponse>(futures);

          expect(
            authedInner.executionOrder,
            equals(['/A', '/A', '/B']),
            reason:
                'concurrency wraps refreshing: A must hold its slot '
                'through the 401 + retry before B can dispatch',
          );
        },
      );
    });
  });
}
