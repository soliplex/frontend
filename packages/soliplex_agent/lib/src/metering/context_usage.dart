import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/metering/context_segment.dart';

/// A reading of how much context a thread currently occupies.
///
/// Carries its own confidence rather than leaving the UI to infer it. A
/// number with no denominator, or one taken before calibration has any
/// evidence, has to be presented differently from a settled exact one —
/// and the difference is the whole distinction between a useful gauge and
/// a confidently wrong one.
/// The window size at and above which the later warning applies.
const largeContextWindow = 128000;

@immutable
class ContextUsage {
  /// Creates a reading.
  const ContextUsage({
    required this.tokens,
    required this.byKind,
    this.contextWindow,
    this.isProvisional = true,
    this.isExact = false,
    this.hasUncountableContent = false,
  });

  /// A reading for a thread nothing is known about yet.
  const ContextUsage.unknown()
      : tokens = 0,
        byKind = const {},
        contextWindow = null,
        isProvisional = true,
        isExact = false,
        hasUncountableContent = false;

  /// Estimated tokens the next request will carry.
  final int tokens;

  /// Where those tokens come from.
  final Map<SegmentKind, int> byKind;

  /// The model's window, when the room declares one.
  final int? contextWindow;

  /// Whether calibration has too little evidence to trust yet.
  final bool isProvisional;

  /// Whether the count came from the model's real tokenizer rather than an
  /// approximation.
  final bool isExact;

  /// Whether the thread holds something no text tokenizer can measure —
  /// an image, most often. Calibration cannot absorb it, because its cost
  /// varies with the attachment rather than staying constant.
  final bool hasUncountableContent;

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
  bool get isApproximate => isProvisional || !isExact || hasUncountableContent;

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
  String toString() => 'ContextUsage($tokens / ${contextWindow ?? "?"}, '
      'exact: $isExact, provisional: $isProvisional)';
}
