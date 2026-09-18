import 'compute_display_messages.dart' show loadingMessageId;
import 'execution_tracker.dart';

/// Per-message UI expansion state for assistant responses — whether each
/// message's execution timeline, thinking block, and expandable source blocks
/// are open. Owned by `roomModule()`; outlives widget rebuilds, thread
/// switches, and room navigations within the room module.
///
/// Identity is `(roomId, messageId)`. Unlike the module's other per-server
/// caches this carries no `serverId`; adding it — for full isolation between
/// servers that share a `roomId` — is a possible future enhancement, deferred
/// because a collision also needs a shared `messageId` and would only swap
/// cosmetic expand/collapse state between two messages. [loadingMessageId] is
/// rejected, because it is reused across runs and state written under it would
/// leak into the next response.
///
/// A run that has not named its message yet writes into a pending slot
/// instead, claimed by the object that owns the run's execution tracker; when
/// the reply names itself, [adoptPending] moves that state onto the message.
/// Keying the slot to the tracker is what stops an unrelated tile scrolling
/// into view from taking it.
///
/// Retention is capped at [maxEntries]; once reached, the oldest-inserted
/// entry is evicted when a new one is created.
///
/// All access goes through a [MessageExpansion] handle obtained via
/// [forMessage] or [pendingFor]; the internal storage is private.
class MessageExpansions {
  /// Upper bound on entries retained. Eviction is FIFO (oldest-inserted).
  /// Chosen to comfortably exceed realistic session sizes (~50 typical,
  /// ~100-200 heavy use) so the cap almost never trips in practice.
  static const int maxEntries = 200;

  /// Second half of the key the pending slot is held under. Prefixed with NUL,
  /// which no backend message id carries, so it cannot collide with one.
  static const String _pendingKey = '\u0000pending';

  final Map<(String, String), _Expansion> _state = {};

  /// Who holds each room's pending slot, so only the run that wrote one can
  /// adopt it. Keyed by room because rooms can stream at once. Identity only;
  /// never called on.
  final Map<String, ExecutionTracker> _pendingOwners = {};

  /// Returns a handle bound to one message so callers pass `(roomId,
  /// messageId)` exactly once. Both are same-typed strings, so passing
  /// them in the wrong order at every access site is easy to get wrong.
  MessageExpansion forMessage(String roomId, String messageId) {
    assert(
      messageId != loadingMessageId,
      'MessageExpansions must not be keyed by loadingMessageId',
    );
    return MessageExpansion._(this, (roomId, messageId));
  }

  /// The handle a tile keys on: the pending slot while [owner]'s run has not
  /// named its message, and that message's own once it has — carrying across
  /// whatever the slot was holding.
  MessageExpansion forTile(
    ExecutionTracker owner,
    String roomId,
    String messageId,
  ) {
    if (messageId == loadingMessageId) return pendingFor(owner, roomId);
    adoptPending(owner, roomId, messageId);
    return forMessage(roomId, messageId);
  }

  /// Returns the handle for a run that has not named its message yet, owned
  /// by [owner] — the run's execution tracker, which survives the message
  /// being named and so identifies the same run afterwards. A different owner
  /// starts the slot over: the previous run's state was either adopted or
  /// abandoned with the run.
  MessageExpansion pendingFor(ExecutionTracker owner, String roomId) {
    if (!identical(_pendingOwners[roomId], owner)) {
      _pendingOwners[roomId] = owner;
      _state.remove((roomId, _pendingKey));
    }
    return MessageExpansion._(this, (roomId, _pendingKey));
  }

  /// Moves what [owner]'s run wrote while unnamed onto [messageId].
  ///
  /// A no-op unless [owner] holds that room's slot, so a tile mounting for
  /// some other message — one scrolled back into view mid-run — cannot take
  /// it. The slot is released either way: it belongs to the reply that just
  /// arrived.
  ///
  /// Adds to whatever [messageId] already holds rather than replacing it:
  /// both are things the user opened, one before the run and one during it.
  /// Nothing open means nothing written, so an untouched slot leaves no entry.
  void adoptPending(ExecutionTracker owner, String roomId, String messageId) {
    if (!identical(_pendingOwners[roomId], owner)) return;
    _pendingOwners.remove(roomId);
    final pending = _state.remove((roomId, _pendingKey));
    if (pending == null) return;
    // Written through a handle so the retention cap applies to this entry as
    // it does to any other.
    final adopted = MessageExpansion._(this, (roomId, messageId));
    if (pending.timeline) adopted.timelineExpanded = true;
    if (pending.thinking) adopted.thinkingExpanded = true;
    for (final source in pending.sources) {
      adopted.setSourceExpanded(source, true);
    }
  }

  /// Debug/test probe: returns whether any state has been written under
  /// `(roomId, messageId)`. Exposed by convention for tests — not enforced;
  /// production code has no reason to introspect the store directly.
  bool debugHasStateFor(String roomId, String messageId) =>
      _state.containsKey((roomId, messageId));
}

class _Expansion {
  bool timeline = false;
  bool thinking = false;
  final Set<String> sources = {};
}

/// A view of [MessageExpansions] bound to a single `(roomId, messageId)`.
/// Obtain via [MessageExpansions.forMessage].
class MessageExpansion {
  MessageExpansion._(this._owner, this._key);

  final MessageExpansions _owner;
  final (String, String) _key;

  _Expansion? get _entry => _owner._state[_key];
  _Expansion _ensureEntry() {
    final map = _owner._state;
    final existing = map[_key];
    if (existing != null) return existing;
    if (map.length >= MessageExpansions.maxEntries) {
      map.remove(map.keys.first);
    }
    return map[_key] = _Expansion();
  }

  bool get timelineExpanded => _entry?.timeline ?? false;
  set timelineExpanded(bool value) => _ensureEntry().timeline = value;

  bool get thinkingExpanded => _entry?.thinking ?? false;
  set thinkingExpanded(bool value) => _ensureEntry().thinking = value;

  bool isSourceExpanded(String sourceKey) =>
      _entry?.sources.contains(sourceKey) ?? false;

  void setSourceExpanded(String sourceKey, bool value) {
    if (value) {
      _ensureEntry().sources.add(sourceKey);
      return;
    }
    _entry?.sources.remove(sourceKey);
  }

  void toggleSource(String sourceKey) =>
      setSourceExpanded(sourceKey, !isSourceExpanded(sourceKey));
}
