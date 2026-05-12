import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';

/// Sentinel key for the execution tracker created before a message ID is known.
const kAwaitingTrackerKey = '_awaiting';

/// Manages execution trackers keyed by message ID.
///
/// Handles the tracker lifecycle: creation on first streaming event,
/// re-keying when a message ID becomes available, and freezing when
/// a run terminates.
class TrackerRegistry {
  TrackerRegistry({required Logger logger}) : _logger = logger;

  final Map<String, ExecutionTracker> _trackers = {};
  String? _activeId;
  final Logger _logger;

  Map<String, ExecutionTracker> get trackers => .unmodifiable(_trackers);

  /// Update tracker state based on the current streaming state.
  ///
  /// [events] is the execution event signal to subscribe a new tracker to,
  /// only used when a tracker needs to be created.
  void onStreaming(
    StreamingState streaming,
    ReadonlySignal<ExecutionEvent?> events,
  ) {
    switch (streaming) {
      case TextStreaming(:final messageId):
        if (_activeId == messageId) return;
        if (_activeId == kAwaitingTrackerKey) {
          final tracker = _trackers.remove(kAwaitingTrackerKey);
          if (tracker != null) {
            _trackers[messageId] = tracker;
          }
        } else {
          _freezeActive();
          _trackers[messageId] = ExecutionTracker(
            executionEvents: events,
            logger: _logger,
          );
        }
        _activeId = messageId;
      case AwaitingText():
        if (_activeId != null) return;
        _activeId = kAwaitingTrackerKey;
        _trackers[kAwaitingTrackerKey] = ExecutionTracker(
          executionEvents: events,
          logger: _logger,
        );
    }
  }

  /// Freeze the active tracker when a run reaches a terminal state.
  void onRunTerminated() {
    _freezeActive();
  }

  /// Renames the awaiting tracker to [key] so that the tile rendered for
  /// a synthesized "no response" message attaches to the same tracker
  /// that captured the run's thinking.
  ///
  /// No-op when the awaiting tracker doesn't exist or [key] is the same
  /// as the awaiting key. Called by `ExecutionTrackerExtension` on
  /// terminal `RunState` transitions for runs that ended with buffered
  /// thinking but no assistant text.
  ///
  /// When no awaiting tracker is present the synthesized [NoResponseTile]
  /// still renders its `thinkingText` field, but no execution-step
  /// timeline attaches; the warning makes that divergence observable.
  void renameAwaitingTo(String key) {
    if (key == kAwaitingTrackerKey) return;
    final tracker = _trackers.remove(kAwaitingTrackerKey);
    if (tracker == null) {
      _logger.warning(
        'No awaiting tracker for renameAwaitingTo; NoResponseTile will '
        'render thinking but lack the execution-step timeline.',
        attributes: {'targetKey': key},
      );
      return;
    }
    final clobbered = _trackers[key];
    if (clobbered != null) {
      // `seedHistorical` declared "live always wins over historical", but
      // an unguarded overwrite here loses any tracker (live or historical)
      // already bound to the same key. Freeze the loser so its
      // subscription is released and warn so the divergence is observable.
      clobbered.freeze();
      _logger.warning(
        'renameAwaitingTo overwrote an existing tracker at the target key.',
        attributes: {'targetKey': key},
      );
    }
    _trackers[key] = tracker;
    if (_activeId == kAwaitingTrackerKey) {
      _activeId = key;
    }
  }

  /// Bulk-inserts already-frozen trackers produced from a loaded thread's
  /// history. Existing entries with the same key are not overwritten —
  /// a live tracker always wins over a historical one.
  void seedHistorical(Map<String, ExecutionTracker> historical) {
    for (final entry in historical.entries) {
      _trackers.putIfAbsent(entry.key, () => entry.value);
    }
  }

  void _freezeActive() {
    if (_activeId != null) {
      _trackers[_activeId!]?.freeze();
      _activeId = null;
    }
  }

  void dispose() {
    for (final tracker in _trackers.values) {
      tracker.dispose();
    }
    _trackers.clear();
  }
}
