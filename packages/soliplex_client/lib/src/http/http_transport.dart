import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/request_timeouts.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.http_transport');

const _errorBodyLimit = 4096;
const _errorBodyWait = Duration(seconds: 2);
const _reasonLimit = 200;

/// A `Bearer`/`Basic` token of 16 or more characters, or a JWT: what an
/// intermediary echoing the `Authorization` header would put in a reason.
/// The length floor lets a reason that only names one ("Missing Bearer
/// token") keep its words. An opaque token, API key or cookie is not caught.
final _credential = RegExp(
  r'\b(?:Bearer|Basic)\s+[\w\-.~+/]{16,}=*|\beyJ[\w-]+\.[\w-]+(?:\.[\w-]*)?',
  caseSensitive: false,
);

/// HTTP transport layer with JSON serialization and exception mapping.
///
/// Wraps a [SoliplexHttpClient] and provides:
/// - Automatic JSON encoding/decoding for request and response bodies
/// - HTTP status code to exception mapping
/// - Request cancellation via [CancelToken]
/// - Configurable timeout with per-request override
///
/// Example:
/// ```dart
/// final transport = HttpTransport(client: DartHttpClient());
///
/// // Simple GET request
/// final data = await transport.request<Map<String, dynamic>>(
///   'GET',
///   Uri.parse('https://api.example.com/rooms'),
/// );
///
/// // POST with JSON body
/// final response = await transport.request(
///   'POST',
///   Uri.parse('https://api.example.com/rooms'),
///   body: {'name': 'New Room'},
/// );
///
/// // With cancellation
/// final token = CancelToken();
/// final future = transport.request('GET', uri, cancelToken: token);
/// token.cancel();  // Throws CancelledException
///
/// transport.close();
/// ```
class HttpTransport {
  /// Creates an HTTP transport with the given [client].
  ///
  /// Parameters:
  /// - [client]: The underlying HTTP client to use for requests
  /// - [defaultTimeout]: Default timeout for requests
  HttpTransport({
    required SoliplexHttpClient client,
    this.defaultTimeout = defaultHttpTimeout,
  }) : _client = client;

  final SoliplexHttpClient _client;

  /// Default timeout applied to requests when no per-request timeout is given.
  final Duration defaultTimeout;

  /// Performs an HTTP request and returns the decoded response.
  ///
  /// Parameters:
  /// - [method]: HTTP method (GET, POST, PUT, DELETE, PATCH, etc.)
  /// - [uri]: The request URI
  /// - [body]: Optional request body. Maps are JSON encoded automatically.
  /// - [headers]: Optional request headers. Content-Type is set to JSON
  ///   when body is a Map.
  /// - [timeout]: Request timeout. Uses [defaultTimeout] if not specified.
  /// - [cancelToken]: Optional token for cancelling the request.
  /// - [fromJson]: Optional function to convert the JSON response to type [T].
  ///   If null and response is JSON, returns the decoded Map.
  ///
  /// Returns:
  /// - The decoded response body. If [fromJson] is provided, returns [T].
  /// - If response body is empty, returns null cast to [T].
  /// - If response is not JSON, returns the raw string cast to [T].
  ///
  /// Throws:
  /// - [CancelledException] if the request was cancelled via [cancelToken]
  /// - [AuthException] for 401 responses
  /// - [PermissionDeniedException] for 403 responses
  /// - [NotFoundException] for 404 responses
  /// - [ApiException] for any other non-2xx response
  /// - [NetworkException] for connection failures (from client)
  Future<T> request<T>(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
    CancelToken? cancelToken,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    // Check cancellation before starting
    cancelToken?.throwIfCancelled();

    // Prepare headers and body
    final requestHeaders = <String, String>{...?headers};
    var requestBody = body;

    // JSON encode Map bodies
    if (body is Map<String, dynamic>) {
      requestBody = jsonEncode(body);
      requestHeaders['content-type'] ??= 'application/json';
    }

    // Make the request
    final response = await _client.request(
      method,
      uri,
      headers: requestHeaders,
      body: requestBody,
      timeout: timeout ?? defaultTimeout,
      cancelToken: cancelToken,
    );

    // Check cancellation after request completes
    cancelToken?.throwIfCancelled();

    // Map status codes to exceptions
    _throwForStatusCode(response, uri);

    // Decode response
    return _decodeResponse<T>(response, fromJson);
  }

  /// Performs an HTTP request and returns the raw response bytes.
  ///
  /// Use this for binary downloads (images, file contents, archives) where
  /// JSON decoding would corrupt the payload. Status-to-exception mapping
  /// is identical to [request]. Buffers the entire response in memory; for
  /// large payloads, use [requestStream] instead.
  ///
  /// Parameters:
  /// - [method]: HTTP method (typically GET).
  /// - [uri]: The request URI.
  /// - [headers]: Optional request headers.
  /// - [timeout]: Request timeout. Uses [defaultTimeout] if not specified.
  /// - [cancelToken]: Optional token for cancelling the request.
  ///
  /// Throws:
  /// - [CancelledException] if the request was cancelled via [cancelToken]
  /// - [AuthException] for 401 responses
  /// - [PermissionDeniedException] for 403 responses
  /// - [NotFoundException] for 404 responses
  /// - [ApiException] for any other non-2xx response
  /// - [NetworkException] for connection failures (from client)
  Future<Uint8List> requestBytes(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final response = await _client.request(
      method,
      uri,
      headers: {...?headers},
      timeout: timeout ?? defaultTimeout,
      cancelToken: cancelToken,
    );

    cancelToken?.throwIfCancelled();

    _throwForStatusCode(response, uri);

    return response.bodyBytes;
  }

  /// Performs a streaming HTTP request and returns a [StreamedHttpResponse].
  ///
  /// Used for SSE (Server-Sent Events) and other streaming protocols.
  /// The returned [StreamedHttpResponse] contains the HTTP status code and
  /// headers, plus a body stream that emits byte chunks.
  ///
  /// Parameters:
  /// - [method]: HTTP method (typically GET or POST)
  /// - [uri]: The request URI
  /// - [body]: Optional request body. Maps are JSON encoded automatically.
  /// - [headers]: Optional request headers
  /// - [cancelToken]: Optional token for cancelling the stream
  ///
  /// A refused stream's body is read (at most 4096 bytes, for at most 2
  /// seconds) for the server's reason before throwing.
  ///
  /// Throws:
  /// - [CancelledException] if cancelled before the stream starts, including
  ///   while a refused stream's error body is read
  /// - [NetworkException] for connection failures (from client)
  /// - [AuthException] for 401 on stream setup
  /// - [PermissionDeniedException] for 403 on stream setup
  /// - [NotFoundException] for 404 on stream setup
  /// - [ApiException] for any other non-2xx on stream setup
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    // Check cancellation before starting
    cancelToken?.throwIfCancelled();

    // Prepare headers and body
    final requestHeaders = <String, String>{...?headers};
    var requestBody = body;

    // JSON encode Map bodies
    if (body is Map<String, dynamic>) {
      requestBody = jsonEncode(body);
      requestHeaders['content-type'] ??= 'application/json';
    }

    final response = await _client.requestStream(
      method,
      uri,
      headers: requestHeaders,
      body: requestBody,
      cancelToken: cancelToken,
    );

    try {
      // Check cancellation after connection established
      cancelToken?.throwIfCancelled();
    } catch (_) {
      // Cancel the body stream to release the underlying socket.
      // Without this, a thrown cancellation would leave the HTTP
      // connection open indefinitely.
      _cancelBody(response.body.listen((_) {}));
      rethrow;
    }

    if (!response.isSuccess) {
      // Reading the head cancels the body, which releases the socket.
      final (bodyHead, bodyRead) =
          await _readErrorBodyHead(response.body, cancelToken);
      _throwForStreamStatusCode(
        response,
        uri,
        bodyHead,
        bodyRead,
        cancelToken,
      );
    }

    // If no cancel token, return response as-is
    if (cancelToken == null) {
      return response;
    }

    // Wrap body stream with cancellation support
    return StreamedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      body: _wrapStreamWithCancellation(response.body, cancelToken),
    );
  }

  /// Closes the transport and releases resources.
  ///
  /// After calling this method, no further requests should be made.
  void close() {
    _client.close();
  }

  /// Wraps a stream with cancellation support from a [CancelToken].
  ///
  /// When the token fires, a [CancelledException] is injected into the
  /// controller and the underlying subscription is cancelled. This cancel
  /// sends TCP RST to the server — it is an abrupt close, not graceful.
  /// Callers that receive a terminal application event (e.g. RunFinishedEvent)
  /// should detach from the stream without cancelling to allow the server to
  /// close the connection naturally.
  Stream<List<int>> _wrapStreamWithCancellation(
    Stream<List<int>> source,
    CancelToken cancelToken,
  ) {
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;

    controller = StreamController<List<int>>(
      onListen: () {
        // Listen to cancellation
        cancelToken.whenCancelled.then((_) {
          if (!controller.isClosed) {
            controller
              ..addError(CancelledException(reason: cancelToken.reason))
              ..close();
            subscription?.cancel();
          }
        });

        // Forward stream data
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );

    return controller.stream;
  }

  /// Reads a refused stream's body until it ends, reaches [_errorBodyLimit]
  /// bytes, outlasts [_errorBodyWait], or [cancelToken] fires, then cancels
  /// it so the socket is released. Returns the first [_errorBodyLimit] bytes
  /// and how the read ended: `complete`, `limit`, `timeout`, `cancelled`, or
  /// `error: <type>`.
  ///
  /// A refused stream answers with an ordinary error body, not SSE, but
  /// nothing stops a misbehaving server from streaming it forever. A body
  /// that fails mid-read is deliberately not rethrown: the status the caller
  /// throws for is the failure, and the bytes read so far still help.
  Future<(List<int>, String)> _readErrorBodyHead(
    Stream<List<int>> body,
    CancelToken? cancelToken,
  ) async {
    final bytes = <int>[];
    final ended = Completer<String>();
    void end(String outcome) {
      if (!ended.isCompleted) ended.complete(outcome);
    }

    final subscription = body.listen(
      (chunk) {
        bytes.addAll(chunk);
        if (bytes.length >= _errorBodyLimit) end('limit');
      },
      onError: (Object error) => end('error: ${error.runtimeType}'),
      onDone: () => end('complete'),
      cancelOnError: true,
    );
    // Subscribed rather than chained with `then`, so the listener detaches
    // when the read ends instead of pinning it to the token.
    final cancelled =
        cancelToken?.whenCancelled.asStream().listen((_) => end('cancelled'));
    final outcome = await ended.future.timeout(
      _errorBodyWait,
      onTimeout: () => 'timeout',
    );
    unawaited(cancelled?.cancel());
    _cancelBody(subscription);
    return (bytes.take(_errorBodyLimit).toList(), outcome);
  }

  /// Cancels a response body's [subscription], which releases the socket.
  ///
  /// A failed cancel is logged rather than left to surface as an uncaught
  /// async error.
  void _cancelBody(StreamSubscription<List<int>> subscription) {
    unawaited(
      subscription.cancel().catchError((Object error, StackTrace stackTrace) {
        _logger.warning(
          'Could not cancel a response body',
          attributes: {'failure': describeFailure(error)},
          stackTrace: stackTrace,
        );
      }),
    );
  }

  /// Logs a refused stream, then throws [CancelledException] if
  /// [cancelToken] fired, or else the exception for its status code.
  ///
  /// The message is the server's reason in [bodyHead] (see [_serverReason]);
  /// otherwise the status code and reason phrase. The refusal is logged even
  /// when the caller cancelled, so it is not lost behind the cancellation.
  Never _throwForStreamStatusCode(
    StreamedHttpResponse response,
    Uri uri,
    List<int> bodyHead,
    String bodyRead,
    CancelToken? cancelToken,
  ) {
    final statusCode = response.statusCode;
    final reason = _serverReason(utf8.decode(bodyHead, allowMalformed: true));

    // Every value here is safe to log: the only caller, `AgUiStreamClient`,
    // streams `rooms/{room}/agui/{thread}/{run}`, which holds only
    // identifiers, and the query is not logged; the reason has been through
    // [_serverReason]; and the `Server` header names software, not a person.
    // A body that is not JSON — a proxy's HTML page, say — contributes only
    // its content type and the number of bytes read. Those and the `Server`
    // header are what tell a proxy's refusal from the backend's.
    _logger.warning(
      'Stream request refused',
      attributes: {
        'statusCode': statusCode,
        'path': uri.path,
        'contentType': response.headers['content-type'] ?? 'none',
        'bodyBytesRead': bodyHead.length,
        'bodyRead': bodyRead,
        if (response.headers['server'] case final server?) 'server': server,
        if (reason != null) 'reason': reason,
      },
    );

    cancelToken?.throwIfCancelled();

    final reasonPhrase = response.reasonPhrase;
    _throwForStatus(
      statusCode,
      uri,
      message: reason ??
          'HTTP $statusCode${reasonPhrase != null ? ': $reasonPhrase' : ''}',
      serverMessage: reason,
      body: null,
    );
  }

  /// Throws appropriate exception for HTTP error status codes.
  void _throwForStatusCode(HttpResponse response, Uri uri) {
    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      return; // Success
    }

    // Lenient: an error body is diagnostic text only, and a non-UTF-8 payload
    // must not throw here or it would mask the status (breaking retry/re-auth).
    final body = response.bodyLenient;
    final serverMessage = _serverReason(body);
    _throwForStatus(
      statusCode,
      uri,
      message: serverMessage ?? 'HTTP $statusCode',
      serverMessage: serverMessage,
      body: body.isNotEmpty ? body : null,
    );
  }

  Never _throwForStatus(
    int statusCode,
    Uri uri, {
    required String message,
    required String? serverMessage,
    required String? body,
  }) {
    if (statusCode == 401) {
      throw AuthException(
        message: message,
        statusCode: statusCode,
        serverMessage: serverMessage,
      );
    }

    if (statusCode == 403) {
      throw PermissionDeniedException(
        message: message,
        statusCode: statusCode,
        serverMessage: serverMessage,
      );
    }

    if (statusCode == 404) {
      throw NotFoundException(
        message: message,
        resource: uri.path,
        serverMessage: serverMessage,
      );
    }

    // All other non-2xx statuses
    throw ApiException(
      message: message,
      statusCode: statusCode,
      serverMessage: serverMessage,
      body: body,
    );
  }

  /// The reason a server wrote for an error: the first of its JSON
  /// `message`, `error` and `detail` that is a non-blank string, with
  /// [_credential] matches replaced and capped at [_reasonLimit] characters.
  ///
  /// This is the only text of an error body that becomes an exception's
  /// message, which the UI shows and logs record. ([ApiException.body] holds
  /// the full body; its `toString()` leaves it out, and it must not be
  /// logged.) The reason is taken on trust: the backend's error strings are
  /// its own words and must never quote request content or a secret, which
  /// the client cannot detect in prose. [_credential] is only a backstop. A
  /// validation list is never used: it echoes the request back.
  static String? _serverReason(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;

    for (final key in const ['message', 'error', 'detail']) {
      if (json[key] case final String text when text.trim().isNotEmpty) {
        final safe = text.replaceAll(_credential, '[REDACTED]');
        final runes = safe.runes;
        return runes.length <= _reasonLimit
            ? safe
            : '${String.fromCharCodes(runes.take(_reasonLimit))}…';
      }
    }
    return null;
  }

  /// Decodes the response body, optionally using a [fromJson] converter.
  T _decodeResponse<T>(
    HttpResponse response,
    T Function(Map<String, dynamic>)? fromJson,
  ) {
    // Any failure decoding the body of an otherwise well-formed HTTP response
    // (bad bytes, a cast that doesn't match T, invalid JSON, or a throwing
    // fromJson mapper) is a malformed *payload*, surfaced as a (non-retryable)
    // MalformedResponseException rather than a raw TypeError/FormatException. A
    // SoliplexException from the mapper passes through unchanged.
    try {
      final body = response.body;

      // Empty body is legitimate for a nullable/void T (e.g. 204); a failed
      // cast here means the caller expected a body that never arrived.
      if (body.isEmpty) {
        return null as T;
      }

      // Check if response is JSON
      final contentType = response.contentType ?? '';
      final isJson = contentType.contains('application/json') ||
          body.trimLeft().startsWith('{') ||
          body.trimLeft().startsWith('[');

      if (!isJson) {
        // Return raw string
        return body as T;
      }

      // Decode JSON
      final decoded = jsonDecode(body);

      // If fromJson is provided and response is a Map, use it
      if (fromJson != null && decoded is Map<String, dynamic>) {
        return fromJson(decoded);
      }

      // Return decoded JSON as-is
      return decoded as T;
    } on SoliplexException {
      rethrow;
    } on Object catch (error, stackTrace) {
      // `bodyBytes.length`, not `body.length`: `body` decodes UTF-8 and
      // throws, and a throw here would replace the exception being built.
      // The content type names a proxy or portal page answering in the
      // backend's place, which the failure alone cannot.
      throw MalformedResponseException(
        message: 'Could not decode the response body as $T '
            '(content-type ${response.contentType ?? 'none'}, '
            '${response.bodyBytes.length} bytes): '
            '${describeFailure(error)}',
        originalError: error,
        stackTrace: stackTrace,
      );
    }
  }
}
