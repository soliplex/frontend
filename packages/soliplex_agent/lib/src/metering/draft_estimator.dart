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
/// the over-count is a rounding error: a 500-character English draft
/// estimated 30% high costs about 40 tokens of a 32k window, roughly a
/// tenth of a percent.
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

/// Estimates the tokens [text] will occupy, biased high.
///
/// Returns 0 for empty text — an empty composer adds nothing, and
/// showing the per-message overhead for a message nobody is writing
/// would make the gauge twitch for no reason.
int estimateDraftTokens(String text) {
  if (text.isEmpty) return 0;

  var pieces = 0;
  var longRunPenalty = 0;
  var wideChars = 0;

  for (final match in _piece.allMatches(text)) {
    pieces++;

    // A long alphabetic run splits further under real BPE, so it costs
    // more than one token. Roughly one extra per six characters past
    // the first six tracks observed behaviour without a vocabulary.
    final length = match.end - match.start;
    if (length > 6) longRunPenalty += (length - 6) ~/ 6;
  }

  // A run of CJK matches '\p{L}+' as a single piece, which is where a
  // pre-tokenizer-shaped estimate reads catastrophically low: those
  // scripts cost around a token per character. Counting every
  // non-Latin-range code unit again puts that back, and over-counts
  // accented Latin text slightly rather than under-counting Han.
  for (final unit in text.codeUnits) {
    if (unit > 0x024F) wideChars++;
  }

  final base = (pieces * _safetyMargin).ceil() + longRunPenalty;

  return base + wideChars + perMessageOverhead;
}
