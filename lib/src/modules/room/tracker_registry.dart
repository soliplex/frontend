import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';

/// Manages execution trackers, keyed by the message that owns the work or —
/// until one speaks — by the run doing it.
///
/// Handles the tracker lifecycle: creation on the first streaming event,
/// re-keying to a message once that message says something, and freezing when
/// a run terminates.
class TrackerRegistry {
  TrackerRegistry({required Logger logger}) : _logger = logger;

  final Map<String, ExecutionTracker> _trackers = {};
  String? _activeId;
  final Logger _logger;

  Map<String, ExecutionTracker> get trackers => Map.unmodifiable(_trackers);

  /// Update tracker state based on the current streaming state.
  ///
  /// [events] is the execution event signal to subscribe a new tracker
  /// to, only used when a tracker needs to be created. [activities] is
  /// the live `Conversation.activities` signal the new tracker mirrors
  /// into a local copy, so that freezing it pins the records it had at
  /// that moment.
  void onStreaming(
    StreamingState streaming,
    String runId,
    ReadonlySignal<ExecutionEvent?> events,
    ReadonlySignal<List<ActivityRecord>> activities,
  ) {
    // Until a message speaks, the run owns the band. Keying it by run rather
    // than by a slot shared across runs is what lets two runs that both go
    // quiet each keep their own work, and it names the tile such a run will be
    // given if it never speaks at all.
    final unclaimed = noResponseMessageId(runId);
    switch (streaming) {
      case TextStreaming(:final messageId, :final text):
        // A band goes to a message once it has said something. A response that
        // begins with a tool call opens a message with nothing in it, purely to
        // give that call's `parentMessageId` something to refer to, and its
        // work belongs to the reply that eventually speaks.
        if (text.trim().isEmpty) return;
        if (_activeId == messageId) return;
        if (_activeId == unclaimed) {
          final tracker = _trackers.remove(unclaimed);
          if (tracker != null) {
            _trackers[messageId] = tracker;
          }
        } else {
          // The run moved on to a new reply, so the stretch that closes here
          // did finish its work; only a terminal leaves a step unfinished.
          _freezeActive(StepStatus.completed);
          _trackers[messageId] = ExecutionTracker(
            executionEvents: events,
            activities: activities,
            logger: _logger,
          );
        }
        _activeId = messageId;
      case AwaitingText():
        if (_activeId != null) return;
        _activeId = unclaimed;
        _trackers[unclaimed] = ExecutionTracker(
          executionEvents: events,
          activities: activities,
          logger: _logger,
        );
    }
  }

  /// Freeze the active tracker when a run reaches a terminal state.
  void onRunTerminated(StepStatus unfinishedAs) {
    _freezeActive(unfinishedAs);
  }

  /// Bulk-inserts already-frozen trackers produced from a loaded thread's
  /// history. Existing entries with the same key are not overwritten —
  /// a live tracker always wins over a historical one.
  void seedHistorical(Map<String, ExecutionTracker> historical) {
    for (final entry in historical.entries) {
      _trackers.putIfAbsent(entry.key, () => entry.value);
    }
  }

  void _freezeActive(StepStatus unfinishedAs) {
    if (_activeId != null) {
      _trackers[_activeId!]?.freeze(unfinishedAs);
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
