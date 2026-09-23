import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';
import 'tracker_registry.dart';

/// A [SessionExtension] that reacts to [AgentSession] run-state changes and
/// drives an internal [TrackerRegistry].
///
/// Subscribes to `session.runState` in [onAttach] and routes
/// [RunningState]/terminal states into the registry. The resulting
/// [Map<String, ExecutionTracker>] is exposed via the [stateSignal] and the
/// convenience [trackers] getter.
///
/// [ThreadViewState] absorbs the live trackers into its own historical
/// registry on detach, so execution data persists after the session ends.
class ExecutionTrackerExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, ExecutionTracker>> {
  ExecutionTrackerExtension({required Logger logger}) : _logger = logger {
    setInitialState(const <String, ExecutionTracker>{});
  }

  final Logger _logger;

  /// Built on attach, from the session whose events it routes; null before.
  TrackerRegistry? _registry;
  void Function()? _runStateUnsub;

  @override
  String get namespace => 'execution_tracker';

  @override
  int get priority => 10;

  @override
  List<ClientTool> get tools => const [];

  /// Current tracker map (historical + live for this session).
  Map<String, ExecutionTracker> get trackers => _registry?.trackers ?? const {};

  @override
  Future<void> onAttach(AgentSession session) async {
    _registry = TrackerRegistry(
      events: session.lastExecutionEvent,
      activities: session.conversationActivities,
      logger: _logger,
    );
    _runStateUnsub = session.runState.subscribe(_onRunState);
  }

  @override
  void onDispose() {
    // Order is load-bearing: unsubscribe must precede clearing _registry, so
    // _onRunState can rely on _registry being non-null while subscribed.
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _registry?.dispose();
    _registry = null;
    super.onDispose();
  }

  /// Test entrypoint for [_onRunState]. Production code routes through
  /// the signal subscription; tests use this to drive the post-dispose
  /// path that production can't reach without racing the signals teardown.
  @visibleForTesting
  void debugPushRunState(RunState runState) => _onRunState(runState);

  void _onRunState(RunState runState) {
    final registry = _registry;
    if (registry == null) {
      // signals teardown is assumed synchronous w.r.t. onDispose, but
      // that's a fragile invariant across signals upgrades. Reaching
      // here means the invariant broke — `error`-level so Sentry can
      // page on a regression instead of having the breadcrumb buried
      // among warnings.
      _logger.error(
        '_onRunState fired after dispose; ignoring',
        stackTrace: StackTrace.current,
        attributes: {'runState': runState.runtimeType.toString()},
      );
      return;
    }
    switch (runState) {
      case RunningState(:final runId, :final streaming):
        registry.onStreaming(streaming, runId);
        _sync(registry);
      case CompletedState():
        registry.onRunTerminated(StepStatus.completed);
        _sync(registry);
      // A step still running when the user stops the run, or when the run
      // fails, did not finish. Reporting it green would say the work landed.
      case FailedState() || CancelledState():
        registry.onRunTerminated(StepStatus.failed);
        _sync(registry);
      case IdleState() || ToolYieldingState():
        break;
    }
  }

  void _sync(TrackerRegistry registry) => state = registry.trackers;
}
