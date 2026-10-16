import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/replay_clock.dart';

import 'test_logger.dart';

/// A stored event as a replayed band is fed it: the execution event it bridged
/// to, or null when it bridged to none, and the time it was emitted with, or
/// null when it carries none.
typedef StoredStep = ({ExecutionEvent? event, int? timestamp});

/// [events] with no emission time, the shape a stored thread has when the
/// backend that produced it did not stamp its events.
List<StoredStep> untimed(List<ExecutionEvent> events) =>
    [for (final event in events) (event: event, timestamp: null)];

/// A replayed band fed [events] directly, each at its stored time, outside
/// any registry, then frozen with [unfinishedAs] as the run's ending.
ExecutionTracker replayedBand({
  List<StoredStep> events = const [],
  StepStatus unfinishedAs = StepStatus.completed,
  Logger? logger,
}) {
  final clock = ReplayClock();
  final band = ExecutionTracker.replayed(
    activities: Signal<List<ActivityRecord>>(const []),
    elapsed: clock.start(),
    logger: logger ?? testLogger(),
  );
  for (final (:event, :timestamp) in events) {
    clock.eventTime = timestamp;
    if (event != null) band.observe(event);
  }
  band.freeze(unfinishedAs);
  return band;
}
