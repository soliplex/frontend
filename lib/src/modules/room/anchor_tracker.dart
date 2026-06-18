import 'dart:developer' as dev;

import 'thread_anchor_storage.dart';
import 'thread_read_markers.dart' show ThreadActivityKey;

/// Owns the per-thread "last read message id" state behind the unread
/// "New messages" divider: loads it, snapshots the previous value when a
/// thread opens (frozen for the divider), and advances it as messages arrive.
///
/// Extracted from the room screen so the load/advance ordering — which must
/// never persist a partial map before the disk load merges other threads'
/// anchors — is unit-testable.
class AnchorTracker {
  AnchorTracker({
    Future<Map<ThreadActivityKey, String>> Function()? load,
    Future<void> Function(Map<ThreadActivityKey, String>)? save,
  })  : _load = load ?? ThreadAnchorStorage.load,
        _save = save ?? ThreadAnchorStorage.save;

  final Future<Map<ThreadActivityKey, String>> Function() _load;
  final Future<void> Function(Map<ThreadActivityKey, String>) _save;

  Map<ThreadActivityKey, String> _anchors = const {};
  bool _anchorsLoaded = false;
  ThreadActivityKey? _currentKey;
  String? _frozenBoundaryId;
  bool _boundaryResolved = false;
  String? _lastPersistedAnchorId;

  /// The frozen first-seen anchor for the open thread (the previous value,
  /// captured before this visit advances it). Drives the divider.
  String? get frozenBoundaryId => _frozenBoundaryId;

  /// Whether [frozenBoundaryId] reflects a resolved read state (vs. the anchor
  /// not having loaded yet).
  bool get boundaryResolved => _boundaryResolved;

  /// Snapshots the previous anchor for [key] BEFORE any advance. Warm
  /// (anchors loaded): the in-memory value is authoritative and resolved.
  /// Cold: leave unresolved; [loadFromDisk] resolves it from the disk value.
  void beginThread(ThreadActivityKey key) {
    _currentKey = key;
    if (_anchorsLoaded) {
      _frozenBoundaryId = _anchors[key];
      _boundaryResolved = true;
    } else {
      _frozenBoundaryId = null;
      _boundaryResolved = false;
    }
    _lastPersistedAnchorId = _anchors[key];
  }

  /// Loads anchors from storage, merging under any value advanced in-memory
  /// before the load completed (so other threads' anchors are preserved), and
  /// resolves the frozen boundary for the open thread from the DISK value.
  /// Flushes the merged map so a pre-load advance is persisted without
  /// dropping the other threads.
  Future<void> loadFromDisk() async {
    final Map<ThreadActivityKey, String> loaded;
    try {
      loaded = await _load();
    } catch (error, stackTrace) {
      dev.log(
        'Failed to load thread anchors',
        error: error,
        stackTrace: stackTrace,
        name: 'AnchorTracker',
        level: 900,
      );
      return;
    }
    _anchors = {...loaded, ..._anchors};
    _anchorsLoaded = true;
    final key = _currentKey;
    if (key != null && !_boundaryResolved) {
      _frozenBoundaryId = loaded[key];
      _boundaryResolved = true;
      // The flush below persists _anchors[key]; record it so the first advance
      // carrying that same id does not trigger a redundant write.
      _lastPersistedAnchorId ??= _anchors[key];
    }
    // Persist the merged map so a value advanced before the load completed is
    // written without dropping the other threads' anchors.
    await _persist('Failed to flush merged thread anchors after load');
  }

  /// Advances the open thread's anchor to [lastRealId] (already filtered for
  /// the ephemeral loading sentinel by the caller). No-op when there is no
  /// open thread, the id is null, or it is unchanged. Persists only once
  /// anchors are loaded — a partial map written earlier would clobber the
  /// other threads' anchors.
  void advance(String? lastRealId) {
    final key = _currentKey;
    if (key == null) return;
    if (lastRealId == null || lastRealId == _lastPersistedAnchorId) return;
    _lastPersistedAnchorId = lastRealId;
    _anchors = {..._anchors, key: lastRealId};
    if (_anchorsLoaded) {
      _persist('Failed to persist advanced thread anchor');
    }
  }

  Future<void> _persist(String failureMessage) {
    return _save(_anchors).catchError((Object error, StackTrace stackTrace) {
      dev.log(
        failureMessage,
        error: error,
        stackTrace: stackTrace,
        name: 'AnchorTracker',
        level: 900,
      );
    });
  }
}
