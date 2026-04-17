import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:test/test.dart';

/// Fake inner client that gates every response on a Completer so tests
/// can control request/response timing precisely.
class _GatedInner implements SoliplexHttpClient {
  final List<_PendingRequest> pending = [];
  int requestCallCount = 0;
  int streamCallCount = 0;

  _PendingRequest queueNextRequest() {
    final p = _PendingRequest();
    pending.add(p);
    return p;
  }

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    requestCallCount++;
    if (pending.isEmpty) {
      return HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));
    }
    return pending.removeAt(0).future;
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    streamCallCount++;
    return const StreamedHttpResponse(statusCode: 200, body: Stream.empty());
  }

  @override
  void close() {}
}

class _PendingRequest {
  final _completer = Completer<HttpResponse>();
  Future<HttpResponse> get future => _completer.future;

  void complete() => _completer.complete(
        HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
      );
  void fail(Object error) => _completer.completeError(error);
}

class _RecordingObserver implements ConcurrencyObserver {
  final events = <ConcurrencyWaitEvent>[];

  @override
  void onConcurrencyWait(ConcurrencyWaitEvent event) => events.add(event);
}

/// Observer that throws on every call. Verifies the decorator's
/// try-catch around observer dispatch prevents a broken observer from
/// crashing the request flow.
class _ThrowingObserver implements ConcurrencyObserver {
  int callCount = 0;

  @override
  void onConcurrencyWait(ConcurrencyWaitEvent event) {
    callCount++;
    throw Exception('observer is broken');
  }
}

/// Inner that returns a stream with a controllable body, so tests can
/// hold the body open and verify the slot is held for its lifetime.
class _StreamBodyInner implements SoliplexHttpClient {
  _StreamBodyInner(this._body);
  final Stream<List<int>> _body;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async =>
      HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async =>
      StreamedHttpResponse(statusCode: 200, body: _body);

  @override
  void close() {}
}

/// Inner that returns a fresh body per `requestStream` call. Real HTTP
/// clients return a new single-subscription stream per request; tests
/// that exercise multiple sequential requests need this shape.
class _FreshStreamBodyInner implements SoliplexHttpClient {
  _FreshStreamBodyInner(this._makeBody);
  final Stream<List<int>> Function() _makeBody;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async =>
      HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async =>
      StreamedHttpResponse(statusCode: 200, body: _makeBody());

  @override
  void close() {}
}

/// Inner that throws synchronously on request() when [throwOnNext] is true.
/// Verifies the decorator's try/finally releases the slot even when the
/// inner throws before returning a Future (as opposed to inside an awaited
/// future).
class _SyncThrowingInner implements SoliplexHttpClient {
  bool throwOnNext = true;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    if (throwOnNext) {
      throw const NetworkException(message: 'sync boom');
    }
    return Future.value(
      HttpResponse(statusCode: 200, bodyBytes: Uint8List(0)),
    );
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

/// Inner that throws from `requestStream` after the caller has acquired
/// a slot. Separate sync/async failure modes — the decorator's
/// `on Object { release; rethrow; }` block must handle both.
class _StreamThrowingInner implements SoliplexHttpClient {
  _StreamThrowingInner({this.synchronous = false});
  final bool synchronous;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async =>
      HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) {
    if (synchronous) {
      throw const NetworkException(message: 'stream sync boom');
    }
    return Future<StreamedHttpResponse>.error(
      const NetworkException(message: 'stream async boom'),
    );
  }

  @override
  void close() {}
}

/// Inner whose `requestStream` runs a scripted sequence of responses;
/// anything past the script delegates to [fallback] for `request`.
/// `request` always delegates to [fallback].
class _SequentialInner implements SoliplexHttpClient {
  _SequentialInner(this._streamScript, {required this.fallback});
  final List<Future<StreamedHttpResponse> Function()> _streamScript;
  final SoliplexHttpClient fallback;
  int _streamIndex = 0;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) =>
      fallback.request(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) {
    if (_streamIndex < _streamScript.length) {
      return _streamScript[_streamIndex++]();
    }
    return fallback.requestStream(
      method,
      uri,
      headers: headers,
      body: body,
      cancelToken: cancelToken,
    );
  }

  @override
  void close() => fallback.close();
}

/// Mutable clock for deterministic waitDuration assertions.
class _MockClock {
  DateTime now = DateTime(2026);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// Stream whose `listen` throws synchronously. Models a stream whose
/// subscription setup fails (e.g., a single-subscription stream already
/// listened elsewhere, which Dart's single-subscription contract
/// surfaces as a `StateError`).
class _ListenThrowingStream extends Stream<List<int>> {
  _ListenThrowingStream(this._error);
  final Error _error;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw _error;
  }
}

/// Inner whose stream body throws on `listen`.
class _ListenThrowingBodyInner implements SoliplexHttpClient {
  _ListenThrowingBodyInner(this._error);
  final Error _error;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async =>
      HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async =>
      StreamedHttpResponse(
        statusCode: 200,
        body: _ListenThrowingStream(_error),
      );

  @override
  void close() {}
}

void main() {
  group('ConcurrencyLimitingHttpClient.request', () {
    test('single request passes through immediately', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 2,
      );

      final response = await client.request(
        'GET',
        Uri.parse('https://x/y'),
      );

      expect(response.statusCode, 200);
      expect(inner.requestCallCount, 1);
    });

    test('caps in-flight requests at maxConcurrent', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 2,
      );

      final pending = [
        inner.queueNextRequest(),
        inner.queueNextRequest(),
        inner.queueNextRequest(),
      ];

      final futures = [
        client.request('GET', Uri.parse('https://x/1')),
        client.request('GET', Uri.parse('https://x/2')),
        client.request('GET', Uri.parse('https://x/3')),
      ];

      await Future<void>.delayed(Duration.zero);

      expect(
        inner.requestCallCount,
        2,
        reason: 'Third request must queue until a slot frees',
      );

      pending[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 3);

      pending[1].complete();
      pending[2].complete();
      await Future.wait<void>(futures);
    });

    test('queue is FIFO', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final acquiredOrder = <int>[];
      final pending = [
        inner.queueNextRequest(),
        inner.queueNextRequest(),
        inner.queueNextRequest(),
      ];

      final futures = [
        client.request('GET', Uri.parse('https://x/a')).then((_) {
          acquiredOrder.add(1);
        }),
        client.request('GET', Uri.parse('https://x/b')).then((_) {
          acquiredOrder.add(2);
        }),
        client.request('GET', Uri.parse('https://x/c')).then((_) {
          acquiredOrder.add(3);
        }),
      ];

      await Future<void>.delayed(Duration.zero);

      pending[0].complete();
      await Future<void>.delayed(Duration.zero);
      pending[1].complete();
      await Future<void>.delayed(Duration.zero);
      pending[2].complete();

      await Future.wait<void>(futures);

      expect(acquiredOrder, equals([1, 2, 3]));
    });

    test('releases slot after inner throws', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final first = inner.queueNextRequest();
      final second = inner.queueNextRequest();

      final firstFuture = client.request('GET', Uri.parse('https://x/1'));
      final secondFuture = client.request('GET', Uri.parse('https://x/2'));

      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 1);

      first.fail(const NetworkException(message: 'blip'));
      await expectLater(firstFuture, throwsA(isA<NetworkException>()));

      second.complete();
      await secondFuture;
      expect(inner.requestCallCount, 2);
    });

    test('releases slot when inner throws synchronously', () async {
      final inner = _SyncThrowingInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      await expectLater(
        () => client.request('GET', Uri.parse('https://x/1')),
        throwsA(isA<NetworkException>()),
      );

      inner.throwOnNext = false;
      final response = await client.request('GET', Uri.parse('https://x/2'));
      expect(response.statusCode, 200);
    });
  });

  group('ConcurrencyLimitingHttpClient observers', () {
    test('emits onConcurrencyWait with waitDuration=0 when not queued',
        () async {
      final inner = _GatedInner();
      final observer = _RecordingObserver();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 2,
        observers: [observer],
      );

      await client.request('GET', Uri.parse('https://x/y'));

      expect(observer.events.length, 1);
      final event = observer.events[0];
      expect(event.waitDuration, Duration.zero);
      expect(event.queueDepthAtEnqueue, 0);
      expect(event.slotsInUseAfterAcquire, 1);
      expect(event.uri.toString(), equals('https://x/y'));
    });

    test(
        'emits onConcurrencyWait with deterministic non-zero waitDuration '
        'when queued', () async {
      final inner = _GatedInner();
      final observer = _RecordingObserver();
      final clock = _MockClock();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
        observers: [observer],
        clock: clock.call,
      );

      final first = inner.queueNextRequest();
      final second = inner.queueNextRequest();

      final firstFuture = client.request('GET', Uri.parse('https://x/1'));
      final secondFuture = client.request('GET', Uri.parse('https://x/2'));

      await Future<void>.delayed(Duration.zero);

      clock.advance(const Duration(milliseconds: 50));

      first.complete();
      await firstFuture;
      second.complete();
      await secondFuture;

      expect(observer.events.length, 2);
      expect(observer.events[0].waitDuration, Duration.zero);
      expect(
        observer.events[1].waitDuration,
        equals(const Duration(milliseconds: 50)),
      );
      expect(observer.events[1].queueDepthAtEnqueue, 1);
    });

    test('swallows observer exceptions without breaking the request', () async {
      final inner = _GatedInner();
      final throwingObserver = _ThrowingObserver();
      final capturedMessages = <String>[];
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 2,
        observers: [throwingObserver],
        onDiagnostic: (_, __, {required message}) =>
            capturedMessages.add(message),
      );

      final response = await client.request(
        'GET',
        Uri.parse('https://x/y'),
      );

      expect(response.statusCode, 200);
      expect(throwingObserver.callCount, 1);
      expect(
        capturedMessages,
        hasLength(1),
        reason: 'onDiagnostic must surface the throwing-observer event so '
            'broken observers are visible in production logs',
      );
      expect(capturedMessages.single, contains('ConcurrencyObserver'));
    });

    test(
        'reports accurate queueDepth and slotsInUse for the third of three '
        'concurrent requests under maxConcurrent=2', () async {
      final inner = _GatedInner();
      final observer = _RecordingObserver();
      final clock = _MockClock();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 2,
        observers: [observer],
        clock: clock.call,
      );

      final first = inner.queueNextRequest();
      final second = inner.queueNextRequest();
      final third = inner.queueNextRequest();

      final f1 = client.request('GET', Uri.parse('https://x/1'));
      final f2 = client.request('GET', Uri.parse('https://x/2'));
      final f3 = client.request('GET', Uri.parse('https://x/3'));

      await Future<void>.delayed(Duration.zero);

      // First two acquire immediately; the third queues behind them.
      expect(inner.requestCallCount, 2);

      first.complete();
      await f1;
      // After first releases, third dispatches.
      second.complete();
      third.complete();
      await Future.wait<void>([f2, f3]);

      expect(observer.events, hasLength(3));
      final thirdEvent = observer.events[2];
      expect(
        thirdEvent.queueDepthAtEnqueue,
        2,
        reason: 'Two requests were already in the system when the third '
            'enqueued',
      );
      expect(
        thirdEvent.slotsInUseAfterAcquire,
        2,
        reason: 'Request 2 is still in-flight when request 3 acquires the '
            'freed slot, so both slots are now in use',
      );
    });

    test(
        'clamps negative waitDuration from clock skew and fires '
        'onDiagnostic', () async {
      final inner = _GatedInner();
      final observer = _RecordingObserver();
      final clock = _MockClock();
      final capturedMessages = <String>[];
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
        observers: [observer],
        clock: clock.call,
        onDiagnostic: (_, __, {required message}) =>
            capturedMessages.add(message),
      );

      // First request holds the single slot.
      final first = inner.queueNextRequest();
      final firstFuture = client.request('GET', Uri.parse('https://x/1'));
      await Future<void>.delayed(Duration.zero);

      // Second request queues; its enqueuedAt is recorded at the current
      // clock.
      final secondFuture = client.request('GET', Uri.parse('https://x/2'));
      await Future<void>.delayed(Duration.zero);

      // Clock rewinds (e.g. NTP correction) before the second acquires.
      clock.now = clock.now.subtract(const Duration(milliseconds: 100));

      first.complete();
      await firstFuture;
      await secondFuture;

      expect(observer.events, hasLength(2));
      expect(
        observer.events[1].waitDuration,
        Duration.zero,
        reason: '_nonNegative must clamp the backward-clock duration',
      );
      expect(
        capturedMessages,
        hasLength(1),
        reason: 'onDiagnostic must log the clock-skew clamp so rewinds '
            'are visible in diagnostics',
      );
      expect(capturedMessages.single, contains('Clock went backward'));
    });

    test(
        'permit accounting does not drift after many sequential bursts that '
        'exceed the cap — both immediate and queued-acquire paths are '
        'exercised so the waiter hand-off branch of _onSlotReleased is '
        'covered', () async {
      // Drift regression: an off-by-one in _onSlotReleased's
      // increment/hand-off would leak permits, erode the cap, and
      // eventually cause silent over-commitment. Each cycle queues
      // requests beyond the cap to exercise the hand-off branch.
      final inner = _GatedInner();
      final observer = _RecordingObserver();
      const cap = 2;
      const perCycle = 4;
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: cap,
        observers: [observer],
      );

      for (var cycle = 0; cycle < 50; cycle++) {
        final pendings =
            List.generate(perCycle, (_) => inner.queueNextRequest());
        final futures = List.generate(
          perCycle,
          (i) => client.request('GET', Uri.parse('https://x/$cycle/$i')),
        );
        await Future<void>.delayed(Duration.zero);
        // Complete in order — each completion hands the permit to the
        // next queued waiter via _onSlotReleased's waiter branch.
        for (final p in pendings) {
          p.complete();
          await Future<void>.delayed(Duration.zero);
        }
        await Future.wait(futures);
      }

      // After 200 acquisitions (100 of them via the queued branch), a
      // fresh request must acquire immediately with zero queue depth
      // and a single slot in use — proving no accumulated drift.
      final probePending = inner.queueNextRequest();
      final probeFuture = client.request('GET', Uri.parse('https://x/probe'));
      probePending.complete();
      await probeFuture;

      final last = observer.events.last;
      expect(
        last.queueDepthAtEnqueue,
        0,
        reason: 'Idle semaphore must report zero depth on probe acquire.',
      );
      expect(
        last.slotsInUseAfterAcquire,
        1,
        reason: 'Only the probe should be in flight — drift would push '
            'this above 1.',
      );
      expect(
        last.waitDuration,
        Duration.zero,
        reason: 'Probe must not queue against leaked permits.',
      );
    });

    test(
        'generates pairwise-distinct acquisitionIds even when many requests '
        'share the same clock timestamp — the counter suffix is the last '
        'line of defense against collisions', () async {
      // Frozen clock: every acquisitionId would share the same
      // millisecondsSinceEpoch component. Uniqueness must come from the
      // monotonic counter suffix. A future refactor that scopes the
      // counter to a per-millisecond epoch would silently collide here.
      final inner = _GatedInner();
      final observer = _RecordingObserver();
      final frozenClock = _MockClock();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 10,
        observers: [observer],
        clock: frozenClock.call,
      );

      const concurrent = 10;
      final pendings = List.generate(
        concurrent,
        (_) => inner.queueNextRequest(),
      );
      final futures = List.generate(
        concurrent,
        (i) => client.request('GET', Uri.parse('https://x/$i')),
      );

      // Clock does NOT advance. All acquisitions share the same
      // timestamp — counter alone must disambiguate.
      for (final p in pendings) {
        p.complete();
      }
      await Future.wait(futures);

      expect(observer.events, hasLength(concurrent));
      final ids = observer.events.map((e) => e.acquisitionId).toSet();
      expect(
        ids,
        hasLength(concurrent),
        reason: 'All $concurrent acquisitionIds must be distinct even under '
            'a frozen clock — the counter component carries the '
            'uniqueness guarantee.',
      );
    });

    test('continues notifying remaining observers after one throws', () async {
      final inner = _GatedInner();
      final throwingObserver = _ThrowingObserver();
      final recordingObserver = _RecordingObserver();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 2,
        observers: [throwingObserver, recordingObserver],
      );

      await client.request('GET', Uri.parse('https://x/y'));

      expect(throwingObserver.callCount, 1);
      expect(
        recordingObserver.events.length,
        1,
        reason: 'Second observer must receive the event',
      );
    });

    test(
        'request completes normally even when the diagnostic handler itself '
        'throws — failure must not propagate past the safety wrapper',
        () async {
      // A throwing observer forces the decorator to invoke _onDiagnostic.
      // The handler then throws, simulating a Sentry-style sink failing
      // transiently. safeDiagnosticHandler must swallow the failure.
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
        observers: [_ThrowingObserver()],
        onDiagnostic: (_, __, {required message}) {
          throw StateError('diagnostic sink down');
        },
      );

      await expectLater(
        client.request('GET', Uri.parse('https://x/y')),
        completes,
        reason: 'A broken diagnostic sink must not break request flow.',
      );
    });
  });

  group('ConcurrencyLimitingHttpClient.requestStream', () {
    test('holds slot until body stream closes, then releases', () async {
      final bodyController = StreamController<List<int>>();
      final inner = _StreamBodyInner(bodyController.stream);
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final response = await client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
      );
      expect(response.statusCode, 200);

      var secondStarted = false;
      final secondFuture =
          client.request('GET', Uri.parse('https://x/rest')).then((r) {
        secondStarted = true;
        return r;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        secondStarted,
        isFalse,
        reason: 'Slot held by stream; second request must wait',
      );

      final drainFuture = response.body.drain<void>();
      await bodyController.close();
      await drainFuture;

      await secondFuture;
      expect(secondStarted, isTrue);
    });

    test('releases slot when body stream errors', () async {
      final bodyController = StreamController<List<int>>();
      final inner = _StreamBodyInner(bodyController.stream);
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final response = await client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
      );

      final drainFuture = response.body.drain<void>().catchError((_) {});
      bodyController.addError(Exception('stream broke'));
      await bodyController.close();
      await drainFuture;

      final second = await client.request('GET', Uri.parse('https://x/rest'));
      expect(second.statusCode, 200);
    });

    test(
        'throws CancelledException and does not acquire when cancelled '
        'before acquire', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final cancelToken = CancelToken()..cancel('pre-emptive');

      await expectLater(
        () => client.requestStream(
          'GET',
          Uri.parse('https://x/stream'),
          cancelToken: cancelToken,
        ),
        throwsA(isA<CancelledException>()),
      );
      expect(inner.streamCallCount, 0);
    });

    test('queued stream cancel drops out of queue without acquiring', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final firstPending = inner.queueNextRequest();
      final firstFuture = client.request('GET', Uri.parse('https://x/first'));

      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 1);

      final cancelToken = CancelToken();
      final streamFuture = client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
        cancelToken: cancelToken,
      );
      await Future<void>.delayed(Duration.zero);

      cancelToken.cancel('navigated away');

      await expectLater(streamFuture, throwsA(isA<CancelledException>()));
      expect(inner.streamCallCount, 0);

      firstPending.complete();
      await firstFuture;
      expect(inner.streamCallCount, 0);
    });

    test(
        'cancel token shared across queued requests — cancelling after each '
        'has dispatched does not disrupt the dispatched requests, and the '
        'token still fails fast for a fresh acquire', () async {
      // Regression: queued requests subscribe to whenCancelled. Each
      // subscription must detach when its slot is acquired so a later
      // token.cancel() does not fire handlers for completed waiters
      // (and so closures do not accumulate for the token's lifetime).
      // The test queues two requests behind a held slot so the
      // subscription-attached branch in _Semaphore.acquire is exercised.
      final bodyControllers = <StreamController<List<int>>>[];
      final inner = _FreshStreamBodyInner(() {
        final c = StreamController<List<int>>();
        bodyControllers.add(c);
        return c.stream;
      });
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final token = CancelToken();

      // Fire all three concurrently. First takes the slot immediately
      // (no subscription created). The other two queue and register
      // cancel subscriptions.
      final responses = <StreamedHttpResponse?>[null, null, null];
      final dispatched = List.generate(
        3,
        (i) => client
            .requestStream(
              'GET',
              Uri.parse('https://x/$i'),
              cancelToken: token,
            )
            .then((r) => responses[i] = r),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        responses[0],
        isNotNull,
        reason: 'First request must acquire immediately.',
      );
      expect(
        responses[1],
        isNull,
        reason: 'Second request must be queued behind the held slot.',
      );
      expect(
        responses[2],
        isNull,
        reason: 'Third request must also be queued.',
      );

      // Release each slot in order — listen+close drains the body, so
      // the wrapper's onDone fires and the next waiter acquires
      // (detaching its cancel subscription via whenComplete).
      for (var i = 0; i < 3; i++) {
        while (responses[i] == null) {
          await Future<void>.delayed(Duration.zero);
        }
        responses[i]!.body.listen((_) {});
        await bodyControllers[i].close();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(dispatched);

      // All three dispatched and released. Cancelling now must not
      // fire any handler for the already-completed waiters.
      token.cancel('after all dispatched');

      // Fresh request with the same (now-cancelled) token must fail
      // fast at the pre-acquire check.
      await expectLater(
        client.requestStream(
          'GET',
          Uri.parse('https://x/4'),
          cancelToken: token,
        ),
        throwsA(isA<CancelledException>()),
      );
    });
  });

  group('ConcurrencyLimitingHttpClient mixed request/stream queue', () {
    test('FIFO applies across request and requestStream uniformly', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final dispatchOrder = <String>[];

      final firstPending = inner.queueNextRequest();
      final thirdPending = inner.queueNextRequest();

      final firstFuture = client
          .request('GET', Uri.parse('https://x/1'))
          .then((_) => dispatchOrder.add('request-1'));
      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 1);

      final streamFuture =
          client.requestStream('GET', Uri.parse('https://x/2')).then((r) {
        dispatchOrder.add('stream-2');
        return r;
      });
      final thirdFuture = client
          .request('GET', Uri.parse('https://x/3'))
          .then((_) => dispatchOrder.add('request-3'));
      await Future<void>.delayed(Duration.zero);

      expect(inner.requestCallCount, 1);
      expect(inner.streamCallCount, 0);

      firstPending.complete();
      await firstFuture;
      await Future<void>.delayed(Duration.zero);
      expect(inner.streamCallCount, 1);

      // The stream's body is Stream.empty() — draining it releases the slot.
      final streamResponse = await streamFuture;
      await streamResponse.body.drain<void>();
      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 2);

      thirdPending.complete();
      await thirdFuture;

      expect(
        dispatchOrder,
        equals(['request-1', 'stream-2', 'request-3']),
        reason: 'Mixed queue must dispatch in arrival order regardless of type',
      );
    });
  });

  group('ConcurrencyLimitingHttpClient slot lifecycle', () {
    test('releases slot when inner.requestStream throws asynchronously',
        () async {
      final inner = _StreamThrowingInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      await expectLater(
        () => client.requestStream('GET', Uri.parse('https://x/stream')),
        throwsA(isA<NetworkException>()),
      );

      // If the slot leaked, the next request would hang forever.
      final response = await client.request('GET', Uri.parse('https://x/ok'));
      expect(response.statusCode, 200);
    });

    test('releases slot when inner.requestStream throws synchronously',
        () async {
      final inner = _StreamThrowingInner(synchronous: true);
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      await expectLater(
        () => client.requestStream('GET', Uri.parse('https://x/stream')),
        throwsA(isA<NetworkException>()),
      );

      final response = await client.request('GET', Uri.parse('https://x/ok'));
      expect(response.statusCode, 200);
    });

    test(
        'cancelled middle waiter drops out of the queue; next live waiter '
        'dispatches when slot frees', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      // Hold the single slot with a non-completing request.
      final heldPending = inner.queueNextRequest();
      final heldFuture = client.request('GET', Uri.parse('https://x/held'));
      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 1);

      // Enqueue three stream requests behind the held slot.
      final cancelA = CancelToken();
      final cancelB = CancelToken();
      final cancelC = CancelToken();
      final streamA = client.requestStream(
        'GET',
        Uri.parse('https://x/a'),
        cancelToken: cancelA,
      );
      final streamB = client.requestStream(
        'GET',
        Uri.parse('https://x/b'),
        cancelToken: cancelB,
      );
      final streamC = client.requestStream(
        'GET',
        Uri.parse('https://x/c'),
        cancelToken: cancelC,
      );
      await Future<void>.delayed(Duration.zero);

      // Cancel the MIDDLE waiter. The cancel handler atomically removes
      // its completer from the queue, so when release() fires later it
      // must find A at the head (not B, not C).
      cancelB.cancel('removed');
      await expectLater(streamB, throwsA(isA<CancelledException>()));

      // Release the held slot. A is expected to dispatch; C remains
      // queued behind it.
      heldPending.complete();
      await heldFuture;
      await Future<void>.delayed(Duration.zero);

      expect(
        inner.streamCallCount,
        1,
        reason: 'A, not the cancelled B or the behind C, must dispatch',
      );

      // Clean up remaining waiters.
      cancelA.cancel('cleanup');
      cancelC.cancel('cleanup');
      // A already dispatched, its stream resolves normally; C was still
      // queued and throws.
      await expectLater(streamC, throwsA(isA<CancelledException>()));
      await streamA;
    });

    test('body that emits error then done releases the slot exactly once',
        () async {
      // An inner that serves one error-terminated body stream, then
      // delegates subsequent requests to a gated fake. If the body
      // wrapper over-released (two decrements, so effectively +1 slot),
      // the cap would rise from 1 to 2 and two gated requests would
      // dispatch concurrently. The regression signal is cap violation.
      final errorBody = StreamController<List<int>>();
      final gated = _GatedInner();
      final inner = _SequentialInner(
        [
          () async => StreamedHttpResponse(
                statusCode: 200,
                body: errorBody.stream,
              ),
        ],
        fallback: gated,
      );

      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final response = await client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
      );
      // Start draining before closing the source so the listener is
      // attached; otherwise close() blocks on no subscriber.
      final drained = response.body.drain<void>().catchError((_) {});
      errorBody.addError(Exception('boom'));
      await errorBody.close();
      await drained;

      // Slot should be back to 1 available. Fire two gated requests.
      final q1 = gated.queueNextRequest();
      gated.queueNextRequest(); // second one must queue
      final f1 = client.request('GET', Uri.parse('https://x/1'));
      final f2 = client.request('GET', Uri.parse('https://x/2'));
      await Future<void>.delayed(Duration.zero);

      expect(
        gated.requestCallCount,
        1,
        reason: 'Cap must remain 1 after body error+done — no double '
            'release into _available',
      );

      q1.complete();
      await f1;
      // The second queued request then dispatches; let it finish.
      gated.pending.first.complete();
      await f2;
    });

    test('cancelling the body subscription mid-flight releases the slot',
        () async {
      final body = StreamController<List<int>>();
      final client = ConcurrencyLimitingHttpClient(
        inner: _StreamBodyInner(body.stream),
        maxConcurrent: 1,
      );

      final response = await client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
      );
      final received = <List<int>>[];
      final sub = response.body.listen(received.add);

      body.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      // Cancel the subscription mid-flight. The body wrapper's
      // onCancel must release the slot.
      await sub.cancel();
      await body.close();

      // If the slot leaked, this next request would hang forever.
      final follow = await client.request('GET', Uri.parse('https://x/ok'));
      expect(follow.statusCode, 200);
    });

    test(
        'releases slot when body source.listen throws synchronously '
        '(e.g. single-subscription double-listen)', () async {
      final inner = _ListenThrowingBodyInner(
        StateError('stream has already been listened to'),
      );
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final response = await client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
      );

      // Listening triggers the wrapper's onListen, which calls
      // source.listen on the throwing stream. The decorator must
      // catch the synchronous throw, release the slot, and surface
      // the error through the wrapped controller.
      final errors = <Object>[];
      response.body.listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());

      // If the slot leaked, this request would hang forever.
      final follow = await client.request('GET', Uri.parse('https://x/ok'));
      expect(follow.statusCode, 200);
    });
  });

  group('maxConcurrent validation', () {
    test('throws RangeError when maxConcurrent is 0', () {
      expect(
        () => ConcurrencyLimitingHttpClient(
          inner: _GatedInner(),
          maxConcurrent: 0,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws RangeError when maxConcurrent is negative', () {
      expect(
        () => ConcurrencyLimitingHttpClient(
          inner: _GatedInner(),
          maxConcurrent: -1,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('accepts maxConcurrent of 1 (lowest valid value)', () {
      final client = ConcurrencyLimitingHttpClient(
        inner: _GatedInner(),
        maxConcurrent: 1,
      );
      expect(client.maxConcurrent, 1);
    });
  });

  group('close drains queued waiters', () {
    test('errors pending acquires with CancelledException', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      // First request holds the only slot.
      final first = inner.queueNextRequest();
      final firstFuture = client.request('GET', Uri.parse('https://x/1'));

      // Second queues.
      final secondFuture = client.request('GET', Uri.parse('https://x/2'));
      await Future<void>.delayed(Duration.zero);

      // Close before the slot is released.
      client.close();

      await expectLater(secondFuture, throwsA(isA<CancelledException>()));

      // Unblock the first so its future settles.
      first.complete();
      await firstFuture;
    });

    test('close is idempotent', () {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );
      expect(
        () => client
          ..close()
          ..close(),
        returnsNormally,
      );
    });

    test('acquire after close errors immediately', () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      )..close();

      await expectLater(
        client.request('GET', Uri.parse('https://x/after-close')),
        throwsA(isA<CancelledException>()),
      );
    });

    test(
        'close during an active stream body leaves the in-flight slot alone; '
        'the body drains normally and only post-close acquires fail', () async {
      // Documents the _Semaphore.closeAndDrain contract: "In-flight
      // slots are left alone — they release normally when their
      // requests complete." A regression here would either leak the
      // slot (no release on body completion) or abort the active
      // stream prematurely.
      final bodyController = StreamController<List<int>>();
      final inner = _StreamBodyInner(bodyController.stream);
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      final response = await client.requestStream(
        'GET',
        Uri.parse('https://x/stream'),
      );
      final chunks = <List<int>>[];
      final doneCompleter = Completer<void>();
      response.body.listen(
        chunks.add,
        onDone: doneCompleter.complete,
      );

      // Close while the body is actively streaming.
      bodyController.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      client.close();

      // Body must continue delivering until it completes naturally.
      bodyController.add([4, 5]);
      await bodyController.close();
      await doneCompleter.future;
      expect(
        chunks,
        equals([
          [1, 2, 3],
          [4, 5],
        ]),
      );

      // Any new acquire after close fails with CancelledException —
      // confirms the slot transition through close is consistent.
      await expectLater(
        client.request('GET', Uri.parse('https://x/after')),
        throwsA(isA<CancelledException>()),
      );
    });
  });

  group('post-acquire cancel (stream path)', () {
    test('cancel after acquire-but-before-sync-check releases the slot',
        () async {
      final inner = _GatedInner();
      final client = ConcurrencyLimitingHttpClient(
        inner: inner,
        maxConcurrent: 1,
      );

      // First request holds the only slot.
      final first = inner.queueNextRequest();
      final firstFuture = client.request('GET', Uri.parse('https://x/1'));
      await Future<void>.delayed(Duration.zero);

      // Second request queues with a cancel token.
      final token = CancelToken();
      final secondFuture = client.requestStream(
        'GET',
        Uri.parse('https://x/2'),
        cancelToken: token,
      );
      await Future<void>.delayed(Duration.zero);

      // Race: release the slot AND cancel the token synchronously. The
      // slot is acquired first (via release's removeFirst.complete), but
      // the post-acquire throwIfCancelled check sees the cancel and
      // throws — the catch block must release the slot.
      first.complete();
      token.cancel('test cancel');

      await expectLater(secondFuture, throwsA(isA<CancelledException>()));

      // Slot must be free: third request acquires.
      final third = inner.queueNextRequest();
      final thirdFuture = client.request('GET', Uri.parse('https://x/3'));
      await Future<void>.delayed(Duration.zero);
      expect(inner.requestCallCount, 2);
      third.complete();
      await thirdFuture;
      await firstFuture;
    });
  });

  group('unlistened-body leak handler (60s production)', () {
    test(
      'releases the slot after 60s so the cap recovers for later requests',
      () {
        fakeAsync((async) {
          // Fresh stream per call so the queued second request gets its
          // own subscription-capable body — real HTTP clients do the
          // same. Without the leak handler, the slot would be held
          // indefinitely and the second request would queue forever.
          final sources = <StreamController<List<int>>>[];
          final inner = _FreshStreamBodyInner(() {
            final c = StreamController<List<int>>();
            sources.add(c);
            return c.stream;
          });
          final captured = <String>[];
          final client = ConcurrencyLimitingHttpClient(
            inner: inner,
            maxConcurrent: 1,
            onDiagnostic: (_, __, {required message}) => captured.add(message),
          );

          // First request — caller never listens.
          unawaited(client.requestStream('GET', Uri.parse('https://x/y')));
          async.flushMicrotasks();

          // Second request — must queue because cap is 1.
          var secondAcquired = false;
          unawaited(
            client.requestStream('GET', Uri.parse('https://x/z')).then((resp) {
              secondAcquired = true;
              resp.body.listen((_) {});
            }),
          );
          async.flushMicrotasks();
          expect(
            secondAcquired,
            isFalse,
            reason: 'Second request must queue while first holds the slot.',
          );

          async.elapse(const Duration(seconds: 61));
          expect(
            captured,
            hasLength(1),
            reason: 'Force-drain must log exactly one diagnostic.',
          );
          expect(captured.single, contains('Unlistened body stream leak'));
          expect(
            secondAcquired,
            isTrue,
            reason: 'Cap must recover after force-drain so the queued '
                'request can dispatch.',
          );

          for (final c in sources) {
            c.close();
          }
          async.flushMicrotasks();
        });
      },
    );

    test(
      'late listener after 60s receives a StateError describing the timeout '
      'and the semaphore survives the double-release path',
      () {
        fakeAsync((async) {
          final source = StreamController<List<int>>();
          final inner = _StreamBodyInner(source.stream);
          final client = ConcurrencyLimitingHttpClient(
            inner: inner,
            maxConcurrent: 1,
            onDiagnostic: (_, __, {required message}) {},
          );

          StreamedHttpResponse? response;
          unawaited(
            client
                .requestStream('GET', Uri.parse('https://x/y'))
                .then((r) => response = r),
          );
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 61));

          final errors = <Object>[];
          var doneFired = false;
          response!.body.listen(
            (_) {},
            onError: errors.add,
            onDone: () => doneFired = true,
          );
          async.flushMicrotasks();

          expect(
            errors,
            hasLength(1),
            reason: 'Late listener must receive exactly one StateError '
                'so the failure is loud and self-describing.',
          );
          expect(errors.single, isA<StateError>());
          expect(
            (errors.single as StateError).message,
            contains('60s unlistened-body timeout'),
          );
          expect(
            doneFired,
            isTrue,
            reason: 'Stream must close after the error so the listener '
                'does not hang waiting for more data.',
          );

          // The timer and the late-listener branch both call
          // slot.release(); _SlotHandle.release is idempotent, but the
          // permit-conservation assert would fire if _available drifted.
          // Prove the semaphore is back to idle by acquiring a fresh
          // slot without queueing.
          var followUpAcquired = false;
          unawaited(
            client.request('GET', Uri.parse('https://x/follow-up')).then(
                  (_) => followUpAcquired = true,
                ),
          );
          async.flushMicrotasks();
          expect(
            followUpAcquired,
            isTrue,
            reason: 'Follow-up request must acquire immediately — a drift '
                'from the double-release path would make it queue.',
          );

          source.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'does not fire when the body is listened within 60s',
      () {
        fakeAsync((async) {
          final source = StreamController<List<int>>();
          final inner = _StreamBodyInner(source.stream);
          final captured = <String>[];
          final client = ConcurrencyLimitingHttpClient(
            inner: inner,
            maxConcurrent: 1,
            onDiagnostic: (_, __, {required message}) => captured.add(message),
          );

          unawaited(
            client
                .requestStream('GET', Uri.parse('https://x/y'))
                .then((resp) => resp.body.listen((_) {})),
          );
          async
            ..flushMicrotasks()
            // Elapse well past 60s — early listener must have cancelled
            // the timer. A regression here would spam the diagnostic
            // channel for every normal streaming request.
            ..elapse(const Duration(seconds: 120));
          expect(captured, isEmpty);

          source.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'drains the upstream source on timeout so the socket can close',
      () {
        fakeAsync((async) {
          var sourceWasListenedTo = false;
          final source = StreamController<List<int>>(
            onListen: () => sourceWasListenedTo = true,
          );
          final inner = _StreamBodyInner(source.stream);
          final client = ConcurrencyLimitingHttpClient(
            inner: inner,
            maxConcurrent: 1,
            onDiagnostic: (_, __, {required message}) {},
          );

          unawaited(client.requestStream('GET', Uri.parse('https://x/y')));
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 61));

          expect(
            sourceWasListenedTo,
            isTrue,
            reason: 'Force-drain must listen-then-cancel on the upstream '
                'source so the platform client tears down the socket.',
          );

          source.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}
