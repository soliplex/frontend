import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';
import 'replay_clock.dart';
import 'response_segmenter.dart';

/// The turn whose work is being collected: the key its band is open under
/// until a message speaks, which names its latest run, and what decides when
/// each of its responses ends.
///
/// The band is open under the message that has spoken in its response, as the
/// segmenter names it, or under [unclaimed] while none has ([_openKey]). When a
/// response ends its band stays where it is and the next one opens under
/// [unclaimed], so nothing else needs to remember which band is open.
typedef _OpenTurn = ({String unclaimed, ResponseSegmenter segmenter});

/// Manages execution trackers, keyed by the message that owns the work or —
/// until one speaks — by the turn's latest run.
///
/// Handles the tracker lifecycle: creation on the first streaming event,
/// handing a band to the message that speaks in its response as soon as it
/// speaks, and freezing when its response ends or its run terminates.
class TrackerRegistry {
  /// A registry collecting a live turn's bands, timed as they run.
  TrackerRegistry({required Logger logger})
      : _clock = null,
        _logger = logger;

  /// A registry rebuilding one turn's bands from its stored events, whose
  /// bands are timed by [clock].
  TrackerRegistry.replaying({
    required ReplayClock clock,
    required Logger logger,
  })  : _clock = clock,
        _logger = logger;

  final Map<String, ExecutionTracker> _trackers = {};

  /// The run's `Conversation.activities`, which each open band mirrors into a
  /// local copy, so that freezing it pins the records it had at that moment.
  final Signal<List<ActivityRecord>> _activities =
      Signal<List<ActivityRecord>>(const []);

  /// What times a replayed turn's bands; null for a live one.
  final ReplayClock? _clock;
  final Logger _logger;

  /// The turn being collected, or null between turns.
  _OpenTurn? _open;

  final Set<String> _runs = {};

  Map<String, ExecutionTracker> get trackers => Map.unmodifiable(_trackers);

  /// Every run that has started in this session's turn.
  Set<String> get runs => Set.unmodifiable(_runs);

  /// Update tracker state based on the current streaming state.
  void onStreaming(StreamingState streaming, String runId) {
    _runs.add(runId);
    _continueTurn(runId);
    switch (streaming) {
      case TextStreaming(:final messageId, :final text, :final user):
        // A message speaks for the response it was emitted in. A response that
        // begins with a tool call opens a message with nothing in it, purely to
        // give that call's `parentMessageId` something to refer to, and says
        // nothing — so its response's work passes to the reply that does.
        if (text.trim().isEmpty) return;
        // A turn whose first streaming state is a reply — no phase before it —
        // still needs somewhere to put the work that follows. Read this run's
        // key, not whatever the last turn left behind, or its work would open
        // a band belonging to a turn that did not do it.
        final open = _open ?? _openTurn(runId);
        // Only an assistant reply hosts a band, in layout's
        // `_standsInForItsRun`. Letting a system reply host one means changing
        // both, and the tile that renders it, together.
        if (user != ChatUser.assistant) return;
        // A reply arriving after a tool result is the next response opening.
        _handOver(open, open.segmenter.speaks(messageId));
        _keyBySpeaker(open);
      case AwaitingText():
        if (_open == null) _openTurn(runId);
    }
  }

  /// Keys the open turn's unclaimed work to [runId], the run streaming now. A
  /// new run here resumes the turn after a client tool and is its latest run
  /// so far: its key names the tile the turn's outcome is given if nothing in
  /// the turn speaks. For the same run nothing changes. The response being
  /// collected carries on. Any run arriving while a turn is open belongs to
  /// it because a registry lives for one turn: a session's, or one replayed.
  void _continueTurn(String runId) {
    final open = _open;
    if (open == null) return;
    final unclaimed = noResponseMessageId(runId);
    final tracker = _trackers.remove(open.unclaimed);
    if (tracker != null) _trackers[unclaimed] = tracker;
    _open = (unclaimed: unclaimed, segmenter: open.segmenter);
  }

  _OpenTurn _openTurn(String runId) {
    // Until a message speaks, the turn's latest run owns the band. Keying it
    // by run rather than by a slot shared across turns is what lets two turns
    // that both go quiet each keep their own work, and it names the tile such
    // a turn's run will be given if it never speaks at all.
    final open = (
      unclaimed: noResponseMessageId(runId),
      segmenter: ResponseSegmenter(),
    );
    _open = open;
    _openBand(open);
    return open;
  }

  void _openBand(_OpenTurn open) {
    final clock = _clock;
    _trackers[open.unclaimed] = clock == null
        ? ExecutionTracker(activities: _activities, logger: _logger)
        : ExecutionTracker.replayed(
            activities: _activities,
            elapsed: clock.start(),
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
  void _handOver(_OpenTurn open, String? takes) {
    if (takes == null) return;
    _trackers[takes]?.freeze(StepStatus.completed);
    _openBand(open);
  }

  /// Hands the open band to the message that has spoken for it, the moment it
  /// speaks, so that layout places it on that message's tile rather than on
  /// whichever tile of the run happens to be last.
  void _keyBySpeaker(_OpenTurn open) {
    final owner = open.segmenter.owner;
    if (owner == null) return;
    final tracker = _trackers.remove(open.unclaimed);
    if (tracker != null) _trackers[owner] = tracker;
  }

  String _openKey(_OpenTurn open) => open.segmenter.owner ?? open.unclaimed;

  /// Routes [event] to the open band, after ending the response if [event]
  /// opens the next one.
  ///
  /// The registry hands each event to the open band itself, so recording an
  /// event and acting on it happen in one place, in a stated order.
  ///
  /// A tool result ends the response that made the call: the producer is
  /// invoked again to decide what to do with the result, and what it emits
  /// next belongs to a new response. Nothing in the streaming state says so —
  /// a result leaves it untouched — so this is the only place the registry can
  /// see it.
  void onEvent(ExecutionEvent event) {
    final open = _open;
    if (open == null) return;
    // Closed only once the next response starts, so calls a response made in
    // parallel stay in it, and what arrives between a result and the next
    // response — state the tool wrote, the run ending — stays with it too.
    _handOver(open, open.segmenter.arrives(event));
    _trackers[_openKey(open)]?.observe(event);
  }

  /// The run's `Conversation.activities` is now [activities].
  void onActivities(List<ActivityRecord> activities) =>
      _activities.value = activities;

  /// Freeze the open band when a run reaches a terminal state, [completed]
  /// when the run finished rather than failing or being stopped.
  ///
  /// The run ending ends the response being collected — the last response of
  /// a run has no tool result to end it. A step still running when the run
  /// fails or is stopped did not finish; reporting it green would say the
  /// work landed.
  void onRunEnded({required bool completed}) {
    final open = _open;
    if (open == null) return;
    _open = null;
    final band = _trackers[_openKey(open)];
    // The run's own RUN_FINISHED is routed after this, to no band, so the band
    // settles as that event would, which also reports a call the run finished
    // without answering.
    if (completed) band?.observe(const RunCompleted());
    band?.freeze(completed ? StepStatus.completed : StepStatus.failed);
  }

  void dispose() {
    for (final tracker in _trackers.values) {
      tracker.dispose();
    }
    _trackers.clear();
    _activities.dispose();
  }
}
