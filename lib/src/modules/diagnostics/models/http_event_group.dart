import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';

enum HttpEventStatus {
  pending,
  success,
  clientError,
  serverError,
  networkError,
  streaming,
  streamComplete,
  streamError,
}

class HttpEventGroup {
  HttpEventGroup({
    required this.requestId,
    this.request,
    this.response,
    this.error,
    this.streamStart,
    this.streamEnd,
  });

  final String requestId;
  final HttpRequestEvent? request;
  final HttpResponseEvent? response;
  final HttpErrorEvent? error;
  final HttpStreamStartEvent? streamStart;
  final HttpStreamEndEvent? streamEnd;

  HttpEventGroup copyWith({
    HttpRequestEvent? request,
    HttpResponseEvent? response,
    HttpErrorEvent? error,
    HttpStreamStartEvent? streamStart,
    HttpStreamEndEvent? streamEnd,
  }) => HttpEventGroup(
    requestId: requestId,
    request: request ?? this.request,
    response: response ?? this.response,
    error: error ?? this.error,
    streamStart: streamStart ?? this.streamStart,
    streamEnd: streamEnd ?? this.streamEnd,
  );

  bool get isStream => streamStart != null;

  String get methodLabel => isStream ? 'SSE' : method;

  String get method {
    if (request case HttpRequestEvent(:final method)) return method;
    if (error case HttpErrorEvent(:final method)) return method;
    if (streamStart case HttpStreamStartEvent(:final method)) return method;
    throw StateError('HttpEventGroup $requestId has no event with method');
  }

  Uri get uri {
    if (request case HttpRequestEvent(:final uri)) return uri;
    if (error case HttpErrorEvent(:final uri)) return uri;
    if (streamStart case HttpStreamStartEvent(:final uri)) return uri;
    throw StateError('HttpEventGroup $requestId has no event with uri');
  }

  String get pathWithQuery {
    final u = uri;
    final path = u.path.isEmpty ? '/' : u.path;
    if (u.hasQuery) return '$path?${u.query}';
    return path;
  }

  Map<String, String> get requestHeaders {
    if (request case HttpRequestEvent(:final headers)) return headers;
    if (streamStart case HttpStreamStartEvent(:final headers)) return headers;
    return const {};
  }

  dynamic get requestBody {
    if (request case HttpRequestEvent(:final body)) return body;
    if (streamStart case HttpStreamStartEvent(:final body)) return body;
    return null;
  }

  DateTime get timestamp {
    if (request case HttpRequestEvent(:final timestamp)) return timestamp;
    if (streamStart case HttpStreamStartEvent(:final timestamp)) {
      return timestamp;
    }
    if (error case HttpErrorEvent(:final timestamp)) return timestamp;
    throw StateError('HttpEventGroup $requestId has no event with timestamp');
  }

  bool get hasEvents =>
      request != null ||
      response != null ||
      error != null ||
      streamStart != null ||
      streamEnd != null;

  HttpEventStatus get status {
    if (isStream) {
      return switch (streamEnd) {
        null => HttpEventStatus.streaming,
        HttpStreamEndEvent(error: _?) => HttpEventStatus.streamError,
        HttpStreamEndEvent() => HttpEventStatus.streamComplete,
      };
    }
    if (error != null) return HttpEventStatus.networkError;
    return switch (response) {
      null => HttpEventStatus.pending,
      HttpResponseEvent(statusCode: final code) when code >= 500 =>
        HttpEventStatus.serverError,
      HttpResponseEvent(statusCode: final code) when code >= 400 =>
        HttpEventStatus.clientError,
      HttpResponseEvent() => HttpEventStatus.success,
    };
  }

  bool get hasSpinner =>
      status == HttpEventStatus.pending || status == HttpEventStatus.streaming;

  String get statusDescription {
    return switch ((status, response, error)) {
      (HttpEventStatus.pending, _, _) => 'pending',
      (HttpEventStatus.success, HttpResponseEvent(:final statusCode), _) =>
        'success, status $statusCode',
      (HttpEventStatus.clientError, HttpResponseEvent(:final statusCode), _) =>
        'client error, status $statusCode',
      (HttpEventStatus.serverError, HttpResponseEvent(:final statusCode), _) =>
        'server error, status $statusCode',
      (HttpEventStatus.networkError, _, HttpErrorEvent(:final exception)) =>
        'network error, ${exception.runtimeType}',
      (HttpEventStatus.streaming, _, _) => 'streaming',
      (HttpEventStatus.streamComplete, _, _) => 'stream complete',
      (HttpEventStatus.streamError, _, _) => 'stream error',
      _ => status.name,
    };
  }

  String get semanticLabel {
    final methodText = isStream ? 'SSE stream' : '$method request';
    return '$methodText to $pathWithQuery, $statusDescription';
  }

  static String formatBody(dynamic body) {
    if (body == null) return '';
    if (body is String) {
      try {
        final parsed = jsonDecode(body);
        return _jsonEncoder.convert(parsed);
      } on FormatException {
        return body;
      }
    }
    try {
      return _jsonEncoder.convert(body);
    } on Object {
      return body.toString();
    }
  }

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  String? toCurl() {
    if (!hasEvents) return null;
    if (request == null && streamStart == null) return null;

    final parts = <String>['curl'];
    if (method != 'GET') parts.add('-X $method');

    for (final entry in requestHeaders.entries) {
      final escapedValue = _shellEscape(entry.value);
      parts.add("-H '${entry.key}: $escapedValue'");
    }

    final body = requestBody;
    if (body != null) {
      final bodyString = body is String ? body : jsonEncode(body);
      final escapedBody = _shellEscape(bodyString);
      parts.add("-d '$escapedBody'");
    }

    parts.add("'${_shellEscape(uri.toString())}'");
    return parts.join(' \\\n  ');
  }

  static String _shellEscape(String value) {
    return value.replaceAll("'", r"'\''");
  }
}
