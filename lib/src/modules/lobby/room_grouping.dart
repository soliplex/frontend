import 'package:soliplex_agent/soliplex_agent.dart' show Room;

/// Orders [rooms] by [activityFor] descending (newest activity first). Rooms
/// with a null timestamp — none fetched, no threads, or a failed lookup —
/// keep their original relative order at the end. Ties among dated rooms break
/// by original index so equal timestamps stay in input order (`List.sort` is
/// not guaranteed stable). Does not mutate [rooms].
List<Room> sortRoomsByRecency(
  List<Room> rooms,
  DateTime? Function(Room) activityFor,
) {
  final dated = <(Room, DateTime, int)>[];
  final undated = <Room>[];
  for (var i = 0; i < rooms.length; i++) {
    final time = activityFor(rooms[i]);
    if (time != null) {
      dated.add((rooms[i], time, i));
    } else {
      undated.add(rooms[i]);
    }
  }
  dated.sort((a, b) {
    final byTime = b.$2.compareTo(a.$2);
    return byTime != 0 ? byTime : a.$3.compareTo(b.$3);
  });
  return [...dated.map((e) => e.$1), ...undated];
}

/// An unread/read split of a room list, each side already recency-ordered.
typedef UnreadPartition = ({List<Room> unread, List<Room> read});

/// Splits [rooms] into an unread section (where [isUnread] is true) and a read
/// section (the rest), ordering each side newest-activity-first via
/// [sortRoomsByRecency]. Does not mutate [rooms].
UnreadPartition partitionByUnread(
  List<Room> rooms,
  bool Function(Room) isUnread,
  DateTime? Function(Room) activityFor,
) {
  final unread = <Room>[];
  final read = <Room>[];
  for (final room in rooms) {
    (isUnread(room) ? unread : read).add(room);
  }
  return (
    unread: sortRoomsByRecency(unread, activityFor),
    read: sortRoomsByRecency(read, activityFor),
  );
}
