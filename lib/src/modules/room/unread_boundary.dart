import 'package:soliplex_agent/soliplex_agent.dart';

import 'compute_display_messages.dart';

/// The id of the first unread message, given [boundaryAnchorId] — the id of the
/// last message the user had already seen. Returns null when there is no line
/// to draw: no anchor, the anchor is the last message, or the anchor is absent
/// from [displayMessages] (e.g. it belonged to a run that is no longer
/// replayed).
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
