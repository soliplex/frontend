import 'dart:async';
import 'dart:convert';

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_diagnostic.dart';
import 'package:soliplex_client/src/http/http_observer.dart';
import 'package:soliplex_client/src/http/http_redactor.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';

/// HTTP client decorator that notifies observers of all HTTP activity.
///
/// Wraps any [SoliplexHttpClient] implementation and notifies registered
/// [HttpObserver]s on requests, responses, errors, and streaming events.
///
/// All sensitive data (headers, URIs, bodies) is redacted via [HttpRedactor]
/// before being emitted to observers. Sensitive data never crosses the
/// observer boundary.
///
/// Observer exceptions are routed to the [HttpDiagnosticHandler] and
/// do not disrupt the request flow.
///
/// Example:
/// ```dart
/// final baseClient = DartHttpClient();
/// final observable = ObservableHttpClient(
///   client: baseClient,
///   observers: [LoggingObserver(), MetricsObserver()],
/// );
///
/// final response = await observable.request('GET', uri);
/// // Observers notified at each step
///
/// observable.close();
/// ```
class ObservableHttpClient implements SoliplexHttpClient {
  /// Creates an observable client wrapping [client].
  ///
  /// Parameters:
  /// - [client]: The underlying client to wrap
  /// - [observers]: List of observers to notify (defaults to empty)
  /// - [generateRequestId]: Optional ID generator for correlation
  ///   (defaults to timestamp-based IDs)
  ObservableHttpClient({
    required SoliplexHttpClient client,
    List<HttpObserver> observers = const [],
    String Function()? generateRequestId,
    HttpDiagnosticHandler? onDiagnostic,
  })  : _client = client,
        _observers = List.unmodifiable(observers),
        _generateRequestId = generateRequestId ?? _defaultRequestIdGenerator,
        _onDiagnostic = onDiagnostic ?? defaultHttpDiagnosticHandler;

  final SoliplexHttpClient _client;
  final List<HttpObserver> _observers;
  final String Function() _generateRequestId;
  final HttpDiagnosticHandler _onDiagnostic;

  static int _requestCounter = 0;

  static const _maxStreamBufferSize = 500 * 1024;

  static String _defaultRequestIdGenerator() {
    return '${DateTime.now().millisecondsSinceEpoch}-${_requestCounter++}';
  }

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final requestId = _generateRequestId();
    final startTime = DateTime.now();

    final redactedUri = HttpRedactor.redactUri(uri);
    final redactedHeaders = HttpRedactor.redactHeaders(headers ?? const {});
    final redactedBody = _redactRequestBody(body, headers, uri);

    _notifyObservers((observer) {
      observer.onRequest(
        HttpRequestEvent(
          requestId: requestId,
          timestamp: startTime,
          method: method,
          uri: redactedUri,
          headers: redactedHeaders,
          body: redactedBody,
        ),
      );
    });

    try {
      final response = await _client.request(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      final redactedResponseBody = _redactResponseBody(response, uri);
      final redactedResponseHeaders = HttpRedactor.redactHeaders(
        response.headers,
      );

      _notifyObservers((observer) {
        observer.onResponse(
          HttpResponseEvent(
            requestId: requestId,
            timestamp: endTime,
            statusCode: response.statusCode,
            duration: duration,
            bodySize: response.bodyBytes.length,
            reasonPhrase: response.reasonPhrase,
            body: redactedResponseBody,
            headers: redactedResponseHeaders,
          ),
        );
      });

      return response;
    } on SoliplexException catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _notifyObservers((observer) {
        observer.onError(
          HttpErrorEvent(
            requestId: requestId,
            timestamp: endTime,
            method: method,
            uri: redactedUri,
            exception: e,
            duration: duration,
          ),
        );
      });

      rethrow;
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
    final requestId = _generateRequestId();
    final startTime = DateTime.now();
    var bytesReceived = 0;

    final streamBuffer = _StreamBuffer(_maxStreamBufferSize);

    final redactedUri = HttpRedactor.redactUri(uri);
    final redactedHeaders = HttpRedactor.redactHeaders(headers ?? const {});
    final redactedBody = _redactRequestBody(body, headers, uri);

    _notifyObservers((observer) {
      observer.onStreamStart(
        HttpStreamStartEvent(
          requestId: requestId,
          timestamp: startTime,
          method: method,
          uri: redactedUri,
          headers: redactedHeaders,
          body: redactedBody,
        ),
      );
    });

    var emittedEnd = false;

    void emitEnd({Object? error, StackTrace? stackTrace}) {
      if (emittedEnd) return;
      emittedEnd = true;
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      final soliplexError = error == null
          ? null
          : (error is SoliplexException
              ? error
              : NetworkException(
                  message: HttpRedactor.redactString(error.toString(), uri),
                  originalError: error,
                  stackTrace: stackTrace,
                ));
      _notifyObservers((observer) {
        observer.onStreamEnd(
          HttpStreamEndEvent(
            requestId: requestId,
            timestamp: endTime,
            bytesReceived: bytesReceived,
            duration: duration,
            error: soliplexError,
            body: HttpRedactor.redactSseContent(streamBuffer.content, uri),
          ),
        );
      });
    }

    final StreamedHttpResponse response;
    try {
      response = await _client.requestStream(
        method,
        uri,
        headers: headers,
        body: body,
        cancelToken: cancelToken,
      );
    } on Object catch (error, stackTrace) {
      // Inner call failed after onStreamStart. Emit onStreamEnd so
      // observers don't see a dangling "stream open" forever.
      emitEnd(error: error, stackTrace: stackTrace);
      rethrow;
    }

    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;

    // `sync: true` avoids a per-chunk microtask hop on high-rate byte
    // streams (e.g. SSE). Backpressure is propagated by the explicit
    // `onPause`/`onResume` forwarding below, not by the sync mode.
    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        try {
          subscription = response.body.listen(
            (data) {
              bytesReceived += data.length;
              streamBuffer.add(data);
              controller.add(data);
            },
            onError: (Object error, StackTrace stackTrace) {
              emitEnd(error: error, stackTrace: stackTrace);
              controller.addError(error, stackTrace);
            },
            onDone: () {
              emitEnd();
              controller.close();
            },
          );
        } on Object catch (error, stackTrace) {
          // response.body.listen can throw synchronously (e.g.
          // StateError when the inner stream was already listened to).
          // Without this catch, emitEnd never fires and observers see a
          // dangling onStreamStart. The error is forwarded to the
          // caller via controller.addError so the bug is not masked.
          emitEnd(error: error, stackTrace: stackTrace);
          controller
            ..addError(error, stackTrace)
            ..close();
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        emitEnd();
        return subscription?.cancel();
      },
    );

    return StreamedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      body: controller.stream,
    );
  }

  @override
  void close() {
    _client.close();
  }

  /// Redacts the request body based on content type and URI.
  dynamic _redactRequestBody(
    Object? body,
    Map<String, String>? headers,
    Uri uri,
  ) {
    if (body == null) return null;

    if (body is List<int>) {
      final contentType = headers?['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('multipart/form-data') ||
          contentType.contains('application/octet-stream')) {
        return '<binary upload: ${body.length} bytes>';
      }
      final decoded = utf8.decode(body, allowMalformed: true);
      return _redactRequestBody(decoded, headers, uri);
    }

    // List<int> is handled above, so this branch is only for decoded
    // JSON lists (not raw bytes).
    if (body is Map || (body is List && body is! List<int>)) {
      return HttpRedactor.redactJsonBody(body, uri);
    }

    if (body is String) {
      try {
        final parsed = jsonDecode(body);
        return HttpRedactor.redactJsonBody(parsed, uri);
      } on FormatException {
        return HttpRedactor.redactString(body, uri);
      } on Object catch (error, stackTrace) {
        // Pathological input or redactor bug — fall through so the
        // request still completes, but surface the anomaly so we find
        // out if this ever fires in practice.
        _onDiagnostic(
          error,
          stackTrace,
          message: 'Request body redaction failed unexpectedly',
        );
        return HttpRedactor.redactString(body, uri);
      }
    }

    return body.toString();
  }

  /// Redacts the response body based on content type and URI.
  dynamic _redactResponseBody(HttpResponse response, Uri uri) {
    final contentType = response.headers['content-type'] ?? '';

    if (contentType.contains('application/json')) {
      try {
        final parsed = jsonDecode(response.body);
        return HttpRedactor.redactJsonBody(parsed, uri);
      } on FormatException {
        return HttpRedactor.redactString(response.body, uri);
      } on Object catch (error, stackTrace) {
        // Pathological input or redactor bug — fall through so the
        // request still completes, but surface the anomaly so we find
        // out if this ever fires in practice.
        _onDiagnostic(
          error,
          stackTrace,
          message: 'Response body redaction failed unexpectedly',
        );
        return HttpRedactor.redactString(response.body, uri);
      }
    }

    if (contentType.contains('text/')) {
      return HttpRedactor.redactString(response.body, uri);
    }

    return HttpRedactor.redactString(response.body, uri);
  }

  /// Safely notifies all observers. Observer exceptions are caught and
  /// routed to [_onDiagnostic] so they never break the request flow but
  /// remain visible in production logs.
  void _notifyObservers(void Function(HttpObserver observer) notify) {
    for (final observer in _observers) {
      try {
        notify(observer);
      } on Object catch (error, stackTrace) {
        _onDiagnostic(
          error,
          stackTrace,
          message: 'HttpObserver ${observer.runtimeType} threw',
        );
      }
    }
  }
}

/// Rolling buffer for SSE stream content with size limit.
///
/// When content exceeds [maxSize], oldest content is dropped and a
/// truncation indicator is prepended.
class _StreamBuffer {
  _StreamBuffer(this.maxSize);

  final int maxSize;
  final _chunks = <List<int>>[];
  int _totalSize = 0;

  /// Adds data to the buffer, truncating if necessary.
  void add(List<int> data) {
    _chunks.add(data);
    _totalSize += data.length;

    // Truncate oldest chunks if over limit
    while (_totalSize > maxSize && _chunks.length > 1) {
      final removed = _chunks.removeAt(0);
      _totalSize -= removed.length;
    }
  }

  /// Returns the buffered content as a string.
  ///
  /// If truncation occurred, prepends "[EARLIER CONTENT DROPPED]".
  String get content {
    if (_chunks.isEmpty) return '';

    final bytes = _chunks.expand((c) => c).toList();
    final text = utf8.decode(bytes, allowMalformed: true);

    // Check if we've been truncating (total received was more than current)
    if (_totalSize < maxSize) {
      return text;
    }

    // If we're at or near the max, content was likely truncated
    return '[EARLIER CONTENT DROPPED]\n$text';
  }
}
