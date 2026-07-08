import 'dart:async';

import 'package:soliplex_logging/soliplex_logging.dart';

import 'thread_read_markers.dart' show ThreadActivityKey;
import 'unread_boundary.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.anchor_tracker');

/// Owns the per-thread "last read message id" state behind the unread
/// "New messages" divider: loads it, snapshots the previous value when a
/// thread opens (frozen for the divider), and advances it as messages arrive.
///
/// Isolates the load/advance ordering — which must never persist a partial map
/// before the disk load merges other threads' anchors — so it can be unit-
/// tested independently of the room screen.
class AnchorTracker {
  AnchorTracker({
    required Future<Map<ThreadActivityKey, String>> Function() load,
    required Future<void> Function(Map<ThreadActivityKey, String>) save,
  })  : _load = load,
        _save = save;

  final Future<Map<ThreadActivityKey, String>> Function() _load;
  final Future<void> Function(Map<ThreadActivityKey, String>) _save;

  /// Escalates anchor-persistence logging from warning to error once this many
  /// consecutive writes have failed, so a systemic storage break (disk full,
  /// platform channel down) surfaces instead of degrading silently.
  static const _failureEscalationThreshold = 3;

  Map<ThreadActivityKey, String> _anchors = const {};
  _LoadState _loadState = _LoadState.pending;
  ThreadActivityKey? _currentKey;

  /// The anchor frozen for the open thread's divider, captured the moment its
  /// boundary resolves and left untouched as the thread advances. Null means
  /// "caught up" (no line). Only meaningful once [_loadState] leaves pending.
  String? _frozenAnchorId;

  /// Whether [_anchors] holds changes not yet written to disk. Survives a
  /// failed write so the pending change is retried on the next flush instead
  /// of being lost, and decouples "needs persisting" from the open thread's id.
  bool _dirty = false;

  /// Guards [_flush] so only one write is ever in flight: overlapping saves
  /// against the shared [_anchors] map could otherwise persist a stale snapshot
  /// after a newer one.
  bool _flushing = false;

  int _consecutiveFailures = 0;

  /// The frozen read boundary for the open thread, derived from the load state
  /// so the pending-vs-resolved distinction has a single source of truth.
  UnreadBoundary get boundary => switch (_loadState) {
        _LoadState.pending => const BoundaryPending(),
        _LoadState.loaded ||
        _LoadState.failed =>
          BoundaryResolved(_frozenAnchorId),
      };

  /// Snapshots the previous anchor for [key] BEFORE any advance. Loaded: the
  /// in-memory value is authoritative. Failed: degrade to "no line" so the
  /// divider doesn't wait on a load that will never arrive. Pending:
  /// [loadFromDisk] resolves it from the disk value.
  void beginThread(ThreadActivityKey key) {
    _currentKey = key;
    switch (_loadState) {
      case _LoadState.loaded:
        _frozenAnchorId = _anchors[key];
      case _LoadState.failed:
        _frozenAnchorId = null;
      case _LoadState.pending:
        break; // loadFromDisk resolves the boundary from the disk value.
    }
  }

  /// Loads anchors from storage, merging under any value advanced in-memory
  /// before the load completed (so other threads' anchors are preserved), and
  /// resolves the frozen boundary for the open thread from the DISK value.
  /// Flushes the merged map so a pre-load advance is persisted without
  /// dropping the other threads.
  ///
  /// On a load failure the boundary degrades to a resolved "no line" so the
  /// timeline stops waiting, but persistence stays disabled: we read nothing,
  /// so writing the partial in-memory map would clobber the unread threads.
  Future<void> loadFromDisk() async {
    final Map<ThreadActivityKey, String> loaded;
    try {
      loaded = await _load();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to load thread anchors',
        error: error,
        stackTrace: stackTrace,
      );
      // Boundary now derives to a resolved "no line" so the timeline stops
      // waiting; persistence stays disabled because we read nothing and would
      // clobber the unread threads. A pre-load advance leaves [_dirty] true with
      // no path to flush — that is intentional, not a lost write: the in-memory
      // advance genuinely differs from disk, but writing it without the other
      // threads' anchors is the clobber we are avoiding.
      _loadState = _LoadState.failed;
      return;
    }
    _anchors = {...loaded, ..._anchors};
    final wasPending = _loadState == _LoadState.pending;
    _loadState = _LoadState.loaded;
    final key = _currentKey;
    if (key != null && wasPending) {
      // Freeze the DISK value for the divider: a pre-load advance may have
      // moved the in-memory value, but the line marks where the user left off.
      _frozenAnchorId = loaded[key];
    }
    // A value advanced before the load completed left us dirty; flush the
    // merged map now so it is written without dropping the other threads.
    if (_dirty) unawaited(_flush());
  }

  /// Advances the open thread's anchor to [lastRealId] (already filtered for
  /// the ephemeral loading sentinel by the caller). No-op when there is no
  /// open thread or the id is null/unchanged. Persists only once anchors are
  /// loaded — a partial map written earlier would clobber the other threads'
  /// anchors — and re-flushes any change a prior write failed to persist.
  void advance(String? lastRealId) {
    final key = _currentKey;
    assert(key != null, 'advance called before beginThread');
    if (key == null) return;
    if (lastRealId != null && _anchors[key] != lastRealId) {
      _anchors = {..._anchors, key: lastRealId};
      _dirty = true;
    }
    // Until the disk load completes, [loadFromDisk]'s flush owns persistence; a
    // write here would clobber the threads we haven't read yet.
    if (_loadState != _LoadState.loaded) return;
    if (_dirty) unawaited(_flush());
  }

  /// Drops [threadId]'s anchor (a deleted thread) from the in-memory map so a
  /// later flush doesn't re-persist it. Only flushes once loaded — the exit-time
  /// prune that calls this runs against an already-loaded tracker, so the
  /// in-flight-load merge that could otherwise re-add the entry isn't reached in
  /// practice. The disk store's all-users `clearThread` is the source of truth.
  void clearThread(String threadId) {
    final next = {..._anchors}..removeWhere((k, _) => k.threadId == threadId);
    if (next.length == _anchors.length) return;
    _anchors = next;
    _dirty = true;
    if (_loadState != _LoadState.loaded) return;
    unawaited(_flush());
  }

  /// Writes [_anchors] while any change is pending, one write at a time. Keeps
  /// [_dirty] set on failure so the change is retried by the next flush rather
  /// than lost, and escalates the log once failures persist.
  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_dirty) {
        _dirty = false;
        final snapshot = Map.of(_anchors);
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

  /// Best-effort persist of any pending advance before the tracker is
  /// discarded, so a write the retry loop was about to re-attempt survives a
  /// room change. Callers fire this without awaiting (a [State.dispose] has no
  /// async gap), so during app shutdown the event loop may tear down before
  /// the [_flush] completes and the pending advance is dropped — it reappears
  /// on next launch. Guarded to the loaded state: a pending or failed load must
  /// never write a partial map, which would clobber the unread threads it never
  /// read.
  Future<void> dispose() async {
    if (_loadState == _LoadState.loaded && _dirty) await _flush();
  }

  void _logPersistFailure(Object error, StackTrace stackTrace) {
    if (_consecutiveFailures >= _failureEscalationThreshold) {
      _logger.error(
        'Failed to persist thread anchors '
        '($_consecutiveFailures consecutive failures; unread dividers may be '
        'stale until a write succeeds)',
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      _logger.warning(
        'Failed to persist thread anchors',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

enum _LoadState { pending, loaded, failed }
