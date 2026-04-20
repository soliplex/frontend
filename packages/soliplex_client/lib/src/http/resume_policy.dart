import 'dart:math';

import 'package:ag_ui/ag_ui.dart';

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
  }) : _random = random;

  /// Disable resume entirely — a single attempt with no retries.
  const ResumePolicy.disabled() : this(maxAttempts: 0);

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
  Duration backoffFor(int attempt) {
    assert(attempt >= 1, 'attempt is 1-based');
    final raw =
        initialBackoff.inMilliseconds * pow(backoffMultiplier, attempt - 1);
    final capped = min(raw.toDouble(), maxBackoff.inMilliseconds.toDouble());
    final rnd = _random ?? Random();
    final jitterFactor = 1.0 + (rnd.nextDouble() * 2 - 1) * jitter;
    final ms = (capped * jitterFactor).round().clamp(0, 1 << 30);
    return Duration(milliseconds: ms);
  }
}

/// Names of synthetic [CustomEvent]s that `AgUiStreamClient` yields into
/// the run stream when a dropped SSE connection is detected and resumed.
///
/// UI consumers can intercept these to render a reconnect banner; they are
/// never emitted by the server and never persisted.
abstract final class ReconnectEvent {
  /// Announced when an SSE drop is detected and a resume attempt is about
  /// to begin.
  ///
  /// Value: `{attempt: int, lastEventId: String?, error: String?}`.
  static const reconnecting = 'stream.reconnecting';

  /// Announced on the first decoded event of a successful resume.
  ///
  /// Value: `{attempt: int}`.
  static const reconnected = 'stream.reconnected';

  /// Announced when the retry budget is exhausted. A synthetic
  /// [RunErrorEvent] is yielded immediately after so downstream state
  /// machines see a terminal run without resume-specific branches.
  ///
  /// Value: `{attempts: int, error: String?}`.
  static const failed = 'stream.reconnect_failed';

  static const _namePrefix = 'stream.';

  /// True when [name] is one of the reconnect-lifecycle events.
  static bool isReconnectEvent(String name) => name.startsWith(_namePrefix);
}

/// Typed interpretation of a reconnect-lifecycle [CustomEvent].
sealed class ReconnectStatus {
  const ReconnectStatus();

  /// Parse a [CustomEvent] into a [ReconnectStatus], or null if [event]
  /// is not one of the reconnect-lifecycle events.
  static ReconnectStatus? tryParse(CustomEvent event) {
    final rawValue = event.value;
    final map =
        rawValue is Map<String, dynamic> ? rawValue : const <String, dynamic>{};
    switch (event.name) {
      case ReconnectEvent.reconnecting:
        return Reconnecting(
          attempt: (map['attempt'] as num?)?.toInt() ?? 0,
          lastEventId: map['lastEventId'] as String?,
          error: map['error'] as String?,
        );
      case ReconnectEvent.reconnected:
        return Reconnected(
          attempt: (map['attempt'] as num?)?.toInt() ?? 0,
        );
      case ReconnectEvent.failed:
        return ReconnectFailed(
          attempts: (map['attempts'] as num?)?.toInt() ?? 0,
          error: map['error'] as String?,
        );
    }
    return null;
  }
}

/// Resume attempt in progress.
class Reconnecting extends ReconnectStatus {
  /// Creates a [Reconnecting] status.
  const Reconnecting({
    required this.attempt,
    this.lastEventId,
    this.error,
  });

  /// 1-based attempt index (first retry = 1).
  final int attempt;

  /// The `Last-Event-ID` the client is about to reconnect with.
  final String? lastEventId;

  /// Error message that triggered the drop, for display.
  final String? error;
}

/// Resume succeeded — the stream is live again.
class Reconnected extends ReconnectStatus {
  /// Creates a [Reconnected] status.
  const Reconnected({required this.attempt});

  /// Attempt number that succeeded (1-based).
  final int attempt;
}

/// Resume budget exhausted. The run should be considered terminal; a
/// synthetic `RunErrorEvent` follows this status in the event stream.
class ReconnectFailed extends ReconnectStatus {
  /// Creates a [ReconnectFailed] status.
  const ReconnectFailed({required this.attempts, this.error});

  /// Total number of attempts performed before giving up.
  final int attempts;

  /// Error message from the last attempt, for display.
  final String? error;
}
