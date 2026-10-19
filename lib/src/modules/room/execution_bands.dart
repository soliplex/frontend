import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_tracker.dart';
import 'replay_clock.dart';
import 'tracker_registry.dart';

final Logger _replayLogger =
    LogManager.instance.getLogger('soliplex_frontend.execution_bands');

/// The execution bands of runs as they are folded: a live session's, from its
/// stream, or a thread's history, from its stored events. For the same events
/// both are fed the same calls in the same order, so, but for the one
/// exception `RunFoldObserver` names, both build the same bands. The clock
/// differs too: a live band times its steps by a running stopwatch, a
/// replayed one by the stored events' times.
///
/// One registry per turn; a live session holds one turn. For each run, the
/// streaming state it opens in; then for each event, the streaming state after
/// it, the conversation's activities, and the event bridged, when it reached
/// the conversation. A run's `RUN_FINISHED` or `RUN_ERROR` is held until this
/// is told how the run ended, and nothing folded after it reaches a band: live
/// folds nothing after it. A run that ended is ended in its registry before
/// its terminal event is handed to the registry, so the event reaches no band;
/// a run waiting on a client tool keeps the turn's band open across the wait,
/// and the event reaches it.
class ExecutionBands implements RunFoldObserver {
  /// Bands rebuilt from a thread's stored events.
  ExecutionBands.replayed()
      : _replayed = true,
        _logger = _replayLogger;

  /// Bands built as a live session's runs stream.
  ExecutionBands.live({required Logger logger})
      : _replayed = false,
        _logger = logger;

  final bool _replayed;
  final Logger _logger;
  final Map<String, ExecutionTracker> _bands = {};

  /// The steps reported as told before any run started.
  final Set<String> _reportedUnstarted = {};
  _Turn? _turn;

  /// Every band so far, keyed as layout places them: the turns ended, and the
  /// one being collected.
  Map<String, ExecutionTracker> get trackers =>
      Map.unmodifiable({..._bands, ...?_turn?.trackers});

  /// Every run that has started in the turn being collected.
  Set<String> get runs => _turn?.runs ?? const {};

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) {
    if (!continuesTurn) _endTurn();
    (_turn ??= _Turn(clock: _replayed ? ReplayClock() : null, logger: _logger))
        .runStarted(fold);
  }

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) {
    final turn = _turn;
    if (turn == null) {
      _reportUnstarted('eventFolded', runId: fold.runId);
      return;
    }
    turn.eventFolded(fold, processed);
  }

  @override
  void runEnded(RunEnding ending) {
    final turn = _turn;
    if (turn == null) {
      _reportUnstarted('runEnded');
      return;
    }
    turn.runEnded(ending);
  }

  /// Both producers tell a run starting before any of its steps, so a step
  /// with no turn to reach is a producer's bug, or follows a run start this
  /// threw at; dropped, it would leave no trace. Each step is reported once,
  /// as the run fold guard reports a failure: after a run start that threw,
  /// every event of the run would repeat it.
  void _reportUnstarted(String step, {String? runId}) {
    if (_reportedUnstarted.add(step)) {
      _logger.warning(
        'Fold step before any run started; dropped',
        attributes: {'step': step, if (runId != null) 'runId': runId},
      );
    }
    assert(false, '$step told before any run started');
  }

  /// Ends the turn being collected and hands over every band, keyed as
  /// [trackers] keys them.
  ///
  /// Called directly, not through the run fold guard: whatever it throws fails
  /// the caller, and on reload that is the whole history load. Nothing on its
  /// path can throw today: it copies maps and releases the turn's registry
  /// (`_Turn.end`, `TrackerRegistry.dispose`, `ExecutionTracker.dispose`),
  /// which unsubscribes from a signal and runs no app code.
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

/// A run's terminal event, with the activities its conversation held then.
typedef _Terminal = ({
  List<ActivityRecord> activities,
  ExecutionEvent? event,
});

/// One turn, with what its registry is handed.
class _Turn {
  /// [clock] times a replayed turn's bands; null for a live one.
  _Turn({required ReplayClock? clock, required Logger logger})
      : _clock = clock,
        _registry = clock == null
            ? TrackerRegistry(logger: logger)
            : TrackerRegistry.replaying(clock: clock, logger: logger);

  final ReplayClock? _clock;
  final TrackerRegistry _registry;

  /// The terminal event of the run being folded, held until the run is told
  /// how it ended.
  _Terminal? _terminal;

  Map<String, ExecutionTracker> get trackers => _registry.trackers;

  Set<String> get runs => _registry.runs;

  void runStarted(RunFold fold) {
    _clock?.eventTime = null;
    _registry.onStreaming(fold.streaming, fold.runId);
    _registry.onActivities(fold.conversation.activities);
  }

  void eventFolded(RunFold fold, BaseEvent? processed) {
    if (_terminal != null) return;
    _clock?.eventTime = processed?.timestamp;
    final event = processed == null ? null : bridgeBaseEvent(processed);
    if (processed is RunFinishedEvent || processed is RunErrorEvent) {
      _terminal = (activities: fold.conversation.activities, event: event);
      return;
    }
    _registry.onStreaming(fold.streaming, fold.runId);
    _registry.onActivities(fold.conversation.activities);
    if (event != null) _registry.onEvent(event);
  }

  void runEnded(RunEnding ending) {
    // Taken first, so a registry that throws below cannot leave the run's
    // events ignored for the rest of the turn.
    final terminal = _terminal;
    _terminal = null;
    switch (ending) {
      case RunEnding.completed:
        _registry.onRunEnded(completed: true);
      case RunEnding.failed || RunEnding.cancelled:
        _registry.onRunEnded(completed: false);
      case RunEnding.waitingOnClientTool:
        break;
    }
    if (terminal == null) return;
    _registry.onActivities(terminal.activities);
    if (terminal.event case final event?) _registry.onEvent(event);
  }

  /// Hands over the turn's bands and releases its registry, which stops each
  /// band mirroring the turn's activities.
  Map<String, ExecutionTracker> end() {
    final bands = _registry.trackers;
    _registry.dispose();
    return bands;
  }
}
