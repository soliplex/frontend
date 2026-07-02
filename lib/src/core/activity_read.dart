/// Identifies a room across servers for the device-local read model. Named
/// fields (rather than a positional `(String, String)`) so the two ids can't
/// be transposed at a lookup or insertion site.
typedef RoomActivityKey = ({String serverId, String roomId});

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
