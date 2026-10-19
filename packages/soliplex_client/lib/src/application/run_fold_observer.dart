import 'dart:async' show Zone;

import 'package:ag_ui/ag_ui.dart' show BaseEvent;
import 'package:soliplex_client/src/application/run_fold.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Told what folding a run does as it does it: each run it starts folding,
/// each of that run's events once folded, and how the run ended. A live run
/// is folded as its stream delivers it, a reopened thread's runs as replay
/// reads their stored events. For the same events both report the same calls
/// in the same order, except for a client-tool wait that ended without
/// resuming the turn: that ending stores no event, so live alone reports it,
/// and replay reports how the waiting run's own events ended.
///
/// What either shows is only its end state; a reader that needs every step in
/// between watches here instead of folding the events a second time.
///
/// An observer that throws stops neither a live run nor a replay: both tell
/// it through a [GuardedRunFoldObserver].
abstract interface class RunFoldObserver {
  /// [fold]'s run starts, before any of its events. [continuesTurn] says the
  /// run resumes the turn of the run before it, as a run resumed after a
  /// client tool does.
  void runStarted(RunFold fold, {required bool continuesTurn});

  /// One of the run's events was folded into [fold]. [processed] is the event
  /// when it reached the conversation, and null when it could not be read or
  /// processed and became a drop tile instead.
  void eventFolded(RunFold fold, {required BaseEvent? processed});

  /// The run started last ended as [ending], after its terminal event when it
  /// had one.
  ///
  /// A run that ended [RunEnding.waitingOnClientTool] ends again when the wait
  /// does without resuming the turn: [RunEnding.failed] or
  /// [RunEnding.cancelled]. A resumed turn starts its next run instead, and a
  /// reset during the wait discards the run and reports nothing more.
  void runEnded(RunEnding ending);
}

/// Tells an observer each step of a fold, so that a bug of the observer's own
/// cannot stop the fold it watches.
///
/// Nothing the observer throws escapes, so it is told every step it would have
/// been, and a later ending still settles what it shows. Its first failure at
/// each step is reported once for as long as the guard lives: a live turn, or
/// a whole replay; a failure that repeats would repeat once per step. It is
/// logged through `describeFailure`, since the observer's exception may carry
/// what it was handling, and where asserts are checked it is also handed to
/// the zone, so a bug in an observer fails a test as it would anywhere else.
class GuardedRunFoldObserver implements RunFoldObserver {
  /// Tells [observer] each step of [threadId]'s runs, logging its failures to
  /// [logger].
  GuardedRunFoldObserver(
    RunFoldObserver observer, {
    required String threadId,
    required Logger logger,
  })  : _observer = observer,
        _threadId = threadId,
        _logger = logger;

  final RunFoldObserver _observer;
  final String _threadId;
  final Logger _logger;

  /// The steps [_observer] has failed at.
  final Set<String> _failedSteps = {};

  /// The run started last, which an ending belongs to.
  String? _runId;

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) {
    _runId = fold.runId;
    _tell(
      'runStarted',
      () => _observer.runStarted(fold, continuesTurn: continuesTurn),
    );
  }

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) {
    _runId = fold.runId;
    _tell(
      'eventFolded',
      () => _observer.eventFolded(fold, processed: processed),
    );
  }

  @override
  void runEnded(RunEnding ending) =>
      _tell('runEnded', () => _observer.runEnded(ending));

  void _tell(String step, void Function() tell) {
    try {
      tell();
    } on Object catch (error, stackTrace) {
      if (!_failedSteps.add(step)) return;
      assert(
        () {
          Zone.current.handleUncaughtError(error, stackTrace);
          return true;
        }(),
        'runs only where asserts are checked',
      );
      final runId = _runId;
      _logger.error(
        'Run fold observer threw; this step failing again is not logged',
        stackTrace: stackTrace,
        attributes: {
          'step': step,
          'threadId': _threadId,
          if (runId != null) 'runId': runId,
          'failure': describeFailure(error),
        },
      );
    }
  }
}

/// How a run ended.
enum RunEnding {
  /// The run finished, and with it the turn.
  completed,

  /// The run finished waiting on a client tool; the turn resumes in the next
  /// run once the tool has run.
  waitingOnClientTool,

  /// The run failed: its terminal event said so, its stream broke or ended
  /// without one, or its client-tool wait ended in failure: the tool executor
  /// threw, the resume failed, or the tool-depth limit was reached.
  failed,

  /// The run was stopped, or whatever was folding it was disposed while it ran
  /// or waited on a client tool.
  cancelled,
}
