import 'package:soliplex_client/soliplex_client.dart';

import '../../core/activity_read.dart' show isActivityUnread;
import 'thread_read_markers.dart' show ThreadActivityKey;

export 'thread_read_markers.dart' show ThreadActivityKey;

/// The ids of [threads] that are unread for this device: a thread is unread
/// when its [ThreadInfo.lastActivity] is newer than the device's last-seen
/// marker for it (or it has activity and no marker). [selectedThreadId] is
/// excluded — the open thread reads as read.
///
/// Used both for the per-thread unread dots and to roll thread-unread up into
/// the room's unread state.
Set<String> unreadThreadIds(
  List<ThreadInfo> threads,
  Map<ThreadActivityKey, DateTime> threadMarkers, {
  required String serverId,
  required String roomId,
  String? selectedThreadId,
}) {
  return {
    for (final thread in threads)
      if (thread.id != selectedThreadId &&
          isActivityUnread(
            thread.lastActivity,
            threadMarkers[(
              serverId: serverId,
              roomId: roomId,
              threadId: thread.id,
            )],
          ))
        thread.id,
  };
}
