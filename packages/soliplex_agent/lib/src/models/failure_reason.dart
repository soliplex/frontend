/// Why an agent run failed.
///
/// Every error the orchestrator encounters is classified into one of
/// these categories. The sealed `AgentResult` hierarchy carries this
/// classification so callers can handle each scenario exhaustively.
enum FailureReason {
  /// Server returned an error event in the AG-UI stream.
  serverError,

  /// Auth token expired or was rejected (401).
  authExpired,

  /// Server returned 403: the user is authenticated but lacks
  /// permission for this resource. Re-authenticating won't help.
  permissionDenied,

  /// A `NetworkException` that carries no underlying error, outside a stream
  /// resume. One that carries an error is classified by that error.
  networkLost,

  /// The run's stream ended with no error and no terminal event. A stream that
  /// fails with an error after its first event id is resumed instead, and
  /// fails as [streamResumeFailed] when the resume cannot continue.
  streamEndedEarly,

  /// SSE `Last-Event-ID` resume failed — either the retry budget was
  /// exhausted or a non-retryable error surfaced during a resume.
  streamResumeFailed,

  /// Server returned 429 Too Many Requests.
  rateLimited,

  /// Tool execution failed (all retries exhausted).
  toolExecutionFailed,

  /// Internal error in the orchestrator itself.
  internalError,

  /// Run was cancelled by the caller.
  cancelled,
}
