import 'package:meta/meta.dart';

/// The window size at and above which the later warning applies.
const largeContextWindow = 128000;

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
    this.contextWindow,
  });

  /// What the provider counted for the last request it served, or null
  /// when no run has reported on this thread yet.
  ///
  /// Only the backend sees the whole request — instructions, tool and MCP
  /// schemas, the chat template, images — so this is the one term nothing
  /// here can reconstruct.
  final int? measuredTokens;

  /// Tokens guessed locally — a draft in the composer, and a message
  /// already sent that no run has reported on — and deliberately
  /// over-stated by the draft estimator.
  final int estimatedTokens;

  /// The model's window, when the provider reports one.
  final int? contextWindow;

  /// Tokens the next request is expected to carry, or null when nothing
  /// has counted this thread.
  ///
  /// Null rather than the estimate alone: a draft is a fragment of a
  /// conversation nobody has measured, and showing it as the whole would
  /// read near-empty on a full thread.
  int? get tokens {
    final measured = measuredTokens;
    return measured == null ? null : measured + estimatedTokens;
  }

  /// Whether every token in [tokens] was counted by the provider.
  bool get isExact => measuredTokens != null && estimatedTokens == 0;

  /// Fraction of the window used, or null without both a count and a
  /// window to put it over.
  ///
  /// Null is deliberate and must not be filled in with a guess: a gauge
  /// with an invented denominator, or an invented numerator, is worse
  /// than one showing nothing.
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

  /// Whether the reading should be presented with a caveat.
  bool get isApproximate => !isExact;

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
  double? get warningThreshold {
    final window = _usableWindow;
    if (window == null) return null;
    return window < largeContextWindow ? 0.80 : 0.85;
  }

  /// Whether the thread is close enough to full to say so unprompted.
  bool get isNearlyFull {
    final fraction = fractionUsed;
    final threshold = warningThreshold;
    if (fraction == null || threshold == null) return false;
    return fraction >= threshold;
  }

  /// The occupancy at which the window is about to stop holding the
  /// conversation, whatever its size.
  ///
  /// Flat where [warningThreshold] scales, because the two answer
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
