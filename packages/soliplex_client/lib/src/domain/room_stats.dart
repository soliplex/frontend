import 'package:meta/meta.dart';

/// Activity statistics for a single room, scoped to the requesting user.
///
/// Mirrors one room's entry in the room stats endpoint payload. Intentionally
/// open-ended: the backend stats payload is expected to grow (message/thread
/// counts, token usage, ...), so new fields are added here rather than minting
/// a new model per metric. The room id is the map key in the endpoint payload,
/// so it is not duplicated as a field.
@immutable
class RoomStats {
  /// Creates room stats.
  RoomStats({
    this.lastActivity,
  }) : assert(
          lastActivity == null || lastActivity.isUtc,
          'lastActivity must be UTC',
        );

  /// Most recent activity in the room for the requesting user, in UTC, or
  /// `null` when there is none to report — the user has no activity in the
  /// room, or its timestamp was absent or unparseable.
  final DateTime? lastActivity;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RoomStats && other.lastActivity == lastActivity;
  }

  @override
  int get hashCode => lastActivity.hashCode;

  @override
  String toString() => 'RoomStats(lastActivity: $lastActivity)';
}
