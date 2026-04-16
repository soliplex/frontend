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

class _CloseCounter implements SoliplexHttpClient {
  _CloseCounter(this._onClose);
  final void Function() _onClose;

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
      const StreamedHttpResponse(statusCode: 200, body: Stream.empty());

  @override
  void close() => _onClose();
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

  test('close delegates to inner', () {
    var closed = 0;
    final inner = _CloseCounter(() => closed++);
    ConcurrencyLimitingHttpClient(inner: inner, maxConcurrent: 1).close();
    expect(closed, 1);
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

  group('debug-only leak detector', () {
    test(
      'fires onDiagnostic after 10s when the response body is never listened',
      () {
        fakeAsync((async) {
          final inner = _StreamBodyInner(const Stream<List<int>>.empty());
          final captured = <String>[];
          final client = ConcurrencyLimitingHttpClient(
            inner: inner,
            maxConcurrent: 1,
            onDiagnostic: (_, __, {required message}) => captured.add(message),
          );

          unawaited(client.requestStream('GET', Uri.parse('https://x/y')));
          async
            ..flushMicrotasks()
            // Just before the 10s threshold — detector must not fire yet.
            ..elapse(const Duration(seconds: 9, milliseconds: 999));
          expect(captured, isEmpty);

          async.elapse(const Duration(milliseconds: 2));
          expect(
            captured,
            hasLength(1),
            reason: 'Detector must fire once after 10s when the body was '
                'never listened to, so caller bugs are visible in dev.',
          );
          expect(captured.single, contains('Unlistened body stream leak'));
        });
      },
    );

    test(
      'does not fire when the body is listened to within the threshold',
      () {
        fakeAsync((async) {
          final controller = StreamController<List<int>>();
          final inner = _StreamBodyInner(controller.stream);
          final captured = <String>[];
          final client = ConcurrencyLimitingHttpClient(
            inner: inner,
            maxConcurrent: 1,
            onDiagnostic: (_, __, {required message}) => captured.add(message),
          );

          unawaited(
            client.requestStream('GET', Uri.parse('https://x/y')).then((
              response,
            ) {
              // Listen immediately — the leak timer must be cancelled.
              response.body.listen((_) {});
            }),
          );
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 30));
          expect(
            captured,
            isEmpty,
            reason: 'Detector must be cancelled on listen — a caller who '
                'listens promptly must not trigger a false positive.',
          );

          controller.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}
