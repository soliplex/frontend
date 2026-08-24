import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_diagnostic.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';

/// Default HTTP client using `package:http`.
///
/// Works on all Dart platforms including web. Provides timeout handling,
/// automatic body encoding, and exception conversion.
///
/// Example:
/// ```dart
/// final client = DartHttpClient();
/// try {
///   final response = await client.request(
///     'POST',
///     Uri.parse('https://api.example.com/data'),
///     body: {'key': 'value'},
///     headers: {'Authorization': 'Bearer token'},
///   );
///   print(response.body);
/// } on NetworkException catch (e) {
///   print('Network error: ${e.message}');
/// } finally {
///   client.close();
/// }
/// ```
class DartHttpClient implements SoliplexHttpClient {
  /// Creates a Dart HTTP client.
  ///
  /// Parameters:
  /// - [client]: Optional [http.Client] to use. Creates a new one if not
  ///   provided.
  /// - [defaultTimeout]: Default timeout for requests.
  /// - [onDiagnostic]: Sink for internal errors the client contained
  ///   without failing the request. Defaults to `dart:developer`.
  DartHttpClient({
    http.Client? client,
    this.defaultTimeout = defaultHttpTimeout,
    HttpDiagnosticHandler? onDiagnostic,
  })  : _client = client ?? http.Client(),
        _onDiagnostic = safeDiagnosticHandler(
          onDiagnostic ?? defaultHttpDiagnosticHandler,
        );

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
  /// Wires [cancelToken] to inject an error into the request sink — the
  /// underlying socket aborts cleanly when the sink errors.
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
      throw StateError('Cannot use DartHttpClient after close() was called');
    }
  }
}
