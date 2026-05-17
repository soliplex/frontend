import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:soliplex_client/soliplex_client.dart';
import 'package:web/web.dart' as web;

/// Web platform HTTP client.
///
/// Implements [SoliplexHttpClient] by recognizing [WebMultipartFileBody]
/// bodies and routing them through `XMLHttpRequest` + `FormData`. The
/// browser builds the multipart body natively and streams from the
/// file's disk-backed `Blob` storage — file bytes never enter the JS
/// heap. Progress is reported from `xhr.upload.onprogress`.
///
/// For every other body type, this client delegates to an inner
/// [DartHttpClient] so non-upload web traffic (GET, JSON POST, SSE)
/// behaves identically to today.
class WebXhrHttpClient implements SoliplexHttpClient {
  /// Wraps an inner [DartHttpClient] for non-upload paths.
  WebXhrHttpClient({Duration defaultTimeout = defaultHttpTimeout})
      : _defaultTimeout = defaultTimeout,
        _inner = DartHttpClient(defaultTimeout: defaultTimeout);

  final Duration _defaultTimeout;
  final DartHttpClient _inner;
  bool _isClosed = false;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    CancelToken? cancelToken,
  }) {
    _checkNotClosed();
    if (body is WebMultipartFileBody) {
      return _sendFormDataViaXhr(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        timeout: timeout ?? _defaultTimeout,
        cancelToken: cancelToken,
      );
    }
    return _inner.request(
      method,
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) {
    _checkNotClosed();
    return _inner.requestStream(
      method,
      uri,
      headers: headers,
      body: body,
      cancelToken: cancelToken,
    );
  }

  Future<HttpResponse> _sendFormDataViaXhr({
    required String method,
    required Uri uri,
    required Map<String, String>? headers,
    required WebMultipartFileBody body,
    required Duration timeout,
    required CancelToken? cancelToken,
  }) {
    cancelToken?.throwIfCancelled();

    final completer = Completer<HttpResponse>();
    final xhr = web.XMLHttpRequest()
      ..open(method.toUpperCase(), uri.toString());

    // Set caller-provided headers. We deliberately do NOT set
    // Content-Type — the browser sets `multipart/form-data; boundary=…`
    // when the body is a FormData instance, including a fresh boundary
    // string. Overriding here breaks the body framing.
    if (headers != null) {
      for (final entry in headers.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'content-type' || lower == 'content-length') continue;
        xhr.setRequestHeader(entry.key, entry.value);
      }
    }

    StreamSubscription<void>? cancelSub;
    Timer? timeoutTimer;
    void cleanup() {
      cancelSub?.cancel();
      timeoutTimer?.cancel();
    }

    if (cancelToken != null) {
      cancelSub = cancelToken.whenCancelled.asStream().listen((_) {
        if (completer.isCompleted) return;
        xhr.abort();
        cleanup();
        completer.completeError(
          CancelledException(reason: cancelToken.reason ?? 'cancelled'),
        );
      });
    }

    timeoutTimer = Timer(timeout, () {
      if (completer.isCompleted) return;
      xhr.abort();
      cleanup();
      completer.completeError(
        NetworkException(
          message: 'Request timed out after ${timeout.inSeconds}s',
          isTimeout: true,
        ),
      );
    });

    final onProgress = body.onProgress;
    if (onProgress != null) {
      xhr.upload.onprogress = ((web.ProgressEvent event) {
        if (event.lengthComputable) {
          onProgress(event.loaded, event.total);
        }
      }).toJS;
    }

    xhr
      ..onload = ((web.Event _) {
        if (completer.isCompleted) return;
        cleanup();
        try {
          completer.complete(_responseFromXhr(xhr));
        } on Object catch (e, st) {
          completer.completeError(
            NetworkException(
              message: 'Failed to read XHR response: $e',
              originalError: e,
              stackTrace: st,
            ),
          );
        }
      }).toJS
      ..onerror = ((web.Event _) {
        if (completer.isCompleted) return;
        cleanup();
        completer.completeError(
          const NetworkException(message: 'XHR network error'),
        );
      }).toJS
      ..onabort = ((web.Event _) {
        if (completer.isCompleted) return;
        cleanup();
        completer.completeError(
          CancelledException(reason: cancelToken?.reason ?? 'aborted'),
        );
      }).toJS
      ..ontimeout = ((web.Event _) {
        if (completer.isCompleted) return;
        cleanup();
        completer.completeError(
          NetworkException(
            message: 'Request timed out after ${timeout.inSeconds}s',
            isTimeout: true,
          ),
        );
      }).toJS;

    final form = web.FormData()
      ..append(body.fieldName, body.fileBlob as web.Blob, body.filename);
    xhr.send(form);

    return completer.future;
  }

  HttpResponse _responseFromXhr(web.XMLHttpRequest xhr) {
    final responseHeaders = <String, String>{};
    final raw = xhr.getAllResponseHeaders();
    for (final line in raw.split('\r\n')) {
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      responseHeaders[name] = value;
    }
    final text = xhr.responseText;
    final bytes = Uint8List.fromList(text.codeUnits);
    return HttpResponse(
      statusCode: xhr.status,
      headers: responseHeaders,
      bodyBytes: bytes,
      reasonPhrase: xhr.statusText,
    );
  }

  @override
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _inner.close();
  }

  void _checkNotClosed() {
    if (_isClosed) {
      throw StateError('WebXhrHttpClient has been closed');
    }
  }
}
