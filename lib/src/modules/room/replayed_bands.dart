import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_tracker.dart';
import 'replay_clock.dart';
import 'tracker_registry.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.replayed_bands');

/// The execution bands of a thread's history, built by the registry a live
/// session builds them with, fed what a live session feeds it, in the order it
/// feeds it.
///
/// One registry per turn, as live has one per session. For each run, the
/// streaming state it opens in; then for each event, the streaming state after
/// it, the conversation's activities, and the event bridged, when it reached
/// the conversation. A run's `RUN_FINISHED` or `RUN_ERROR` is published as the
/// run ending, before the event itself, which then reaches no band.
///
/// Except when the run waits on a client tool: a run that continues the turn
/// says the run before it waited rather than ended, and live keeps the turn's
/// band open across the wait, so that run's `RUN_FINISHED` reaches the band.
/// Which of the two a terminal event was is known only once the next run
/// starts, or the history ends, so it is held until then.
class ReplayedBands implements ReplayObserver {
  final Map<String, ExecutionTracker> _bands = {};
  _ReplayedTurn? _turn;

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) {
    if (continuesTurn) {
      _turn?.resume();
    } else {
      _endTurn();
    }
    (_turn ??= _ReplayedTurn()).runStarted(fold);
  }

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) =>
      _turn?.eventFolded(fold, processed);

  /// Ends the turn the history ended on and hands over every band, keyed as
  /// the live registry keys them.
  Map<String, ExecutionTracker> finish() {
    _endTurn();
    return Map.unmodifiable(_bands);
  }

  void _endTurn() {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    _bands.addAll(turn.end());
  }
}

/// How a run's terminal event left it: whether it finished, the activities
/// its conversation held, and the event bridged.
typedef _Ending = ({
  bool completed,
  List<ActivityRecord> activities,
  ExecutionEvent? event,
});

/// One turn being replayed, with what a live session hands its registry.
class _ReplayedTurn {
  _ReplayedTurn() {
    _registry = TrackerRegistry.replaying(
      events: _events,
      activities: _activities,
      clock: _clock,
      logger: _logger,
    );
  }

  final Signal<ExecutionEvent?> _events = Signal<ExecutionEvent?>(null);
  final Signal<List<ActivityRecord>> _activities =
      Signal<List<ActivityRecord>>(const []);
  final ReplayClock _clock = ReplayClock();
  late final TrackerRegistry _registry;

  /// The terminal event of the run being replayed, held until it is known
  /// whether the run ended or waited on a client tool.
  _Ending? _ending;

  void runStarted(RunFold fold) {
    _clock.eventTime = null;
    _registry.onStreaming(fold.streaming, fold.runId);
    _activities.value = fold.conversation.activities;
  }

  void eventFolded(RunFold fold, BaseEvent? processed) {
    // Live stops reading a run's stream at its terminal event.
    if (_ending != null) return;
    _clock.eventTime = processed?.timestamp;
    final event = processed == null ? null : bridgeBaseEvent(processed);
    if (processed is RunFinishedEvent || processed is RunErrorEvent) {
      _ending = (
        completed: processed is RunFinishedEvent,
        activities: fold.conversation.activities,
        event: event,
      );
      return;
    }
    _registry.onStreaming(fold.streaming, fold.runId);
    _activities.value = fold.conversation.activities;
    if (event != null) _events.value = event;
  }

  /// The run starting continues the turn, so the run before it waited on a
  /// client tool: the turn's band stays open and takes that run's terminal
  /// event, when it stored one.
  void resume() {
    final ending = _ending;
    if (ending == null) return;
    _ending = null;
    _activities.value = ending.activities;
    if (ending.event case final event?) _events.value = event;
  }

  /// Ends the turn as its last run ended, cut off when it reached no terminal
  /// event, and hands over its bands.
  Map<String, ExecutionTracker> end() {
    final ending = _ending;
    _registry.onRunEnded(completed: ending?.completed ?? false);
    if (ending != null) {
      _activities.value = ending.activities;
      if (ending.event case final event?) _events.value = event;
    }
    final bands = _registry.trackers;
    _registry.dispose();
    _events.dispose();
    _activities.dispose();
    return bands;
  }
}
