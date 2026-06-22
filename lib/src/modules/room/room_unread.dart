import 'package:soliplex_client/soliplex_client.dart';

import '../../core/activity_read.dart' show RoomActivityKey, isActivityUnread;
import 'thread_read_markers.dart' show ThreadActivityKey;

export 'thread_read_markers.dart' show ThreadActivityKey;

/// The ids of rooms with activity newer than the device's last-seen marker, for
/// the room rail. [currentRoomId] is excluded — the open room reads as read, so
/// activity arriving while the user views it (e.g. their own reply) does not
/// light its own rail dot. Mirrors the selected-thread exclusion in
/// [unreadThreadIds].
Set<String> unreadRoomIds(
  Map<String, DateTime?> roomActivity,
  Map<RoomActivityKey, DateTime> markers, {
  required String serverId,
  String? currentRoomId,
}) {
  return {
    for (final entry in roomActivity.entries)
      if (entry.key != currentRoomId &&
          isActivityUnread(
            entry.value,
            markers[(serverId: serverId, roomId: entry.key)],
          ))
        entry.key,
  };
}

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

/// Whether to stamp the room read now: true only when no thread is unread AND
/// the room still has activity newer than [roomSeen] (an unread→read transition
/// worth persisting). Returns false when already caught up, so we don't re-stamp
/// on every update.
///
/// "Activity newer than [roomSeen]" is the room-level dot signal, not the truth
/// of unread — the room marker and the per-thread markers are separate, so it
/// can be a stale false positive (dot lit, yet every thread read). The unread
/// truth is the first clause; we stamp only when the dot is lit but no thread is
/// genuinely unread.
///
/// "Newer activity" is the latest [ThreadInfo.lastActivity] across [threads] —
/// the same source as the unread check — so a thread list that hasn't caught up
/// to new activity can't mark the room read over a thread about to surface (the
/// two inputs can never disagree).
bool shouldMarkRoomRead(
  List<ThreadInfo> threads,
  Map<ThreadActivityKey, DateTime> threadMarkers,
  DateTime? roomSeen, {
  required String serverId,
  required String roomId,
  String? selectedThreadId,
}) {
  final hasUnread = unreadThreadIds(
    threads,
    threadMarkers,
    serverId: serverId,
    roomId: roomId,
    selectedThreadId: selectedThreadId,
  ).isNotEmpty;
  if (hasUnread) return false;

  DateTime? latestActivity;
  for (final thread in threads) {
    final activity = thread.lastActivity;
    if (activity != null &&
        (latestActivity == null || activity.isAfter(latestActivity))) {
      latestActivity = activity;
    }
  }
  return isActivityUnread(latestActivity, roomSeen);
}
