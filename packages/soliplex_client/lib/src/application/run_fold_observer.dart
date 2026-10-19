import 'package:ag_ui/ag_ui.dart' show BaseEvent;
import 'package:soliplex_client/src/application/run_fold.dart';

/// Told what folding a run does as it does it: each run it starts folding,
/// each of that run's events once folded, and how the run ended. A live run
/// is folded as its stream delivers it, a reopened thread's runs as replay
/// reads their stored events; both report the same calls in the same order.
///
/// What either shows is only its end state; a reader that needs every step in
/// between watches here instead of folding the events a second time.
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
  /// [RunEnding.cancelled]. A resumed turn starts its next run instead.
  void runEnded(RunEnding ending);
}

/// How a run ended.
enum RunEnding {
  /// The run finished, and with it the turn.
  completed,

  /// The run finished waiting on a client tool; the turn resumes in the next
  /// run once the tool has run.
  waitingOnClientTool,

  /// The run failed: its terminal event said so, its stream broke or ended
  /// without one, or the turn could not resume after a client tool.
  failed,

  /// The run was stopped, or its folder was disposed while it ran.
  cancelled,
}
