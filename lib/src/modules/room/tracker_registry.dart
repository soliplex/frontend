import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';

/// Sentinel key for the execution tracker created before a message ID is known.
const awaitingTrackerKey = '_awaiting';

/// Manages execution trackers keyed by message ID.
///
/// Handles the tracker lifecycle: creation on first streaming event,
/// re-keying when a message ID becomes available, and freezing when
/// a run terminates.
class TrackerRegistry {
  final Map<String, ExecutionTracker> _trackers = {};
  String? _activeId;

  Map<String, ExecutionTracker> get trackers => Map.unmodifiable(_trackers);

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
        if (_activeId == awaitingTrackerKey) {
          final tracker = _trackers.remove(awaitingTrackerKey);
          if (tracker != null) {
            _trackers[messageId] = tracker;
          }
        } else {
          _freezeActive();
          _trackers[messageId] = ExecutionTracker(executionEvents: events);
        }
        _activeId = messageId;
      case AwaitingText():
        if (_activeId != null) return;
        _activeId = awaitingTrackerKey;
        _trackers[awaitingTrackerKey] = ExecutionTracker(
          executionEvents: events,
        );
    }
  }

  /// Freeze the active tracker when a run reaches a terminal state.
  void onRunTerminated() {
    _freezeActive();
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
