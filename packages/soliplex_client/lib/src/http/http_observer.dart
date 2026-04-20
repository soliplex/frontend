import 'package:meta/meta.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';

/// Observer interface for HTTP traffic monitoring.
///
/// Implementations can log requests, track metrics, or display debug info.
/// Observers should not modify requests/responses. Observers that throw
/// do not break the request flow — exceptions are routed to the
/// `HttpDiagnosticHandler` configured on `ObservableHttpClient` — but
/// throwing observers obscure real issues, so treat exceptions as bugs.
///
/// Example:
/// ```dart
/// class LoggingObserver implements HttpObserver {
///   @override
///   void onRequest(HttpRequestEvent event) {
///     print('${event.method} ${event.uri}');
///   }
///
///   @override
///   void onResponse(HttpResponseEvent event) {
///     print('${event.statusCode} (${event.duration.inMilliseconds}ms)');
///   }
///
///   @override
///   void onError(HttpErrorEvent event) {
///     print('Error: ${event.exception.message}');
///   }
///
///   @override
///   void onStreamStart(HttpStreamStartEvent event) {
///     print('Stream started: ${event.method} ${event.uri}');
///   }
///
///   @override
///   void onStreamEnd(HttpStreamEndEvent event) {
///     print('Stream ended: ${event.bytesReceived} bytes');
///   }
/// }
/// ```
abstract class HttpObserver {
  /// Called when a request is about to be sent.
  ///
  /// [event] contains request details (method, uri, headers).
  /// Body is intentionally excluded—tokens and credentials may be in flight.
  void onRequest(HttpRequestEvent event);

  /// Called when a response is received (both success and error status codes).
  ///
  /// [event] contains response details (status code, duration, body size).
  /// Not called if request fails at network level (see [onError]).
  void onResponse(HttpResponseEvent event);

  /// Called when a network error occurs (timeout, connection failure, etc.).
  ///
  /// [event] contains the exception and request context.
  void onError(HttpErrorEvent event);

  /// Called when a streaming request begins.
  ///
  /// [event] contains stream request details.
  void onStreamStart(HttpStreamStartEvent event);

  /// Called when a streaming request completes or errors.
  ///
  /// [event] contains the final status (success, error, cancelled).
  void onStreamEnd(HttpStreamEndEvent event);
}

/// Base event for all HTTP observer events.
///
/// Contains a unique [requestId] for correlating events from the same request
/// and a [timestamp] indicating when the event occurred.
///
/// **Invariant**: The [requestId] is unique per event type within a single
/// HTTP call. Two events with the same [requestId] are considered equal
/// (used for correlation). This is by design for grouping related events.
@immutable
abstract class HttpEvent {
  /// Creates an HTTP event.
  const HttpEvent({required this.requestId, required this.timestamp});

  /// Unique identifier for this request.
  ///
  /// Used to correlate request/response/error events from the same HTTP call.
  /// Events from the same request share this ID, enabling grouping of
  /// request → response/error sequences.
  final String requestId;

  /// When this event occurred.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpEvent &&
          runtimeType == other.runtimeType &&
          requestId == other.requestId;

  @override
  int get hashCode => requestId.hashCode;
}

/// Event emitted when a request is sent.
@immutable
class HttpRequestEvent extends HttpEvent {
  /// Creates a request event.
  const HttpRequestEvent({
    required super.requestId,
    required super.timestamp,
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  /// The HTTP method (GET, POST, PUT, DELETE, etc.).
  final String method;

  /// The request URI.
  final Uri uri;

  /// Request headers (may be empty).
  final Map<String, String> headers;

  /// The request body, if captured.
  ///
  /// For JSON requests, this is the parsed/redacted JSON structure.
  /// For other content types, may be a string or null.
  /// GET requests typically have no body.
  final dynamic body;

  @override
  String toString() => 'HttpRequestEvent($requestId, $method $uri)';
}

/// Event emitted when a response is received.
@immutable
class HttpResponseEvent extends HttpEvent {
  /// Creates a response event.
  const HttpResponseEvent({
    required super.requestId,
    required super.timestamp,
    required this.statusCode,
    required this.duration,
    required this.bodySize,
    this.reasonPhrase,
    this.body,
    this.headers,
  });

  /// The HTTP status code (e.g., 200, 404, 500).
  final int statusCode;

  /// Time elapsed from request start to response completion.
  final Duration duration;

  /// Size of the response body in bytes.
  final int bodySize;

  /// The reason phrase from the server (e.g., "OK", "Not Found").
  final String? reasonPhrase;

  /// The response body, if captured.
  ///
  /// For JSON responses, this is the parsed/redacted JSON structure.
  /// For text responses, this is the string content.
  /// For binary responses (when capture is disabled), this may be a
  /// placeholder string like "[Binary data - capture disabled]".
  final dynamic body;

  /// Response headers, if captured.
  ///
  /// Sensitive headers are redacted before storage.
  final Map<String, String>? headers;

  /// Whether this response indicates success (2xx status code).
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  @override
  String toString() =>
      'HttpResponseEvent($requestId, $statusCode, '
      '${duration.inMilliseconds}ms, ${bodySize}B)';
}

/// Event emitted when a network error occurs.
@immutable
class HttpErrorEvent extends HttpEvent {
  /// Creates an error event.
  const HttpErrorEvent({
    required super.requestId,
    required super.timestamp,
    required this.method,
    required this.uri,
    required this.exception,
    required this.duration,
  });

  /// The HTTP method of the failed request.
  final String method;

  /// The URI of the failed request.
  final Uri uri;

  /// The exception that caused the failure.
  final SoliplexException exception;

  /// Time elapsed from request start to error.
  final Duration duration;

  @override
  String toString() =>
      'HttpErrorEvent($requestId, $method $uri, ${exception.runtimeType})';
}

/// Event emitted when a streaming request starts.
@immutable
class HttpStreamStartEvent extends HttpEvent {
  /// Creates a stream start event.
  const HttpStreamStartEvent({
    required super.requestId,
    required super.timestamp,
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  /// The HTTP method (typically GET or POST).
  final String method;

  /// The request URI.
  final Uri uri;

  /// Request headers (may be empty).
  final Map<String, String> headers;

  /// The request body, if captured.
  ///
  /// For JSON requests, this is the parsed/redacted JSON structure.
  /// For other content types, may be a string or null.
  final dynamic body;

  @override
  String toString() => 'HttpStreamStartEvent($requestId, $method $uri)';
}

/// Event emitted when a streaming request ends.
@immutable
class HttpStreamEndEvent extends HttpEvent {
  /// Creates a stream end event.
  const HttpStreamEndEvent({
    required super.requestId,
    required super.timestamp,
    required this.bytesReceived,
    required this.duration,
    this.error,
    this.body,
  });

  /// Total bytes received during streaming.
  final int bytesReceived;

  /// Time elapsed from stream start to end.
  final Duration duration;

  /// The error that caused the stream to end, if any.
  ///
  /// Null for successful completions or user cancellations.
  final SoliplexException? error;

  /// The accumulated stream content (e.g., SSE events).
  ///
  /// Contains the buffered stream data, potentially truncated if it exceeded
  /// the maximum buffer size (500KB). When truncated, the string starts with
  /// "[EARLIER CONTENT DROPPED]".
  final String? body;

  /// Whether the stream completed successfully (no error).
  bool get isSuccess => error == null;

  @override
  String toString() =>
      'HttpStreamEndEvent($requestId, '
      '${bytesReceived}B, ${duration.inMilliseconds}ms'
      '${error != null ? ', error' : ''})';
}
