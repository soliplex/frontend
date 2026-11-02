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
  final _searched = <_Key, Set<String>>{};

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

  /// The databases the thread has already searched, or null when none is
  /// recorded. Empty means every database.
  ///
  /// A thread's set may grow after its first message but never shrink: a
  /// database dropped from it would leave the earlier answers' citations
  /// naming a database the thread no longer covers. The selection may differ
  /// from this only by additions not yet sent, which can still be undone.
  Set<String>? searched({
    required String serverId,
    required String roomId,
    required String threadId,
  }) =>
      _searched[(serverId: serverId, roomId: roomId, threadId: threadId)];

  /// Adds [names] — what a send carried, or what the thread's history says
  /// its runs asked for — to what the thread has searched. Empty is every
  /// database, which absorbs any list, so the record only ever grows: a send
  /// and a history load can arrive in either order.
  void recordSearched({
    required String serverId,
    required String roomId,
    required String threadId,
    required Set<String> names,
  }) {
    final key = (serverId: serverId, roomId: roomId, threadId: threadId);
    final previous = _searched[key];
    _searched[key] = Set.unmodifiable(
      previous == null
          ? names
          : previous.isEmpty || names.isEmpty
              ? const <String>{}
              : {...previous, ...names},
    );
  }

  /// Drops the selection for a deleted thread.
  void clearThread({
    required String serverId,
    required String roomId,
    required String threadId,
  }) {
    final key = (serverId: serverId, roomId: roomId, threadId: threadId);
    _selections.remove(key);
    _searched.remove(key);
  }

  /// Drops every selection for [serverId], so a different user signing in on
  /// that server doesn't inherit the prior user's selections, while leaving
  /// other servers' selections intact.
  void clearServer(String serverId) {
    _selections.removeWhere((key, _) => key.serverId == serverId);
    _searched.removeWhere((key, _) => key.serverId == serverId);
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
