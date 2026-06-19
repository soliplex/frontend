import 'package:soliplex_agent/soliplex_agent.dart';

import 'compute_display_messages.dart';

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
  final pinnedDivider = dividerTop - contextBudget;
  return anchorTop > pinnedDivider ? anchorTop : pinnedDivider;
}

/// The id of the last non-ephemeral message, used to advance the read anchor.
/// Skips the loading sentinel so a transient [LoadingMessage] is never
/// persisted — it would not resolve on reload and would silently lose the line.
String? lastRealMessageId(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final id = messages[i].id;
    if (id != loadingMessageId) return id;
  }
  return null;
}
