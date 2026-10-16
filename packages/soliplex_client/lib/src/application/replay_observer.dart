import 'package:ag_ui/ag_ui.dart' show BaseEvent;
import 'package:soliplex_client/src/application/run_fold.dart';

/// Told what a thread's history replay does as it does it: each run it starts
/// folding, then each of that run's events once folded, in the order a live
/// run's stream would deliver them.
///
/// What replay shows is only its end state; a reader that needs every step in
/// between, as the live path sees it, watches here instead of folding the
/// events a second time.
abstract interface class ReplayObserver {
  /// Replay starts folding [fold]'s run, before any of its events.
  /// [continuesTurn] says the run resumes the turn of the run before it, as a
  /// run resumed after a client tool does.
  void runStarted(RunFold fold, {required bool continuesTurn});

  /// Replay folded one of the run's stored events into [fold]. [processed] is
  /// the event when it reached the conversation, and null when it could not be
  /// read or processed and became a drop tile instead.
  void eventFolded(RunFold fold, {required BaseEvent? processed});
}
