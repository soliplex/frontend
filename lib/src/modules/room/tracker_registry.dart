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

  /// The message that has spoken in the response now being collected, or null
  /// while the response has said nothing. It is what claims the band when the
  /// response ends.
  String? _voice;

  /// The registry reads the session's events and hands each to the open band
  /// itself, so recording an event and acting on it happen in one place, in a
  /// stated order. Subscribing each band to the session signal instead would
  /// make that order depend on which subscribed first, and a band opened at a
  /// response boundary always subscribes last.
  void Function()? _sessionUnsub;

  /// Kept from the first band so a response boundary can open the next one
  /// without waiting for another streaming state.
  ReadonlySignal<List<ActivityRecord>>? _activities;
  String? _unclaimed;

  Map<String, ExecutionTracker> get trackers => Map.unmodifiable(_trackers);

  /// Update tracker state based on the current streaming state.
  ///
  /// [events] is the session's execution event signal, read once so the
  /// registry can route each event to the open band. [activities] is the live
  /// `Conversation.activities` signal each band mirrors into a local copy, so
  /// that freezing it pins the records it had at that moment.
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
        // A message speaks for the response it was emitted in. A response that
        // begins with a tool call opens a message with nothing in it, purely to
        // give that call's `parentMessageId` something to refer to, and says
        // nothing — so its response's work passes to the reply that does.
        if (text.trim().isEmpty) return;
        // A run whose first streaming state is a reply — no phase before it —
        // still needs somewhere to put the work that follows. Read this run's
        // key, not whatever the last one left behind, or its work would open a
        // band belonging to a run that did not do it.
        if (_activeId == null) {
          _activities = activities;
          _unclaimed = unclaimed;
          _openBand(unclaimed);
          _sessionUnsub ??= _routeEvents(events);
        }
        // The first message to speak in a response speaks for it. A producer
        // that emits two texts in one response has not done two things, and
        // splitting the response's work between them would put half of it
        // above a line that did not ask for it.
        _voice ??= messageId;
      case AwaitingText():
        if (_activeId != null) return;
        _activities = activities;
        _unclaimed = unclaimed;
        _openBand(unclaimed);
        _sessionUnsub ??= _routeEvents(events);
    }
  }

  void _openBand(String key) {
    _activeId = key;
    _trackers[key] = ExecutionTracker(
      activities: _activities!,
      logger: _logger,
    );
  }

  /// Routes each execution event to the open band, then ends the response if
  /// that event ended it.
  ///
  /// A tool result ends the response that made the call: the producer is
  /// invoked again to decide what to do with the result, and what it emits
  /// next belongs to a new response. Nothing in the streaming state says so —
  /// a result leaves it untouched — so this is the only place live can see it.
  void Function() _routeEvents(ReadonlySignal<ExecutionEvent?> events) {
    // `subscribe` delivers the signal's current value at once: the last event
    // of the run that just ended, which this run's bands must not record.
    var replayingCurrentValue = true;
    return events.subscribe((event) {
      if (replayingCurrentValue) {
        replayingCurrentValue = false;
        return;
      }
      _trackers[_activeId]?.observe(event);
      if (event is! ServerToolCallCompleted) return;
      final takes = _voice;
      // A response that said nothing leaves its work where it is, so the next
      // response to speak takes that too. It is also what keeps calls made in
      // parallel together: nothing moves between their results.
      if (takes == null) return;
      _claim(takes, StepStatus.completed);
      _openBand(_unclaimed!);
    });
  }

  /// Hands the open band to [takes], the message that spoke for it.
  void _claim(String takes, StepStatus unfinishedAs) {
    final from = _activeId;
    if (from == null) return;
    final tracker = _trackers.remove(from);
    if (tracker != null) _trackers[takes] = tracker..freeze(unfinishedAs);
    _voice = null;
    _activeId = null;
  }

  /// Freeze the open band when a run reaches a terminal state.
  ///
  /// The run ending ends the response being collected, so whoever spoke in it
  /// takes the band — the last response of a run has no tool result to end it.
  void onRunTerminated(StepStatus unfinishedAs) {
    final takes = _voice;
    if (takes != null) {
      _claim(takes, unfinishedAs);
      return;
    }
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
    _sessionUnsub?.call();
    _sessionUnsub = null;
    for (final tracker in _trackers.values) {
      tracker.dispose();
    }
    _trackers.clear();
  }
}
