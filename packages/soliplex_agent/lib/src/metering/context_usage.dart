import 'package:meta/meta.dart';

/// The window size at and above which the later warning applies.
const largeContextWindow = 128000;

/// A reading of how much context a thread currently occupies.
///
/// Carries its own confidence rather than leaving the UI to infer it. A
/// number with no denominator has to be presented differently from a
/// settled exact one — and the difference is the whole distinction
/// between a useful gauge and a confidently wrong one.
@immutable
class ContextUsage {
  /// Creates a reading.
  const ContextUsage({
    required this.tokens,
    this.contextWindow,
    this.isExact = false,
  });

  /// Tokens the next request is expected to carry.
  final int tokens;

  /// The model's window, when the provider reports one.
  final int? contextWindow;

  /// Whether every token in [tokens] was counted by the provider.
  ///
  /// False while any locally estimated term is included — a draft in the
  /// composer, or a message already sent that no run has reported on.
  /// Those are estimated locally and deliberately over-stated.
  final bool isExact;

  /// Fraction of the window used, or null when no window is declared.
  ///
  /// Null is deliberate and must not be filled in with a guess: a gauge
  /// with an invented denominator is worse than one showing a bare count.
  double? get fractionUsed {
    final window = contextWindow;
    if (window == null || window <= 0) return null;
    return (tokens / window).clamp(0.0, 1.0);
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
    final window = contextWindow;
    if (window == null || window <= 0) return null;
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
  String toString() =>
      'ContextUsage($tokens / ${contextWindow ?? "?"}, exact: $isExact)';
}
