/// Estimates what a draft will cost, before it is ever sent.
///
/// Everything already in a thread has been counted by the model's own
/// provider and reported back exactly. The draft is the one part of a
/// reading that nothing has measured yet, so it is the one part that has
/// to be guessed — and the guess is deliberately biased high.
///
/// The bias is the point. A gauge that reads low invites someone to keep
/// typing into a window that is already full, so the failure this must
/// avoid is under-counting, not over-counting. Against a typical window
/// the over-count is a rounding error: tens of tokens on a draft, out of
/// tens of thousands in the window.
library;

/// Splits the way a BPE pre-tokenizer does: letter runs, digit runs,
/// punctuation runs, whitespace. This tracks real token counts across
/// prose, code and JSON alike, because it is the same first step the
/// real algorithm takes — and unlike `chars / 4` it does not fall apart
/// on the JSON that dominates a tool-heavy conversation.
final RegExp _piece = RegExp(
  r'\s?\p{L}+|\s?\p{N}+|\s?[^\s\p{L}\p{N}]+|\s+',
  unicode: true,
);

/// Margin applied to the piece count.
///
/// Real BPE splits some pieces further than this can see. A fifth over
/// is enough to cover that on ordinary prose without making the reading
/// useless.
const double _safetyMargin = 1.2;

/// Tokens a message costs before any of its text: role markers and the
/// chat template's turn delimiters. Over-stated on purpose, and small
/// enough against a window that being generous costs nothing.
const int perMessageOverhead = 8;

/// Tokens one image costs, as a flat stand-in for what a vision model
/// will charge.
///
/// Providers price an image by its area and disagree several times over
/// on the same picture: a 1024x1024 runs about 1,024 tokens on GPT-5.5,
/// 1,398 on Claude Opus 4.7 and 1,032 on Gemini 3.1 Pro, while a phone
/// photo reaches 2,451 on the first and 6,636 on the second. No single
/// number covers that spread, so this clears the common case and falls
/// short of the worst, on the same reasoning as everything else here:
/// reading low is the failure to avoid, and a run's own count replaces
/// the guess as soon as one arrives.
const int perImageTokens = 2500;

/// Estimates the tokens a draft of [text] carrying [images] pictures
/// will occupy, biased high.
///
/// Returns 0 for an empty draft — an empty composer adds nothing, and
/// showing the per-message overhead for a message nobody is writing
/// would make the gauge twitch for no reason.
int estimateDraftTokens(String text, {int images = 0}) {
  final pictures = images * perImageTokens;
  if (text.isEmpty) {
    return pictures == 0 ? 0 : pictures + perMessageOverhead;
  }

  var pieces = 0;
  var longRunPenalty = 0;
  var wideChars = 0;

  for (final match in _piece.allMatches(text)) {
    pieces++;

    // A long run splits further under real BPE, so it costs more than
    // one token. Roughly one extra per six characters past the first six
    // tracks observed behaviour without a vocabulary. Every kind of run
    // is charged it, digits and punctuation included.
    final length = match.end - match.start;
    if (length > 6) longRunPenalty += (length - 6) ~/ 6;
  }

  // A run of CJK matches '\p{L}+' as a single piece, which is where a
  // pre-tokenizer-shaped estimate reads catastrophically low: those
  // scripts cost around a token per character. Counting every code unit
  // past Latin Extended-B again puts that back. Precomposed accented
  // Latin sits below that cutoff and is untouched; Greek, Cyrillic and
  // typographic punctuation are over-counted slightly, and anything
  // outside the basic plane — an emoji, a rare ideograph — is charged
  // twice, being two code units.
  for (final unit in text.codeUnits) {
    if (unit > 0x024F) wideChars++;
  }

  final base = (pieces * _safetyMargin).ceil() + longRunPenalty;

  return base + wideChars + pictures + perMessageOverhead;
}
