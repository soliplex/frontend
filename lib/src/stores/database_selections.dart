/// Persists per-thread RAG database selections across navigation.
///
/// The database twin of `DocumentSelections`, keyed the same way
/// (serverId, roomId, threadId) for the same reasons: selections survive room
/// switches and stay isolated per server. A selection is the set of database
/// names a thread's searches cover; an absent entry means every database, which
/// is the backend's default and what a fresh thread starts on.
///
/// Lives above RoomScreen in the dependency graph — created once at the module
/// level and injected via constructor.
class DatabaseSelections {
  final _selections = <_Key, Set<String>>{};

  /// The names selected for the thread, or empty for "every database".
  Set<String> get({
    required String serverId,
    required String roomId,
    required String? threadId,
  }) =>
      _selections[(serverId: serverId, roomId: roomId, threadId: threadId)] ??
      const {};

  /// Records [names] for the thread. An empty set is kept — it is a deliberate
  /// reset to "every database", which [seed] then leaves alone.
  void set({
    required String serverId,
    required String roomId,
    required String? threadId,
    required Set<String> names,
  }) {
    _selections[(serverId: serverId, roomId: roomId, threadId: threadId)] =
        Set.unmodifiable(names);
  }

  /// Records [names], read from the thread's history, only if the thread has
  /// no entry yet: a selection made while the history loaded — even a
  /// deliberate "every database", which reads as empty through [get] — wins.
  void seed({
    required String serverId,
    required String roomId,
    required String? threadId,
    required Set<String> names,
  }) {
    _selections.putIfAbsent(
      (serverId: serverId, roomId: roomId, threadId: threadId),
      () => Set.unmodifiable(names),
    );
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
  /// that server doesn't inherit the prior user's selections, while leaving
  /// other servers' selections intact.
  void clearServer(String serverId) {
    _selections.removeWhere((key, _) => key.serverId == serverId);
  }

  /// Moves the selection from the null-thread key to [threadId].
  ///
  /// Called when the room screen goes from no thread to a thread — normally
  /// the one the first send creates, but also one opened by auto-select, so a
  /// pick left unsent replaces that thread's own entry.
  void migrateToThread({
    required String serverId,
    required String roomId,
    required String threadId,
  }) {
    final pending = _selections
        .remove((serverId: serverId, roomId: roomId, threadId: null));
    if (pending != null) {
      _selections[(serverId: serverId, roomId: roomId, threadId: threadId)] =
          pending;
    }
  }
}

typedef _Key = ({String serverId, String roomId, String? threadId});
