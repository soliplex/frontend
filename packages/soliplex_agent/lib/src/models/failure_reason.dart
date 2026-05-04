/// Why an agent run failed.
///
/// Every error the orchestrator encounters is classified into one of
/// these categories. The sealed `AgentResult` hierarchy carries this
/// classification so callers can handle each scenario exhaustively.
enum FailureReason {
  /// Server returned an error event in the AG-UI stream.
  serverError,

  /// Auth token expired or was rejected (401/403).
  authExpired,

  /// Network lost — SSE stream ended without a terminal event.
  networkLost,

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
