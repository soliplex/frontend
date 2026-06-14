import 'package:meta/meta.dart';

/// Aggregate activity statistics for a single room.
///
/// Scoped to the requesting user's own threads. Intentionally open-ended:
/// the backend stats payload is expected to grow (message/thread counts,
/// token usage, ...), so new fields are added here rather than minting a
/// new model per metric.
@immutable
class RoomStats {
  /// Creates room stats.
  const RoomStats({
    required this.roomId,
    this.lastMessageAt,
  });

  /// ID of the room these stats describe.
  final String roomId;

  /// Timestamp of the most recent message turn in the room, or `null`
  /// when the user has no activity there.
  final DateTime? lastMessageAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RoomStats &&
        other.roomId == roomId &&
        other.lastMessageAt == lastMessageAt;
  }

  @override
  int get hashCode => Object.hash(roomId, lastMessageAt);

  @override
  String toString() =>
      'RoomStats(roomId: $roomId, lastMessageAt: $lastMessageAt)';
}
