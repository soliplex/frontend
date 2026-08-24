import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:soliplex_client/cancel_token.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;

/// HTTP client using Apple's NSURLSession via cupertino_http.
///
/// Provides native HTTP support on iOS and macOS with benefits including:
/// - Automatic proxy and VPN support
/// - HTTP/2 and HTTP/3 support
/// - System certificate trust evaluation
/// - Better battery efficiency
///
/// Example:
/// ```dart
/// final client = CupertinoHttpClient();
/// try {
///   final response = await client.request(
///     'GET',
///     Uri.parse('https://api.example.com/data'),
///   );
///   print(response.body);
/// } finally {
///   client.close();
/// }
/// ```
class CupertinoHttpClient implements SoliplexHttpClient {
  /// Creates a Cupertino HTTP client.
  ///
  /// Parameters:
  /// - [configuration]: Optional URLSessionConfiguration. If not provided,
  ///   an ephemeral configuration is created with [defaultTimeout] applied
  ///   to timeoutIntervalForRequest. When providing your own configuration,
  ///   you are responsible for its timeout settings.
  /// - [defaultTimeout]: Default timeout for requests.
  /// - [onDiagnostic]: Sink for internal errors the client contained
  ///   without failing the request. Defaults to `dart:developer`.
  CupertinoHttpClient({
    URLSessionConfiguration? configuration,
    this.defaultTimeout = defaultHttpTimeout,
    HttpDiagnosticHandler? onDiagnostic,
  })  : _client = CupertinoClient.fromSessionConfiguration(
          configuration ?? _createConfiguration(defaultTimeout),
        ),
        _onDiagnostic = safeDiagnosticHandler(
          onDiagnostic ?? defaultHttpDiagnosticHandler,
        );

  /// Creates a Cupertino HTTP client with a custom client for testing.
  ///
  /// This constructor allows injecting a mock client for unit testing.
  @visibleForTesting
  CupertinoHttpClient.forTesting({
    required http.Client client,
    this.defaultTimeout = defaultHttpTimeout,
    HttpDiagnosticHandler? onDiagnostic,
  })  : _client = client,
        _onDiagnostic = safeDiagnosticHandler(
          onDiagnostic ?? defaultHttpDiagnosticHandler,
        );

  /// Creates a URLSessionConfiguration with the given timeout.
  static URLSessionConfiguration _createConfiguration(Duration timeout) {
    return URLSessionConfiguration.ephemeralSessionConfiguration()
      ..timeoutIntervalForRequest = timeout;
  }

  final http.Client _client;
  final HttpDiagnosticHandler _onDiagnostic;

  /// Default timeout for requests when not specified per-request.
  final Duration defaultTimeout;

  bool _closed = false;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    _checkNotClosed();
    cancelToken?.throwIfCancelled();

    final effectiveTimeout = timeout ?? defaultTimeout;
    final request = _createRequest(method, uri, headers, body, cancelToken);

    try {
      final streamedResponse = await _client.send(request).timeout(
        effectiveTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Request timed out after ${effectiveTimeout.inSeconds}s',
            effectiveTimeout,
          );
        },
      );

      cancelToken?.throwIfCancelled();

      final bodyBytes = await streamedResponse.stream.toBytes().timeout(
        effectiveTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Response body timed out after ${effectiveTimeout.inSeconds}s',
            effectiveTimeout,
          );
        },
      );

      cancelToken?.throwIfCancelled();

      return HttpResponse(
        statusCode: streamedResponse.statusCode,
        bodyBytes: Uint8List.fromList(bodyBytes),
        headers: _normalizeHeaders(streamedResponse.headers),
        reasonPhrase: streamedResponse.reasonPhrase,
      );
    } on CancelledException {
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      throw NetworkException(
        message: e.message ?? 'Request timed out',
        isTimeout: true,
        originalError: e,
        stackTrace: stackTrace,
      );
    } on http.ClientException catch (e, stackTrace) {
      // Only a streamed body is wired to the token: `_pipeStreamToSink`
      // injects the cancellation into the request sink, and it crosses the
      // `NSInputStream` bridge as an `NSError`, so the [CancelledException]
      // identity is gone by the time it lands here. Reporting a network
      // failure for an upload the caller cancelled is what makes
      // `UploadTracker` show a cancelled row as failed.
      //
      // Buffered bodies are never wired, so a client error there is a real
      // failure even when some other request sharing the token was
      // cancelled; those keep reporting as network failures.
      if (body is Stream<List<int>> && (cancelToken?.isCancelled ?? false)) {
        _onDiagnostic(
          e,
          stackTrace,
          message: 'Client error on a cancelled streamed upload; '
              'reporting the cancellation instead',
        );
        cancelToken!.throwIfCancelled();
      }
      throw NetworkException(
        message: 'Client error: ${e.message}',
        originalError: e,
        stackTrace: stackTrace,
      );
    } on Exception catch (e, stackTrace) {
      // Generic fallback for platform-specific exceptions
      throw NetworkException(
        message: 'Network error: $e',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    _checkNotClosed();
    cancelToken?.throwIfCancelled();

    final request = _createRequest(method, uri, headers, body, cancelToken);

    try {
      final streamedResponse = await _client.send(request);

      try {
        cancelToken?.throwIfCancelled();
      } on CancelledException {
        // Drain the stream to release the underlying TCP socket.
        unawaited(streamedResponse.stream.listen((_) {}).cancel());
        rethrow;
      }

      return StreamedHttpResponse(
        statusCode: streamedResponse.statusCode,
        headers: _normalizeHeaders(streamedResponse.headers),
        reasonPhrase: streamedResponse.reasonPhrase,
        body: streamedResponse.stream.handleError((
          Object error,
          StackTrace stackTrace,
        ) {
          throw NetworkException(
            message: 'Stream error: $error',
            originalError: error,
            stackTrace: stackTrace,
          );
        }),
      );
    } on CancelledException {
      rethrow;
    } on http.ClientException catch (e, stackTrace) {
      // Only a streamed body is wired to the token: `_pipeStreamToSink`
      // injects the cancellation into the request sink, and it crosses the
      // `NSInputStream` bridge as an `NSError`, so the [CancelledException]
      // identity is gone by the time it lands here. Reporting a network
      // failure for an upload the caller cancelled is what makes
      // `UploadTracker` show a cancelled row as failed.
      //
      // Buffered bodies are never wired, so a client error there is a real
      // failure even when some other request sharing the token was
      // cancelled; those keep reporting as network failures.
      if (body is Stream<List<int>> && (cancelToken?.isCancelled ?? false)) {
        _onDiagnostic(
          e,
          stackTrace,
          message: 'Client error on a cancelled streamed upload; '
              'reporting the cancellation instead',
        );
        cancelToken!.throwIfCancelled();
      }
      throw NetworkException(
        message: 'Client error: ${e.message}',
        originalError: e,
        stackTrace: stackTrace,
      );
    } on Exception catch (e, stackTrace) {
      throw NetworkException(
        message: 'Connection failed: $e',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void close() {
    if (!_closed) {
      _closed = true;
      _client.close();
    }
  }

  /// Creates an HTTP request with the given parameters.
  ///
  /// Returns [http.StreamedRequest] for `Stream<List<int>>` bodies — used
  /// for streamed uploads with an exact `Content-Length`. Returns
  /// [http.Request] (buffered) for all other supported body types.
  http.BaseRequest _createRequest(
    String method,
    Uri uri,
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  ) {
    if (body is Stream<List<int>>) {
      return _createStreamedRequest(method, uri, headers, body, cancelToken);
    }

    final request = http.Request(method.toUpperCase(), uri);

    if (headers != null) {
      request.headers.addAll(headers);
    }

    if (body != null) {
      if (body is String) {
        // Set content-type before body to prevent http package from overriding
        request.headers['content-type'] ??= 'text/plain; charset=utf-8';
        request.body = body;
      } else if (body is List<int>) {
        request.headers['content-type'] ??= 'application/octet-stream';
        request.bodyBytes = body;
      } else if (body is Map<String, dynamic>) {
        // Set content-type before body to prevent http package from overriding
        request.headers['content-type'] ??= 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      } else {
        throw ArgumentError(
          'Unsupported body type: ${body.runtimeType}. '
          'Use String, List<int>, Map<String, dynamic>, or Stream<List<int>>.',
        );
      }
    }

    return request;
  }

  /// Builds a [http.StreamedRequest] from a `Stream<List<int>>` body.
  ///
  /// Reads `content-length` from [headers] (case-insensitive) to set
  /// `request.contentLength` so the wire uses an exact `Content-Length`
  /// header rather than `Transfer-Encoding: chunked`. Callers MUST supply
  /// content-length for streamed bodies.
  ///
  /// Wires [cancelToken] to inject an error into the request sink —
  /// `cupertino_http`'s `NSURLSessionTask` aborts cleanly on sink error.
  http.StreamedRequest _createStreamedRequest(
    String method,
    Uri uri,
    Map<String, String>? headers,
    Stream<List<int>> body,
    CancelToken? cancelToken,
  ) {
    final request = http.StreamedRequest(method.toUpperCase(), uri);

    if (headers != null) {
      request.headers.addAll(headers);
    }

    final contentLength = _findHeader(headers, 'content-length');
    if (contentLength != null) {
      request.contentLength = int.parse(contentLength);
    }
    request.headers['content-type'] ??= 'application/octet-stream';

    _pipeStreamToSink(body, request.sink, cancelToken);
    return request;
  }

  /// Pipes [source] chunks into [sink], honoring [cancelToken] by injecting
  /// a [CancelledException] into the sink. The underlying client treats a
  /// sink error as an abrupt connection abort.
  void _pipeStreamToSink(
    Stream<List<int>> source,
    EventSink<List<int>> sink,
    CancelToken? cancelToken,
  ) {
    StreamSubscription<void>? cancelSub;
    var closed = false;

    void closeSink() {
      if (closed) return;
      closed = true;
      sink.close();
    }

    final subscription = source.listen(
      sink.add,
      onError: (Object error, StackTrace stack) {
        if (closed) return;
        sink.addError(error, stack);
        closeSink();
      },
      onDone: () {
        cancelSub?.cancel();
        closeSink();
      },
    );

    if (cancelToken != null) {
      cancelSub = cancelToken.whenCancelled.asStream().listen((_) {
        if (closed) return;
        sink.addError(CancelledException(reason: cancelToken.reason));
        closeSink();
        // A body stream that is an `async*` generator can raise while it
        // unwinds, and Dart reports that through the future returned by
        // `cancel()` rather than through `onError`. Discarding the future
        // lets it reach the zone as an unhandled error.
        //
        // A [CancelledException] here is the body reacting to the same
        // token, a second route for an event the caller already has: the
        // sink error above makes their request future complete with one.
        // Deliberate silence. Anything else is a real body failure — a file
        // read that broke as the socket closed — and this is its only
        // record, because that future carries the cancellation instead.
        unawaited(
          subscription.cancel().catchError((Object e, StackTrace st) {
            if (e is CancelledException) return;
            _onDiagnostic(
              e,
              st,
              message: 'Request body teardown failed after cancel',
            );
          }),
        );
      });
    }
  }

  /// Case-insensitive header lookup.
  String? _findHeader(Map<String, String>? headers, String name) {
    if (headers == null) return null;
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// Normalizes headers by converting keys to lowercase.
  Map<String, String> _normalizeHeaders(Map<String, String> headers) {
    return headers.map((key, value) => MapEntry(key.toLowerCase(), value));
  }

  /// Checks that the client has not been closed.
  void _checkNotClosed() {
    if (_closed) {
      throw StateError(
        'Cannot use CupertinoHttpClient after close() was called',
      );
    }
  }
}
