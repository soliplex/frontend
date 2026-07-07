/// Identifies a room across servers for the device-local read model. Named
/// fields (rather than a positional `(String, String)`) so the two ids can't
/// be transposed at a lookup or insertion site.
typedef RoomActivityKey = ({String serverId, String roomId});

/// Identifies a room read marker, scoped to the user who owns it so a different
/// user signing in on the same device sees their own read state. `userId` is the
/// non-null, sentinel-substituted identity (see `keyed_storage.dart`).
typedef RoomMarkerKey = ({String serverId, String userId, String roomId});

/// Identifies a server read marker, scoped to the user who owns it.
typedef ServerMarkerKey = ({String serverId, String userId});

/// Projects the user-scoped room markers down to the current user per server:
/// keeps each entry whose `userId` equals [userFor] for its server, re-keyed to
/// the user-agnostic [RoomActivityKey] the unread helpers and lobby consume.
///
/// [userFor] returns the non-null identity currently signed into that server (a
/// signed-out or no-auth server resolves to the `unauthenticatedStorageUser`
/// sentinel), letting the multi-server lobby resolve a different user per server.
Map<RoomActivityKey, DateTime> currentUserRoomMarkers(
  Map<RoomMarkerKey, DateTime> markers,
  String Function(String serverId) userFor,
) {
  final result = <RoomActivityKey, DateTime>{};
  markers.forEach((key, at) {
    if (key.userId == userFor(key.serverId)) {
      result[(serverId: key.serverId, roomId: key.roomId)] = at;
    }
  });
  return result;
}

/// Projects the user-scoped server markers down to the current user per server,
/// re-keyed to bare `serverId`. The server twin of [currentUserRoomMarkers].
Map<String, DateTime> currentUserServerMarkers(
  Map<ServerMarkerKey, DateTime> markers,
  String Function(String serverId) userFor,
) {
  final result = <String, DateTime>{};
  markers.forEach((key, at) {
    if (key.userId == userFor(key.serverId)) result[key.serverId] = at;
  });
  return result;
}

/// Whether activity is unread: a known [lastActivity] strictly newer than the
/// user's last-[seen] marker (or it has never been seen). No known activity
/// means there is nothing to be unread about. The tie case ([lastActivity]
/// equal to [seen]) reads as seen.
bool isActivityUnread(DateTime? lastActivity, DateTime? seen) {
  if (lastActivity == null) return false;
  return seen == null || lastActivity.isAfter(seen);
}

/// The later of two "last seen" markers, treating null as never-seen (so it
/// never wins). Used to floor an item's read state under its ancestors: an item
/// reads as read when its activity is at or before the latest of its own marker
/// and its ancestors' (a room's server marker; a thread's room and server
/// markers).
DateTime? latestSeen(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}
