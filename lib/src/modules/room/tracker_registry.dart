import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';
import 'response_segmenter.dart';

/// The run whose work is being collected: the key its band is open under until
/// a message speaks, and what decides when each of its responses ends.
///
/// The band is open under the message that has spoken in its response, as the
/// segmenter names it, or under [unclaimed] while none has ([_openKey]). When a
/// response ends its band stays where it is and the next one opens under
/// [unclaimed], so nothing else needs to remember which band is open.
typedef _OpenRun = ({String unclaimed, ResponseSegmenter segmenter});

/// Manages execution trackers, keyed by the message that owns the work or —
/// until one speaks — by the run doing it.
///
/// Handles the tracker lifecycle: creation on the first streaming event,
/// handing a band to the message that speaks in its response as soon as it
/// speaks, and freezing when its response ends or its run terminates.
class TrackerRegistry {
  /// Routes [events], the session's execution events, to the open band.
  /// [activities] is the live `Conversation.activities` signal each band
  /// mirrors into a local copy, so that freezing it pins the records it had at
  /// that moment.
  TrackerRegistry({
    required ReadonlySignal<ExecutionEvent?> events,
    required ReadonlySignal<List<ActivityRecord>> activities,
    required Logger logger,
  })  : _activities = activities,
        _logger = logger {
    _sessionUnsub = _routeEvents(events);
  }

  final Map<String, ExecutionTracker> _trackers = {};
  final ReadonlySignal<List<ActivityRecord>> _activities;
  final Logger _logger;

  /// The run being collected, or null between runs.
  _OpenRun? _open;

  /// The registry reads the session's events and hands each to the open band
  /// itself, so recording an event and acting on it happen in one place, in a
  /// stated order. Subscribing each band to the session signal instead would
  /// make that order depend on which subscribed first, and a band opened at a
  /// response boundary always subscribes last.
  void Function()? _sessionUnsub;

  Map<String, ExecutionTracker> get trackers => Map.unmodifiable(_trackers);

  /// Update tracker state based on the current streaming state.
  void onStreaming(StreamingState streaming, String runId) {
    switch (streaming) {
      case TextStreaming(:final messageId, :final text, :final user):
        // A message speaks for the response it was emitted in. A response that
        // begins with a tool call opens a message with nothing in it, purely to
        // give that call's `parentMessageId` something to refer to, and says
        // nothing — so its response's work passes to the reply that does.
        if (text.trim().isEmpty) return;
        // A run whose first streaming state is a reply — no phase before it —
        // still needs somewhere to put the work that follows. Read this run's
        // key, not whatever the last one left behind, or its work would open a
        // band belonging to a run that did not do it.
        final open = _open ?? _openRun(runId);
        // Only an assistant reply hosts a band, in layout's
        // `_standsInForItsRun`, and only an assistant message speaks on reload
        // too. Letting a system reply host one means changing all three, and
        // the tile that renders it, together.
        if (user != ChatUser.assistant) return;
        // A reply arriving after a tool result is the next response opening.
        _handOver(open, open.segmenter.speaks(messageId));
        _keyBySpeaker(open);
      case AwaitingText():
        if (_open == null) _openRun(runId);
    }
  }

  _OpenRun _openRun(String runId) {
    // Until a message speaks, the run owns the band. Keying it by run rather
    // than by a slot shared across runs is what lets two runs that both go
    // quiet each keep their own work, and it names the tile such a run will be
    // given if it never speaks at all.
    final open = (
      unclaimed: noResponseMessageId(runId),
      segmenter: ResponseSegmenter(),
    );
    _open = open;
    _openBand(open);
    return open;
  }

  void _openBand(_OpenRun open) {
    _trackers[open.unclaimed] = ExecutionTracker(
      activities: _activities,
      logger: _logger,
    );
  }

  /// Freezes the band of a response that ended under [takes], the message that
  /// spoke in it, and opens the next response's band.
  ///
  /// Asked of the segmenter from the event stream and from the streaming
  /// state, because neither sees everything: a message start does not bridge
  /// to an execution event, and a tool result does not change the streaming
  /// state. A response that said nothing leaves its work where it is, so the
  /// next response to speak takes that too.
  void _handOver(_OpenRun open, String? takes) {
    if (takes == null) return;
    _trackers[takes]?.freeze(StepStatus.completed);
    _openBand(open);
  }

  /// Hands the open band to the message that has spoken for it, the moment it
  /// speaks, so that layout places it on that message's tile rather than on
  /// whichever tile of the run happens to be last.
  void _keyBySpeaker(_OpenRun open) {
    final owner = open.segmenter.owner;
    if (owner == null) return;
    final tracker = _trackers.remove(open.unclaimed);
    if (tracker != null) _trackers[owner] = tracker;
  }

  String _openKey(_OpenRun open) => open.segmenter.owner ?? open.unclaimed;

  /// Routes each execution event to the open band, then ends the response if
  /// that event ended it.
  ///
  /// A tool result ends the response that made the call: the producer is
  /// invoked again to decide what to do with the result, and what it emits
  /// next belongs to a new response. Nothing in the streaming state says so —
  /// a result leaves it untouched — so this is the only place live can see it.
  void Function() _routeEvents(ReadonlySignal<ExecutionEvent?> events) {
    return events.subscribe((event) {
      final open = _open;
      if (open == null || event == null) return;
      // Closed only once the next response starts, so calls a response made in
      // parallel stay in it, and what arrives between a result and the next
      // response — state the tool wrote, the run ending — stays with it too.
      _handOver(open, open.segmenter.arrives(event));
      _trackers[_openKey(open)]?.observe(event);
    });
  }

  /// Freeze the open band when a run reaches a terminal state.
  ///
  /// The run ending ends the response being collected — the last response of
  /// a run has no tool result to end it.
  void onRunTerminated(StepStatus unfinishedAs) {
    final open = _open;
    if (open == null) return;
    _open = null;
    _trackers[_openKey(open)]?.freeze(unfinishedAs);
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
