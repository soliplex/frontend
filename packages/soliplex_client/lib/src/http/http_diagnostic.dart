import 'dart:async';
import 'dart:developer' as developer;

/// Handles a diagnostic from inside the HTTP stack — an internal error
/// that was contained without crashing the request (observer throws,
/// event construction failures, clock skew).
///
/// Routed to `dart:developer.log` by default. Production callers should
/// wire a proper error sink (e.g., `soliplex_logging`).
typedef HttpDiagnosticHandler =
    void Function(
      Object error,
      StackTrace stackTrace, {
      required String message,
    });

/// Default [HttpDiagnosticHandler] — logs at SEVERE via `dart:developer`.
void defaultHttpDiagnosticHandler(
  Object error,
  StackTrace stackTrace, {
  required String message,
}) {
  developer.log(
    message,
    error: error,
    stackTrace: stackTrace,
    level: 1000, // SEVERE
    name: 'soliplex_client.http',
  );
}

/// Wraps [handler] so any throw — sync or from an unawaited async path
/// it started — falls back to `dart:developer.log`. The HTTP stack
/// relies on diagnostic handlers to contain internal errors; a handler
/// that escapes into the caller breaks that contract.
HttpDiagnosticHandler safeDiagnosticHandler(HttpDiagnosticHandler handler) {
  return (Object error, StackTrace stackTrace, {required String message}) {
    runZonedGuarded(() => handler(error, stackTrace, message: message), (
      handlerError,
      handlerStack,
    ) {
      developer.log(
        'Diagnostic handler threw while processing: "$message". '
        'Original error: $error',
        error: handlerError,
        stackTrace: handlerStack,
        level: 1000, // SEVERE
        name: 'soliplex_client.http',
      );
    });
  };
}
