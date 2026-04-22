import 'compute_display_messages.dart' show loadingMessageId;

/// Per-message UI expansion state for assistant responses — whether each
/// message's execution timeline, thinking block, and activity source rows
/// are open. Owned by `roomModule()`; outlives widget rebuilds, thread
/// switches, and room navigations within the room module.
///
/// Identity is `(roomId, messageId)`. [loadingMessageId] is rejected,
/// because it is reused across runs and state written under it would
/// leak into the next response.
///
/// Retention is capped at [maxEntries]; once reached, the oldest-inserted
/// entry is evicted when a new one is created.
///
/// All access goes through a [MessageExpansion] handle obtained via
/// [forMessage]; the internal storage is private.
class MessageExpansions {
  /// Upper bound on entries retained. Eviction is FIFO (oldest-inserted).
  /// Chosen to comfortably exceed realistic session sizes (~50 typical,
  /// ~100-200 heavy use) so the cap almost never trips in practice.
  static const int maxEntries = 200;

  final Map<(String, String), _Expansion> _state = {};

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

  bool isSourceExpanded(String activityId) =>
      _entry?.sources.contains(activityId) ?? false;

  void setSourceExpanded(String activityId, bool value) {
    if (value) {
      _ensureEntry().sources.add(activityId);
      return;
    }
    _entry?.sources.remove(activityId);
  }

  void toggleSource(String activityId) =>
      setSourceExpanded(activityId, !isSourceExpanded(activityId));
}
