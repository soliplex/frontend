import 'package:soliplex_client/soliplex_client.dart';

/// Persists per-thread document filter selections across navigation.
///
/// Keyed by (serverId, roomId, threadId) so selections survive room switches
/// and stay isolated per server — two servers can assign the same roomId, and a
/// user switch on one server must not disturb another server's selections.
/// Lives above RoomScreen in the dependency graph — created once at the module
/// level and injected via constructor.
class DocumentSelections {
  final _selections = <_Key, Set<RagDocument>>{};

  Set<RagDocument> get({
    required String serverId,
    required String roomId,
    required String? threadId,
  }) =>
      _selections[(serverId: serverId, roomId: roomId, threadId: threadId)] ??
      const {};

  void set({
    required String serverId,
    required String roomId,
    required String? threadId,
    required Set<RagDocument> docs,
  }) {
    final key = (serverId: serverId, roomId: roomId, threadId: threadId);
    if (docs.isEmpty) {
      _selections.remove(key);
    } else {
      _selections[key] = docs;
    }
  }

  /// Drops the selection for a deleted thread.
  void clearThread({
    required String serverId,
    required String roomId,
    required String threadId,
  }) {
    _selections
        .remove((serverId: serverId, roomId: roomId, threadId: threadId));
  }

  /// Drops every selection for [serverId], so a different user signing in on
  /// that server doesn't inherit the prior user's document filters, while
  /// leaving other servers' selections intact.
  void clearServer(String serverId) {
    _selections.removeWhere((key, _) => key.serverId == serverId);
  }

  /// Moves the selection from the null-thread key to [threadId].
  ///
  /// Used when a user selects documents before a thread exists, then
  /// a thread is created implicitly by sending a message.
  void migrateToThread({
    required String serverId,
    required String roomId,
    required String threadId,
  }) {
    final pending = _selections
        .remove((serverId: serverId, roomId: roomId, threadId: null));
    if (pending != null && pending.isNotEmpty) {
      _selections[(serverId: serverId, roomId: roomId, threadId: threadId)] =
          pending;
    }
  }
}

typedef _Key = ({String serverId, String roomId, String? threadId});
