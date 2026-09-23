import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';
import 'lay_out_timeline.dart';

/// The read state behind the unread "New messages" divider for an open thread.
sealed class UnreadBoundary {
  const UnreadBoundary();
}

/// The read state hasn't loaded from disk yet; the divider must wait rather
/// than treat a not-yet-loaded null as "caught up".
final class BoundaryPending extends UnreadBoundary {
  const BoundaryPending();
}

/// The read state is known. [anchorId] is the last message the user had already
/// seen (null when there is no prior anchor, so no line is drawn); the divider
/// sits just after it.
final class BoundaryResolved extends UnreadBoundary {
  const BoundaryResolved(this.anchorId);

  final String? anchorId;
}

/// The id of the first unread message, given [boundaryAnchorId] — the id of the
/// last message the user had already seen. Returns null when there is no line
/// to draw: no anchor, the anchor is the last message, the anchor is absent
/// from [displayMessages] (e.g. it belonged to a run that is no longer
/// replayed), or the only message after the anchor is the loading placeholder.
String? firstUnreadMessageId(
  List<ChatMessage> displayMessages,
  String? boundaryAnchorId,
) {
  if (boundaryAnchorId == null) return null;
  final index = displayMessages.indexWhere((m) => m.id == boundaryAnchorId);
  if (index == -1 || index >= displayMessages.length - 1) return null;
  final next = displayMessages[index + 1].id;
  return next == loadingMessageId ? null : next;
}

/// The scroll offset that reveals the "New messages" divider near the top of
/// the viewport while showing as much of the preceding (already-read) anchor
/// message as fits in [contextBudget].
///
/// [dividerTop] is the offset that puts the divider at the viewport top;
/// [anchorTop] puts the anchor (the read message just above the divider) at the
/// top. The anchor sits above the divider, so `anchorTop <= dividerTop`.
///
/// - When the anchor is short (`dividerTop - anchorTop <= contextBudget`) the
///   result is [anchorTop]: the whole anchor shows at the top with the divider
///   just below it.
/// - When the anchor is taller than [contextBudget] the result pins the divider
///   exactly [contextBudget] below the top (`dividerTop - contextBudget`), so
///   the divider stays visible and the anchor's tail peeks above it. This
///   guarantees the divider is never pushed off-screen by a long anchor
///   message — its visibility takes priority over showing full context.
///
/// The caller clamps the result to the scrollable range.
double unreadScrollOffset({
  required double anchorTop,
  required double dividerTop,
  required double contextBudget,
}) {
  assert(anchorTop <= dividerTop, 'the anchor sits above the divider');
  final pinnedDivider = dividerTop - contextBudget;
  return anchorTop > pinnedDivider ? anchorTop : pinnedDivider;
}

/// The id of the last tile the timeline shows, used to advance the read anchor.
///
/// Laid out rather than read off [messages], because the two differ: a message
/// opened only to name a tool call is committed but never shown, and a run that
/// ended with nothing to show for itself is shown but never committed. An
/// anchor on either side of that gap is an id [firstUnreadMessageId] cannot
/// find, and a divider it cannot find is a divider it does not draw.
///
/// Laid out from the same inputs as the timeline, so it is the timeline's own
/// last tile and follows every rule that decides what the timeline shows.
///
/// Except the live projection of [streaming]: the loading tile names no
/// message, so persisting it would lose the line on reload, and a reply still
/// streaming has been seen only in part, so anchoring on it would mark the rest
/// read.
String? lastShownMessageId({
  required List<ChatMessage> messages,
  required Map<String, NoResponseTile> outcomes,
  required Map<String, ExecutionTracker> bands,
  required StreamingState? streaming,
  required String? activeRunId,
}) {
  final streamingId = switch (streaming) {
    TextStreaming(:final messageId) => messageId,
    AwaitingText() || null => null,
  };
  final shown = layOutTimeline(
    messages: messages,
    bands: bands,
    outcomes: outcomes,
    streaming: streaming,
    activeRunId: activeRunId,
  );
  for (final tile in shown.tiles.reversed) {
    final message = tile.message;
    if (message is LoadingMessage || message.id == streamingId) continue;
    return message.id;
  }
  return null;
}
