import 'package:soliplex_client/soliplex_client.dart';

/// Persists per-thread document filter selections across navigation.
///
/// Keyed by (serverId, roomId, threadId) so selections survive room switches
/// and stay isolated per server — two servers can assign the same roomId, and a
/// user switch on one server must not disturb another server's selections.
/// Lives above RoomScreen in the dependency graph — created once at the module
/// level and injected via constructor.
class DocumentSelections {
  final _selections = <(String, String, String?), Set<RagDocument>>{};

  Set<RagDocument> get(String serverId, String roomId, String? threadId) =>
      _selections[(serverId, roomId, threadId)] ?? const {};

  void set(
    String serverId,
    String roomId,
    String? threadId,
    Set<RagDocument> docs,
  ) {
    final key = (serverId, roomId, threadId);
    if (docs.isEmpty) {
      _selections.remove(key);
    } else {
      _selections[key] = docs;
    }
  }

  /// Drops the selection for a deleted thread.
  void clearThread(String serverId, String roomId, String threadId) {
    _selections.remove((serverId, roomId, threadId));
  }

  /// Drops every selection for [serverId], so a different user signing in on
  /// that server doesn't inherit the prior user's document filters, while
  /// leaving other servers' selections intact.
  void clearServer(String serverId) {
    _selections.removeWhere((key, _) => key.$1 == serverId);
  }

  /// Moves the selection from the null-thread key to [threadId].
  ///
  /// Used when a user selects documents before a thread exists, then
  /// a thread is created implicitly by sending a message.
  void migrateToThread(String serverId, String roomId, String threadId) {
    final pending = _selections.remove((serverId, roomId, null));
    if (pending != null && pending.isNotEmpty) {
      _selections[(serverId, roomId, threadId)] = pending;
    }
  }
}
