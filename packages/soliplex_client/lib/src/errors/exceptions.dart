/// Base exception for all Soliplex client errors.
abstract class SoliplexException implements Exception {
  /// Creates a Soliplex exception.
  const SoliplexException({
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  /// The error message.
  final String message;

  /// The original error that caused this exception, if any.
  final Object? originalError;

  /// The stack trace from the original error, if any.
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// Exception thrown when authentication fails (401, 403).
///
/// UI should redirect to login.
class AuthException extends SoliplexException {
  /// Creates an auth exception.
  const AuthException({
    required super.message,
    this.statusCode,
    this.serverMessage,
    super.originalError,
    super.stackTrace,
  });

  /// The HTTP status code that triggered this exception.
  final int? statusCode;

  /// The error message from the server, if any.
  ///
  /// Null when the server didn't provide a meaningful error message.
  final String? serverMessage;

  @override
  String toString() {
    if (statusCode != null) {
      return 'AuthException($statusCode): $message';
    }
    return 'AuthException: $message';
  }
}

/// Exception thrown when a network error occurs (timeout, unreachable).
///
/// UI should show retry option.
class NetworkException extends SoliplexException {
  /// Creates a network exception.
  const NetworkException({
    required super.message,
    this.isTimeout = false,
    super.originalError,
    super.stackTrace,
  });

  /// Whether this exception was caused by a timeout.
  final bool isTimeout;

  @override
  String toString() {
    if (isTimeout) {
      return 'NetworkException(timeout): $message';
    }
    return 'NetworkException: $message';
  }
}

/// Exception thrown when an API error occurs (4xx, 5xx except 401/403/404).
///
/// UI should show error message.
class ApiException extends SoliplexException {
  /// Creates an API exception.
  const ApiException({
    required super.message,
    required this.statusCode,
    this.serverMessage,
    this.body,
    super.originalError,
    super.stackTrace,
  });

  /// The HTTP status code.
  final int statusCode;

  /// The error message from the server, if any.
  ///
  /// Null when the server didn't provide a meaningful error message.
  final String? serverMessage;

  /// The response body, if available.
  final String? body;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Exception thrown when a resource is not found (404).
///
/// UI should go back/navigate away.
class NotFoundException extends SoliplexException {
  /// Creates a not found exception.
  const NotFoundException({
    required super.message,
    this.resource,
    this.serverMessage,
    super.originalError,
    super.stackTrace,
  });

  /// The resource that was not found.
  final String? resource;

  /// The error message from the server, if any.
  ///
  /// Null when the server didn't provide a meaningful error message.
  final String? serverMessage;

  @override
  String toString() {
    if (resource != null) {
      return 'NotFoundException: $resource not found';
    }
    return 'NotFoundException: $message';
  }
}

/// Exception thrown when an operation is cancelled by the user.
///
/// UI should handle silently.
class CancelledException extends SoliplexException {
  /// Creates a cancelled exception.
  const CancelledException({
    String? reason,
    super.originalError,
    super.stackTrace,
  }) : super(message: reason ?? 'Operation cancelled');

  /// The reason for cancellation.
  String? get reason => message == 'Operation cancelled' ? null : message;

  @override
  String toString() {
    if (reason != null) {
      return 'CancelledException: $reason';
    }
    return 'CancelledException';
  }
}

/// Exception thrown when an unexpected, non-Soliplex error must be
/// surfaced through the client's error channel.
///
/// Use to wrap `Error` subtypes (e.g., `TypeError` from a schema
/// mismatch) or any other throwable that is not already a
/// [SoliplexException]. Keeps the `All exceptions must be
/// SoliplexException subtypes` invariant intact at the client boundary
/// without swallowing the cause.
class UnexpectedException extends SoliplexException {
  /// Creates an unexpected exception.
  const UnexpectedException({
    required super.message,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'UnexpectedException: $message';
}
