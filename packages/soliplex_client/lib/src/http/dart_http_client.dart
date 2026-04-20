import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:soliplex_client/src/errors/exceptions.dart';
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
  DartHttpClient({
    http.Client? client,
    this.defaultTimeout = defaultHttpTimeout,
  }) : _client = client ?? http.Client();

  final http.Client _client;

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
  }) async {
    _checkNotClosed();

    final effectiveTimeout = timeout ?? defaultTimeout;
    final request = _createRequest(method, uri, headers, body);

    try {
      final streamedResponse = await _client
          .send(request)
          .timeout(
            effectiveTimeout,
            onTimeout: () {
              throw TimeoutException(
                'Request timed out after ${effectiveTimeout.inSeconds}s',
                effectiveTimeout,
              );
            },
          );

      final bodyBytes = await streamedResponse.stream.toBytes().timeout(
        effectiveTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Response body timed out after ${effectiveTimeout.inSeconds}s',
            effectiveTimeout,
          );
        },
      );

      return HttpResponse(
        statusCode: streamedResponse.statusCode,
        bodyBytes: Uint8List.fromList(bodyBytes),
        headers: _normalizeHeaders(streamedResponse.headers),
        reasonPhrase: streamedResponse.reasonPhrase,
      );
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

    final request = _createRequest(method, uri, headers, body);

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
  http.Request _createRequest(
    String method,
    Uri uri,
    Map<String, String>? headers,
    Object? body,
  ) {
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
          'Use String, List<int>, or Map<String, dynamic>.',
        );
      }
    }

    return request;
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
