import 'package:meta/meta.dart';

/// Context provided to extension factories to allow per-room/per-server
/// customization of tools and resources.
@immutable
class SessionContext {
  const SessionContext({
    required this.serverId,
    required this.roomId,
  });

  /// The ID of the Soliplex server this session belongs to.
  final String serverId;

  /// The ID of the room where this session is active.
  final String roomId;

  @override
  String toString() => 'SessionContext(serverId: $serverId, roomId: $roomId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionContext &&
          runtimeType == other.runtimeType &&
          serverId == other.serverId &&
          roomId == other.roomId;

  @override
  int get hashCode => serverId.hashCode ^ roomId.hashCode;
}
