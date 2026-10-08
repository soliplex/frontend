import 'package:meta/meta.dart';

/// The window size at and above which the later warning applies.
const _largeContextWindow = 128000;

/// How close a reading is to running out of window, from most room to
/// least: a later value is a worse one.
enum ContextLevel {
  /// Under the warning threshold, or nothing to compare against.
  room,

  /// At or over the warning threshold, and under the window.
  nearlyFull,

  /// At or over the window.
  full,
}

/// A reading of how much context a thread currently occupies.
///
/// Carries its own confidence rather than leaving the UI to infer it. A
/// count with no denominator has to be presented differently from a
/// settled exact one, and a thread nothing has counted differently
/// again — it has no number to present at all. Those differences are
/// the whole distinction between a useful gauge and a confidently wrong
/// one.
@immutable
class ContextUsage {
  /// Creates a reading.
  const ContextUsage({
    this.measuredTokens,
    this.estimatedTokens = 0,
    this.draftTokens = 0,
    this.contextWindow,
  });

  /// What the provider counted for the last request it served, plus that
  /// request's reply — the size the next request starts from — or null
  /// when no run has reported on this thread yet.
  ///
  /// Only the backend sees the whole request — instructions, tool and MCP
  /// schemas, the chat template, images — so this is the one term nothing
  /// here can reconstruct.
  final int? measuredTokens;

  /// Tokens of the conversation guessed locally: what the transcript holds
  /// after the measured run, and a message sent that no transcript carries
  /// yet. Deliberately over-stated by the estimators.
  final int estimatedTokens;

  /// Tokens guessed for the draft in the composer, over-stated like
  /// [estimatedTokens]. Kept apart because it is the one term the user can
  /// still change before it costs anything.
  final int draftTokens;

  /// The model's window, when the provider reports one.
  final int? contextWindow;

  /// Tokens the next request is expected to carry, or null when nothing
  /// has counted this thread.
  ///
  /// Null rather than the estimates alone: they cover a fragment of a
  /// conversation nobody has measured, and showing it as the whole would
  /// read near-empty on a full thread.
  int? get tokens {
    final measured = measuredTokens;
    return measured == null ? null : measured + estimatedTokens + draftTokens;
  }

  /// This reading without the draft: what the conversation alone occupies.
  ContextUsage get withoutDraft => ContextUsage(
        measuredTokens: measuredTokens,
        estimatedTokens: estimatedTokens,
        contextWindow: contextWindow,
      );

  /// Whether every token in [tokens] was counted by the provider.
  bool get isExact =>
      measuredTokens != null && estimatedTokens == 0 && draftTokens == 0;

  /// Fraction of the window used, or null without both a count and a
  /// window to put it over.
  ///
  /// Null is deliberate: a gauge with an invented denominator, or an
  /// invented numerator, is worse than one showing nothing.
  double? get fractionUsed {
    final total = tokens;
    final window = _usableWindow;
    if (total == null || window == null) return null;
    return (total / window).clamp(0.0, 1.0);
  }

  /// The window when the backend reported a size worth reading: zero or
  /// less is no window at all. Here rather than in each accessor, so
  /// that adding one cannot leave the rule out.
  int? get _usableWindow {
    final window = contextWindow;
    return window == null || window <= 0 ? null : window;
  }

  /// The occupancy past which a window is worth warning about.
  ///
  /// A small window warns earlier, because the same percentage leaves
  /// far less room in absolute terms: 20% of 32k is about 6,500 tokens,
  /// perhaps two or three more exchanges, while 15% of 128k is nearly
  /// 20,000 and several more. The point of the warning is to arrive
  /// while there is still room to act on it.
  ///
  /// Null when no window is declared, because there is then no
  /// occupancy to compare against.
  double? get _warningThreshold {
    final window = _usableWindow;
    if (window == null) return null;
    return window < _largeContextWindow ? 0.80 : 0.85;
  }

  /// Where this reading stands between room and a full window.
  ///
  /// [ContextLevel.full] compares the total with the window directly
  /// rather than through [fractionUsed], which is clamped at 1.
  ContextLevel get level {
    final total = tokens;
    final window = _usableWindow;
    final threshold = _warningThreshold;
    if (total == null || window == null || threshold == null) {
      return ContextLevel.room;
    }
    if (total >= window) return ContextLevel.full;
    if (total / window >= threshold) return ContextLevel.nearlyFull;
    return ContextLevel.room;
  }

  /// Whether the thread is close enough to full to say so unprompted.
  bool get isNearlyFull => level != ContextLevel.room;

  /// The occupancy at which the window is about to stop holding the
  /// conversation, whatever its size.
  ///
  /// Flat where the warning threshold scales, because the two answer
  /// different questions. A warning arrives while there is still room to
  /// act, and how much room a fraction leaves depends on the window. This
  /// one says almost none is left, which is the same fraction either way.
  static const criticalThreshold = 0.90;

  /// Whether the thread is close enough to full that the next exchange
  /// may not fit.
  bool get isCritical {
    final fraction = fractionUsed;
    return fraction != null && fraction >= criticalThreshold;
  }

  @override
  String toString() => 'ContextUsage(${tokens ?? "?"} / '
      '${contextWindow ?? "?"}, exact: $isExact)';
}
