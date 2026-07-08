import 'dart:async';

import 'package:soliplex_logging/soliplex_logging.dart';

import 'thread_read_markers.dart' show ThreadActivityKey;

final Logger _logger =
    LogManager.instance.getLogger('soliplex.thread_read_tracker');

/// Owns the current room's per-thread "last seen" read markers: loads them,
/// stamps a thread read, and persists the room's blob.
///
/// The topological twin of [AnchorTracker] for the read-dot store — same
/// load/merge/flush lifecycle, minus the divider concept (no frozen boundary).
/// One instance per room, recreated on room change (like the anchor tracker), so
/// its coordinates are captured at construction and never shift under an
/// in-flight write when the widget advances to a new room.
class ThreadReadTracker {
  ThreadReadTracker({
    required Future<Map<ThreadActivityKey, DateTime>> Function() load,
    required Future<void> Function(Map<ThreadActivityKey, DateTime>) save,
  })  : _load = load,
        _save = save;

  final Future<Map<ThreadActivityKey, DateTime>> Function() _load;
  final Future<void> Function(Map<ThreadActivityKey, DateTime>) _save;

  /// Escalates persistence logging from warning to error once this many
  /// consecutive writes have failed, so a systemic storage break (disk full,
  /// platform channel down) surfaces instead of degrading silently.
  static const _failureEscalationThreshold = 3;

  Map<ThreadActivityKey, DateTime> _markers = const {};
  _LoadState _loadState = _LoadState.pending;

  /// Whether [_markers] holds a change not yet written to disk. Survives a failed
  /// write so the pending change is retried on the next flush instead of lost.
  bool _dirty = false;

  /// Guards [_flush] so only one write is ever in flight: overlapping saves
  /// against the shared [_markers] map could otherwise persist a stale snapshot
  /// after a newer one.
  bool _flushing = false;

  int _consecutiveFailures = 0;

  /// The current in-memory markers, for the room-read rollup queries. All keys
  /// share this tracker's captured (serverId, roomId).
  Map<ThreadActivityKey, DateTime> get markers => _markers;

  /// Loads markers from storage, merging UNDER any value stamped in-memory before
  /// the load completed (so a pre-load stamp isn't dropped and the other threads'
  /// markers are preserved). Flushes the merged map if a pre-load stamp left it
  /// dirty.
  ///
  /// On a load failure persistence stays disabled: we read nothing, so writing
  /// the partial in-memory map would clobber the threads we never read.
  Future<void> loadFromDisk() async {
    final Map<ThreadActivityKey, DateTime> loaded;
    try {
      loaded = await _load();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to load thread read markers',
        error: error,
        stackTrace: stackTrace,
      );
      // A pre-load stamp leaves [_dirty] true with no path to flush — intentional,
      // not a lost write: writing it without the other threads' markers is the
      // clobber we are avoiding.
      _loadState = _LoadState.failed;
      return;
    }
    _markers = {...loaded, ..._markers};
    _loadState = _LoadState.loaded;
    // A stamp before the load completed left us dirty; flush the merged map now
    // so it is written without dropping the other threads.
    if (_dirty) unawaited(_flush());
  }

  /// Stamps [key]'s read marker to [at]. Persists only once markers are loaded —
  /// a partial map written earlier would clobber the other threads — and
  /// re-flushes any change a prior write failed to persist.
  void stamp(ThreadActivityKey key, DateTime at) {
    if (_markers[key] == at) return;
    _markers = {..._markers, key: at};
    _dirty = true;
    // Until the disk load completes, [loadFromDisk]'s flush owns persistence; a
    // write here would clobber the threads we haven't read yet.
    if (_loadState != _LoadState.loaded) return;
    unawaited(_flush());
  }

  /// Drops [threadId]'s marker (a deleted thread) from the in-memory map so a
  /// later flush doesn't re-persist it. Only flushes once loaded — the exit-time
  /// prune that calls this runs against an already-loaded tracker, so the
  /// in-flight-load merge that could otherwise re-add the entry isn't reached in
  /// practice. The disk store's all-users `clearThread` is the source of truth
  /// for the removal.
  void clearThread(String threadId) {
    final next = {..._markers}..removeWhere((k, _) => k.threadId == threadId);
    if (next.length == _markers.length) return;
    _markers = next;
    _dirty = true;
    if (_loadState != _LoadState.loaded) return;
    unawaited(_flush());
  }

  /// Writes [_markers] while any change is pending, one write at a time. Keeps
  /// [_dirty] set on failure so the change is retried by the next flush rather
  /// than lost, and escalates the log once failures persist.
  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_dirty) {
        _dirty = false;
        final snapshot = Map.of(_markers);
        try {
          await _save(snapshot);
          _consecutiveFailures = 0;
        } catch (error, stackTrace) {
          _dirty = true;
          _consecutiveFailures++;
          _logPersistFailure(error, stackTrace);
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// Best-effort persist of any pending stamp before the tracker is discarded, so
  /// a write the retry loop was about to re-attempt survives a room change.
  /// Callers fire this without awaiting (a [State.dispose] has no async gap).
  /// Guarded to the loaded state: a pending or failed load must never write a
  /// partial map, which would clobber the threads it never read. When a stamp
  /// lands before the load resolves and the tracker is disposed mid-load, the
  /// orphaned [loadFromDisk] still merges and flushes it.
  Future<void> dispose() async {
    if (_loadState == _LoadState.loaded && _dirty) await _flush();
  }

  void _logPersistFailure(Object error, StackTrace stackTrace) {
    if (_consecutiveFailures >= _failureEscalationThreshold) {
      _logger.error(
        'Failed to persist thread read markers '
        '($_consecutiveFailures consecutive failures; unread dots may be stale '
        'until a write succeeds)',
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      _logger.warning(
        'Failed to persist thread read markers',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

enum _LoadState { pending, loaded, failed }
