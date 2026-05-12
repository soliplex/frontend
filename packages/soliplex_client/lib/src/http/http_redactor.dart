import 'dart:convert';

/// Centralized redaction logic for HTTP traffic logging.
///
/// Provides static methods to redact sensitive information from headers,
/// URIs, and JSON bodies before they are emitted to observers. This ensures
/// sensitive data never crosses the observer boundary.
///
/// Redaction is always enabled and cannot be bypassed.
class HttpRedactor {
  const HttpRedactor._();

  /// Placeholder text for redacted values.
  static const _redacted = '[REDACTED]';

  /// Placeholder for redacted auth endpoint bodies.
  static const _redactedAuthEndpoint = '[REDACTED - Auth Endpoint]';

  /// Headers that are always redacted (exact match, case-insensitive).
  static const _exactMatchHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
    'x-csrf-token',
    'x-xsrf-token',
    'x-forwarded-for',
    'x-real-ip',
  };

  /// Substrings that trigger header redaction (case-insensitive).
  static const _substringMatchHeaders = [
    'token',
    'key',
    'secret',
    'password',
    'auth',
    'session',
    'credential',
    'bearer',
  ];

  /// Query parameters that are always redacted (case-insensitive).
  static const _sensitiveParams = {
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'code',
    'client_secret',
    'state',
    'code_verifier',
    'session_state',
    'api_key',
    'password',
    'secret',
    'key',
    'credential',
    'auth',
  };

  /// JSON field names that are always redacted (case-insensitive).
  static const _sensitiveFields = {
    'password',
    'secret',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'api_key',
    'client_secret',
    'authorization',
    'credential',
    'bearer',
    'session_token',
    'private_key',
    'signing_key',
    'encryption_key',
  };

  /// URL path patterns that indicate auth endpoints (case-insensitive).
  static const _authEndpointPatterns = [
    '/oauth',
    '/token',
    '/tokens',
    '/auth',
    '/authorization',
    '/login',
    '/signin',
    '/authenticate',
    '/password',
    '/reset-password',
    '/forgot-password',
    '/register',
    '/signup',
    '/session',
    '/sessions',
    '/2fa',
    '/mfa',
    '/otp',
    '/verify',
    '/activate',
    '/api-keys',
    '/credentials',
    '/revoke',
    '/introspect',
    '/userinfo',
  ];

  /// Sensitive form field names for form-encoded body redaction.
  static const _sensitiveFormFields = {
    'password',
    'secret',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'api_key',
    'client_secret',
    'code',
    'code_verifier',
    'credential',
    'authorization',
    'bearer',
    'session_token',
    'private_key',
    'signing_key',
    'encryption_key',
  };

  /// Redacts sensitive header values.
  ///
  /// Headers are redacted if:
  /// - Name matches exactly (case-insensitive): Authorization, Cookie, etc.
  /// - Name contains sensitive substring: token, key, secret, etc.
  static Map<String, String> redactHeaders(Map<String, String> headers) {
    return headers.map((name, value) {
      final lowerName = name.toLowerCase();

      // Check exact match
      if (_exactMatchHeaders.contains(lowerName)) {
        return MapEntry(name, _redacted);
      }

      // Check substring match
      for (final substring in _substringMatchHeaders) {
        if (lowerName.contains(substring)) {
          return MapEntry(name, _redacted);
        }
      }

      return MapEntry(name, value);
    });
  }

  /// Redacts sensitive query parameter values.
  ///
  /// Returns the original URI unchanged if no sensitive parameters are present.
  static Uri redactUri(Uri uri) {
    if (uri.queryParameters.isEmpty) return uri;

    final hasSensitiveParams = uri.queryParameters.keys.any(
      (key) => _sensitiveParams.contains(key.toLowerCase()),
    );
    if (!hasSensitiveParams) return uri;

    final redactedParams = uri.queryParameters.map((key, value) {
      if (_sensitiveParams.contains(key.toLowerCase())) {
        return MapEntry(key, _redacted);
      }
      return MapEntry(key, value);
    });

    return uri.replace(queryParameters: redactedParams);
  }

  /// Redacts sensitive fields from a JSON body.
  ///
  /// For auth endpoints, the entire body is redacted. For other endpoints,
  /// sensitive field names are recursively redacted.
  ///
  /// Returns the redacted body, which may be a Map, List, String, or null.
  static dynamic redactJsonBody(dynamic body, Uri uri) {
    if (body == null) return null;

    // Auth endpoints: redact entire body
    if (_isAuthEndpoint(uri)) {
      return _redactedAuthEndpoint;
    }

    return _redactValue(body);
  }

  /// Redacts a raw string body.
  ///
  /// For auth endpoints, the entire body is redacted.
  /// For other endpoints, form-encoded sensitive fields are redacted.
  static String redactString(String body, Uri uri) {
    if (_isAuthEndpoint(uri)) {
      return _redactedAuthEndpoint;
    }

    // Check if body looks like form-encoded data
    if (_looksLikeFormEncoded(body)) {
      return _redactFormEncodedBody(body);
    }

    return body;
  }

  /// Redacts sensitive fields from SSE stream content.
  ///
  /// For auth endpoints, the entire content is redacted.
  /// For other endpoints, JSON data in SSE events is parsed and redacted.
  static String redactSseContent(String content, Uri uri) {
    if (_isAuthEndpoint(uri)) {
      return _redactedAuthEndpoint;
    }

    // Parse SSE events and redact JSON data payloads
    final buffer = StringBuffer();
    final lines = content.split('\n');

    for (final line in lines) {
      if (line.startsWith('data:')) {
        final data = line.substring(5).trim();
        if (data.isNotEmpty) {
          try {
            final parsed = jsonDecode(data);
            final redacted = _redactValue(parsed);
            buffer.writeln('data: ${jsonEncode(redacted)}');
            continue;
          } catch (_) {
            // Not JSON, pass through
          }
        }
      }
      buffer.writeln(line);
    }

    // Remove trailing newline added by writeln
    var result = buffer.toString();
    if (result.endsWith('\n') && !content.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
    }

    return result;
  }

  /// Checks if a string looks like form-urlencoded data.
  static bool _looksLikeFormEncoded(String body) {
    // Form-encoded data has key=value pairs separated by &
    if (!body.contains('=')) return false;
    // Must have at least one sensitive field pattern
    final lowerBody = body.toLowerCase();
    return _sensitiveFormFields.any((field) => lowerBody.contains('$field='));
  }

  /// Redacts sensitive fields from form-urlencoded body.
  static String _redactFormEncodedBody(String body) {
    final parts = body.split('&');
    final redactedParts = <String>[];

    for (final part in parts) {
      final eqIndex = part.indexOf('=');
      if (eqIndex == -1) {
        redactedParts.add(part);
        continue;
      }

      final key = part.substring(0, eqIndex);
      if (_sensitiveFormFields.contains(key.toLowerCase())) {
        redactedParts.add('$key=$_redacted');
      } else {
        redactedParts.add(part);
      }
    }

    return redactedParts.join('&');
  }

  /// Checks if the URI path indicates an auth endpoint.
  static bool _isAuthEndpoint(Uri uri) {
    final lowerPath = uri.path.toLowerCase();
    return _authEndpointPatterns.any(lowerPath.contains);
  }

  /// Recursively redacts sensitive values in JSON structures.
  static dynamic _redactValue(dynamic value) {
    if (value is Map) {
      return _redactMap(value);
    } else if (value is List) {
      return value.map(_redactValue).toList();
    }
    return value;
  }

  /// Redacts sensitive fields in a map.
  static Map<String, dynamic> _redactMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) {
      final keyStr = key.toString();
      if (_sensitiveFields.contains(keyStr.toLowerCase())) {
        return MapEntry(keyStr, _redacted);
      }
      return MapEntry(keyStr, _redactValue(value));
    });
  }
}
