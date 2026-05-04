import 'package:soliplex_agent/src/models/failure_reason.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Maps an error to a [FailureReason] for state machine transitions.
///
/// Handles both `SoliplexException` hierarchy (from REST calls)
/// and `AgUiError` hierarchy (from AG-UI streaming).
FailureReason classifyError(Object error) {
  // Match the typed resume failure before the generic NetworkException
  // unwrap — `StreamResumeFailedException` is a `NetworkException`, so
  // the unwrap would otherwise route it to whatever the underlying
  // transport error classifies as (typically `networkLost`).
  if (error is StreamResumeFailedException) {
    return FailureReason.streamResumeFailed;
  }
  if (error is NetworkException && error.originalError != null) {
    return classifyError(error.originalError!);
  }
  if (error is AuthException) return FailureReason.authExpired;
  if (error is NetworkException) return FailureReason.networkLost;
  if (error is TransportError) return _classifyTransportError(error);
  return FailureReason.internalError;
}

FailureReason _classifyTransportError(TransportError error) {
  final status = error.statusCode;
  if (status == null) return FailureReason.serverError;
  if (status == 401 || status == 403) return FailureReason.authExpired;
  if (status == 429) return FailureReason.rateLimited;
  return FailureReason.serverError;
}
