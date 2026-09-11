// Copied from packages/soliplex_agent/lib/src/metering/context_usage.dart on
// feat/server-measured-context; the mockup carries it until that lands.

import 'package:flutter/foundation.dart' show immutable;

/// The window size at and above which the later warning applies.
const largeContextWindow = 128000;

/// A reading of how much context a thread currently occupies.
///
/// Carries its own confidence rather than leaving the UI to infer it. A
/// number with no denominator has to be presented differently from a
/// settled exact one — and the difference is the whole distinction
/// between a useful gauge and a confidently wrong one.
/// Who put the tokens there. The categories the breakdown reports by.
enum ContextShare {
  human('You'),
  llm('Assistant'),
  system('System'),
  rag('Retrieved documents'),
  tools('Tools');

  const ContextShare(this.label);

  final String label;
}

@immutable
class ContextUsage {
  /// Creates a reading.
  const ContextUsage({
    required this.tokens,
    this.byShare = const {},
    this.contextWindow,
    this.isExact = false,
  });

  /// A reading for a thread nothing is known about yet.
  const ContextUsage.unknown()
      : tokens = 0,
        byShare = const {},
        contextWindow = null,
        isExact = false;

  /// Tokens the next request is expected to carry.
  final int tokens;

  /// Where [tokens] came from. Sums to [tokens] when every share is
  /// accounted for; an unattributed remainder is simply not listed.
  final Map<ContextShare, int> byShare;

  /// [byShare] with a [delta] added to one share, clamped at zero.
  ContextUsage adding(ContextShare share, int delta) {
    final next = Map<ContextShare, int>.of(byShare);
    next[share] = ((next[share] ?? 0) + delta).clamp(0, 1 << 31);
    final window = contextWindow;
    var total = tokens + delta;
    if (total < 0) total = 0;
    if (window != null && total > window) total = window;
    return ContextUsage(
      tokens: total,
      byShare: next,
      contextWindow: window,
      isExact: isExact,
    );
  }

  /// The model's window, when the provider reports one.
  final int? contextWindow;

  /// Whether every token in [tokens] was counted by the provider.
  ///
  /// False while an unsent draft is included, since that term is
  /// estimated locally and deliberately over-stated.
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

  /// Whether a percentage can be shown at all.
  bool get hasWindow => fractionUsed != null;

  /// How much of the window remains, or null without one.
  int? get tokensRemaining {
    final window = contextWindow;
    if (window == null) return null;
    return window - tokens < 0 ? 0 : window - tokens;
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

  @override
  String toString() =>
      'ContextUsage($tokens / ${contextWindow ?? "?"}, exact: $isExact)';
}
