import 'package:soliplex_agent/soliplex_agent.dart';

/// The thread keys that were active in [previous] but are no longer active in
/// [current] — i.e. runs that just reached a terminal state — restricted to the
/// room identified by [serverId] and [roomId]. A non-empty result means the
/// room's thread list should be refetched so the unread dot reflects the new
/// activity.
///
/// [excludeThreadId] drops the thread the user is currently viewing: its dot is
/// excluded from the unread set anyway, its content is already live, and a
/// refetch could clobber an optimistic local insert (e.g. a just-spawned
/// thread) with a listing that doesn't reflect it yet.
Set<ThreadKey> completedRoomThreadKeys(
  Set<ThreadKey> previous,
  Set<ThreadKey> current, {
  required String serverId,
  required String roomId,
  String? excludeThreadId,
}) {
  return previous
      .difference(current)
      .where((k) =>
          k.serverId == serverId &&
          k.roomId == roomId &&
          k.threadId != excludeThreadId)
      .toSet();
}

/// Whether any run on [serverId] (in any room) was active in [previous] but is
/// no longer active in [current] — i.e. a run on this server just reached a
/// terminal state. A true result means the server's room-activity batch should
/// be refetched so the rail reflects a room whose background run finished.
bool serverRunCompleted(
  Set<ThreadKey> previous,
  Set<ThreadKey> current, {
  required String serverId,
}) {
  return previous.difference(current).any((k) => k.serverId == serverId);
}
