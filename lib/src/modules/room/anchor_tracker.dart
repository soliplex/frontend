import 'dart:async';

import 'package:soliplex_logging/soliplex_logging.dart';

import 'thread_anchor_storage.dart';
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
    Future<Map<ThreadActivityKey, String>> Function()? load,
    Future<void> Function(Map<ThreadActivityKey, String>)? save,
  })  : _load = load ?? ThreadAnchorStorage.load,
        _save = save ?? ThreadAnchorStorage.save;

  final Future<Map<ThreadActivityKey, String>> Function() _load;
  final Future<void> Function(Map<ThreadActivityKey, String>) _save;

  Map<ThreadActivityKey, String> _anchors = const {};
  _LoadState _loadState = _LoadState.pending;
  ThreadActivityKey? _currentKey;
  UnreadBoundary _boundary = const BoundaryPending();

  /// The current thread's last id whose write succeeded (or is in flight),
  /// used to skip redundant saves. Rolled back when a write fails so the next
  /// advance retries it instead of treating it as already persisted.
  String? _lastPersistedAnchorId;

  /// The frozen read boundary for the open thread, captured before this visit
  /// advances it. Drives the divider.
  UnreadBoundary get boundary => _boundary;

  /// Snapshots the previous anchor for [key] BEFORE any advance. Loaded: the
  /// in-memory value is authoritative. Failed: degrade to "no line" so the
  /// divider doesn't wait on a load that will never arrive. Pending:
  /// [loadFromDisk] resolves it from the disk value.
  void beginThread(ThreadActivityKey key) {
    _currentKey = key;
    _boundary = switch (_loadState) {
      _LoadState.loaded => BoundaryResolved(_anchors[key]),
      _LoadState.failed => const BoundaryResolved(null),
      _LoadState.pending => const BoundaryPending(),
    };
    _lastPersistedAnchorId = _anchors[key];
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
      _loadState = _LoadState.failed;
      if (_boundary is BoundaryPending) {
        _boundary = const BoundaryResolved(null);
      }
      return;
    }
    _anchors = {...loaded, ..._anchors};
    _loadState = _LoadState.loaded;
    final key = _currentKey;
    if (key != null && _boundary is BoundaryPending) {
      _boundary = BoundaryResolved(loaded[key]);
    }
    // Persist the merged map so a value advanced before the load completed is
    // written without dropping the other threads' anchors. Record the flushed
    // id only on success so the first advance carrying that same id does not
    // trigger a redundant write, while a failed flush stays retryable.
    final flushed =
        await _persist('Failed to flush merged thread anchors after load');
    if (flushed && key != null) {
      _lastPersistedAnchorId = _anchors[key];
    }
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
    _anchors = {..._anchors, key: lastRealId};
    // Until the disk load completes, [loadFromDisk]'s flush owns persistence; a
    // write here would clobber the threads we haven't read yet.
    if (_loadState != _LoadState.loaded) return;
    final previousPersistedId = _lastPersistedAnchorId;
    _lastPersistedAnchorId = lastRealId;
    unawaited(
      _persist('Failed to persist advanced thread anchor').then((persisted) {
        // Roll back so the next advance retries, unless a later advance already
        // moved the marker past this id.
        if (!persisted && _lastPersistedAnchorId == lastRealId) {
          _lastPersistedAnchorId = previousPersistedId;
        }
      }),
    );
  }

  Future<bool> _persist(String failureMessage) async {
    try {
      await _save(_anchors);
      return true;
    } catch (error, stackTrace) {
      _logger.warning(
        failureMessage,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}

enum _LoadState { pending, loaded, failed }
