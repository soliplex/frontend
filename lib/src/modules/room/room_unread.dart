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

/// The rail's room order plus where the unread→read divider goes.
/// [dividerIndex] is the index in [rooms] of the first read-section room, or
/// null when no divider should show (either section empty).
typedef RoomRailOrder = ({List<Room> rooms, int? dividerIndex});

/// Orders [rooms] for the rooms rail:
///   1. the selected room (if present), pinned first regardless of its state;
///   2. unread rooms, newest [activity] first;
///   3. read rooms that have activity, newest first;
///   4. rooms with no activity, alphabetical (case-insensitive) by name.
///
/// A divider separates the unread section (2) from the read sections
/// (3+4); [RoomRailOrder.dividerIndex] marks its position, or is null when
/// either section is empty.
///
/// [activity] maps room id to last-activity (null when the room has no runs).
/// [unreadRoomIds] is the caller's already-computed unread set, so this only
/// orders — it does not re-derive unread.
RoomRailOrder orderRoomsForRail(
  List<Room> rooms,
  Map<String, DateTime?> activity,
  Set<String> unreadRoomIds, {
  String? selectedRoomId,
}) {
  int rankOf(Room room) {
    if (room.id == selectedRoomId) return 0;
    if (unreadRoomIds.contains(room.id)) return 1;
    if (activity[room.id] != null) return 2;
    return 3;
  }

  int byName(Room a, Room b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  final ordered = [...rooms]..sort((a, b) {
      final ra = rankOf(a);
      final rb = rankOf(b);
      if (ra != rb) return ra.compareTo(rb);
      if (ra == 3) return byName(a, b); // no-activity: alphabetical
      // Unread and read-with-activity sections: newest activity first.
      final ta = activity[a.id];
      final tb = activity[b.id];
      if (ta == null && tb == null) return byName(a, b);
      if (ta == null) return 1;
      if (tb == null) return -1;
      final byActivity = tb.compareTo(ta);
      return byActivity != 0 ? byActivity : byName(a, b);
    });

  final firstReadIndex = ordered.indexWhere((room) => rankOf(room) >= 2);
  final hasUnread = ordered.any((room) => rankOf(room) == 1);
  final dividerIndex =
      (hasUnread && firstReadIndex != -1) ? firstReadIndex : null;

  return (rooms: ordered, dividerIndex: dividerIndex);
}
