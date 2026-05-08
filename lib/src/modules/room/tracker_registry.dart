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
  TrackerRegistry({required Logger logger}) : _logger = logger;

  final Map<String, ExecutionTracker> _trackers = {};
  String? _activeId;
  final Logger _logger;

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
          _trackers[messageId] =
              ExecutionTracker(executionEvents: events, logger: _logger);
        }
        _activeId = messageId;
      case AwaitingText():
        if (_activeId != null) return;
        _activeId = awaitingTrackerKey;
        _trackers[awaitingTrackerKey] = ExecutionTracker(
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
  /// The "synthesized message exists but no awaiting tracker present"
  /// case is a state divergence — the tile will still render the
  /// thinking text from `TextMessage.thinkingText` (set at synthesis
  /// time), but it won't have the tracker-attached execution-step
  /// timeline. Logs a warning so the divergence is observable.
  void renameAwaitingTo(String key) {
    if (key == awaitingTrackerKey) return;
    final tracker = _trackers.remove(awaitingTrackerKey);
    if (tracker == null) {
      _logger.warning(
        'No awaiting tracker for renameAwaitingTo; the synthesized '
        'no-response tile will still show its thinking text but will lack '
        'the tracker-attached execution-step timeline.',
        attributes: {'targetKey': key},
      );
      return;
    }
    _trackers[key] = tracker;
    if (_activeId == awaitingTrackerKey) {
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
