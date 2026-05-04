import 'dart:math';

/// Configuration for SSE stream resume behavior on `AgUiStreamClient`.
///
/// The client reconnects with a `Last-Event-ID` header when the SSE
/// stream drops mid-run. [maxAttempts] bounds the retry budget; each
/// attempt waits `initialBackoff * backoffMultiplier^(attempt-1)` capped
/// at [maxBackoff], plus ±[jitter] random jitter.
class ResumePolicy {
  /// Creates a resume policy. Defaults: 5 attempts, 500ms → 8s exponential
  /// backoff, ±20% jitter.
  const ResumePolicy({
    this.maxAttempts = 5,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 8),
    this.backoffMultiplier = 2.0,
    this.jitter = 0.2,
    Random? random,
  })  : _random = random,
        assert(maxAttempts >= 0, 'maxAttempts must be non-negative'),
        assert(backoffMultiplier >= 1.0, 'backoffMultiplier must be >= 1.0'),
        assert(jitter >= 0 && jitter <= 1, 'jitter must be in [0, 1]');

  /// One attempt, no retries. Useful for tests and consumers that
  /// want to opt out of resume.
  const ResumePolicy.noRetry() : this(maxAttempts: 0);

  /// Maximum number of consecutive resume attempts after a drop before
  /// giving up. `0` disables resume.
  final int maxAttempts;

  /// Delay before the first resume attempt after a drop.
  final Duration initialBackoff;

  /// Upper bound on per-attempt backoff duration.
  final Duration maxBackoff;

  /// Geometric growth factor applied per attempt.
  final double backoffMultiplier;

  /// Random jitter fraction applied to each backoff, in the range
  /// `[-jitter, +jitter]`. `0.2` means ±20%.
  final double jitter;

  final Random? _random;

  /// Whether resume is enabled (i.e. [maxAttempts] &gt; 0).
  bool get enabled => maxAttempts > 0;

  /// Backoff for a 1-based [attempt] index (first retry = 1).
  ///
  /// Result is bounded to `[0, maxBackoff]`. Jitter is applied after
  /// the geometric ramp is clamped to `maxBackoff`, then the result is
  /// re-clamped — so the documented [maxBackoff] is a strict ceiling
  /// rather than a pre-jitter midpoint.
  Duration backoffFor(int attempt) {
    assert(attempt >= 1, 'attempt is 1-based');
    final raw =
        initialBackoff.inMilliseconds * pow(backoffMultiplier, attempt - 1);
    final capped = min(raw.toDouble(), maxBackoff.inMilliseconds.toDouble());
    final rnd = _random ?? Random();
    final jitterFactor = 1.0 + (rnd.nextDouble() * 2 - 1) * jitter;
    final ms =
        (capped * jitterFactor).round().clamp(0, maxBackoff.inMilliseconds);
    return Duration(milliseconds: ms);
  }
}

/// Typed lifecycle of an SSE reconnect attempt.
///
/// Delivered via `AgUiStreamClient.runAgent`'s `onReconnectStatus`
/// callback. The callback is the only channel for reconnect lifecycle —
/// the `BaseEvent` stream is reserved for actual server events.
sealed class ReconnectStatus {
  const ReconnectStatus();
}

/// A resume attempt is about to begin.
class Reconnecting extends ReconnectStatus {
  /// Marks a resume attempt about to start at [attempt].
  const Reconnecting({
    required this.attempt,
    this.lastEventId,
    this.error,
  }) : assert(attempt >= 1, 'attempt is 1-based');

  /// 1-based attempt index (first retry = 1).
  final int attempt;

  /// The `Last-Event-ID` the client is about to reconnect with.
  final String? lastEventId;

  /// Error that triggered the drop. Consumers stringify on demand.
  final Object? error;
}

/// Resume succeeded — the stream is live again.
class Reconnected extends ReconnectStatus {
  /// Marks the first successful event after a resume on [attempt].
  const Reconnected({required this.attempt})
      : assert(attempt >= 1, 'attempt is 1-based');

  /// Attempt number that succeeded (1-based).
  final int attempt;
}

/// Resume budget exhausted. The run fails terminally; the client throws
/// `NetworkException` (with `streamResumeFailedPrefix`) immediately
/// after delivering this status.
class ReconnectFailed extends ReconnectStatus {
  /// Marks the resume budget as exhausted after [attempt] tries.
  const ReconnectFailed({required this.attempt, this.error})
      : assert(attempt >= 1, 'attempt is 1-based');

  /// Total number of attempts performed before giving up (1-based).
  final int attempt;

  /// Error from the last attempt. Consumers stringify on demand.
  final Object? error;
}
