import 'execution_tracker.dart';
import 'lay_out_timeline.dart' show loadingMessageId;

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
/// leak into the next response. The loading tile keeps its state by the band
/// it shows instead, through [forBand].
///
/// Retention is capped at [maxEntries]; once reached, the oldest-inserted
/// entry is evicted when a new one is created. State held for a band on the
/// loading tile is released with the band, and counts against [maxEntries]
/// only once a message takes it.
///
/// All access goes through a [MessageExpansion] handle obtained via
/// [forMessage] or [forBand]; the internal storage is private.
class MessageExpansions {
  /// Upper bound on entries retained. Eviction is FIFO (oldest-inserted).
  /// Chosen to comfortably exceed realistic session sizes (~50 typical,
  /// ~100-200 heavy use) so the cap almost never trips in practice.
  static const int maxEntries = 200;

  final Map<(String, String), _Expansion> _state = {};

  /// State given to a band while it sits on the loading tile, before a
  /// message speaks for it. Keyed by the band: an object no other reply's tile
  /// shows, and the same object once it moves to the reply's tile.
  final Expando<_Expansion> _unclaimed = Expando();

  /// Returns a handle bound to one message so callers pass `(roomId,
  /// messageId)` exactly once. Both are same-typed strings, so passing
  /// them in the wrong order at every access site is easy to get wrong.
  MessageExpansion forMessage(String roomId, String messageId) {
    assert(
      messageId != loadingMessageId,
      'MessageExpansions must not be keyed by loadingMessageId',
    );
    return _forKey((roomId, messageId));
  }

  /// Returns a handle for [band] as shown on the tile of [messageId].
  ///
  /// On the loading tile the state belongs to the band. A message with no
  /// state of its own takes the state its band was given there, so what the
  /// reader opened while the agent worked stays open when the reply starts.
  MessageExpansion forBand(
    String roomId,
    String messageId,
    ExecutionTracker band,
  ) {
    if (messageId == loadingMessageId) {
      return MessageExpansion._(
        read: () => _unclaimed[band],
        ensure: () => _unclaimed[band] ??= _Expansion(),
      );
    }
    final key = (roomId, messageId);
    if (!_state.containsKey(key)) {
      final carried = _unclaimed[band];
      if (carried != null) _insert(key, carried);
    }
    return _forKey(key);
  }

  MessageExpansion _forKey((String, String) key) => MessageExpansion._(
        read: () => _state[key],
        ensure: () => _state[key] ?? _insert(key, _Expansion()),
      );

  _Expansion _insert((String, String) key, _Expansion entry) {
    if (_state.length >= maxEntries) _state.remove(_state.keys.first);
    return _state[key] = entry;
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

/// A view of [MessageExpansions] bound to one message, or to one band on the
/// loading tile. Obtain via [MessageExpansions.forMessage] or
/// [MessageExpansions.forBand].
class MessageExpansion {
  MessageExpansion._({
    required _Expansion? Function() read,
    required _Expansion Function() ensure,
  })  : _read = read,
        _ensure = ensure;

  final _Expansion? Function() _read;
  final _Expansion Function() _ensure;

  _Expansion? get _entry => _read();
  _Expansion _ensureEntry() => _ensure();

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
