import 'package:meta/meta.dart';

/// What a piece of the request is, for attribution in a breakdown.
enum SegmentKind {
  /// Text the user sent.
  userText,

  /// Text the assistant produced.
  assistantText,

  /// A tool call's serialized arguments.
  toolCallArguments,

  /// A tool result as it currently stands in the request.
  toolResult,

  /// A tool result the backend has replaced with a compaction receipt.
  ///
  /// The evidence is gone from the request even though the transcript still
  /// shows it, which is why counting the visible text would overcount.
  compactedReceipt,

  /// The one earlier tool result carrying the compaction capsule.
  compactedCapsule,

  /// Everything the request carries that the client never sees: the agent's
  /// instructions, capability instructions, tool schemas, chat-template
  /// scaffolding. Measured rather than reconstructed.
  overhead,
}

/// One attributable piece of the request, with its token count once known.
///
/// A [tokens] of null means "not counted yet". The ledger keeps segments
/// rather than a single total precisely so that one piece can be recounted —
/// or reclassified, when the backend compacts it — without touching the
/// rest.
@immutable
class ContextSegment {
  /// Creates a segment.
  const ContextSegment({
    required this.id,
    required this.kind,
    required this.text,
    this.toolName,
    this.tokens,
  });

  /// Stable identity: the AG-UI message id, suffixed for tool calls that
  /// share one message.
  final String id;

  /// What this segment is.
  final SegmentKind kind;

  /// The text as the request carries it.
  final String text;

  /// For tool calls and results, the tool that produced them. Needed to
  /// decide whether evidence compaction applies.
  final String? toolName;

  /// Token count, or null until counted.
  final int? tokens;

  /// Whether this segment still needs counting.
  bool get isDirty => tokens == null;

  /// A copy with [tokens] set.
  ContextSegment counted(int count) => ContextSegment(
        id: id,
        kind: kind,
        text: text,
        toolName: toolName,
        tokens: count,
      );

  /// A copy carrying different text under a different kind, with its count
  /// dropped so it is recounted.
  ContextSegment rewrittenAs(SegmentKind newKind, String newText) =>
      ContextSegment(
        id: id,
        kind: newKind,
        text: newText,
        toolName: toolName,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextSegment &&
          other.id == id &&
          other.kind == kind &&
          other.text == text &&
          other.toolName == toolName &&
          other.tokens == tokens;

  @override
  int get hashCode => Object.hash(id, kind, text, toolName, tokens);

  @override
  String toString() =>
      'ContextSegment($id, ${kind.name}, ${text.length} chars, $tokens)';
}
