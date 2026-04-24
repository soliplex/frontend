import 'package:soliplex_agent/soliplex_agent.dart';

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
  ExecutionTrackerExtension() : _registry = TrackerRegistry() {
    setInitialState(const <String, ExecutionTracker>{});
  }

  final TrackerRegistry _registry;
  void Function()? _runStateUnsub;
  AgentSession? _session;

  @override
  String get namespace => 'execution_tracker';

  @override
  int get priority => 10;

  @override
  List<ClientTool> get tools => const [];

  /// Current tracker map (historical + live for this session).
  Map<String, ExecutionTracker> get trackers => _registry.trackers;

  @override
  Future<void> onAttach(AgentSession session) async {
    _session = session;
    _runStateUnsub = session.runState.subscribe(_onRunState);
  }

  @override
  void onDispose() {
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _session = null;
    _registry.dispose();
    super.onDispose();
  }

  void _onRunState(RunState runState) {
    final session = _session;
    if (session == null) return;
    switch (runState) {
      case RunningState(:final streaming):
        _registry.onStreaming(streaming, session.lastExecutionEvent);
        _sync();
      case CompletedState() || FailedState() || CancelledState():
        _registry.onRunTerminated();
        _sync();
      case IdleState() || ToolYieldingState():
        break;
    }
  }

  void _sync() => state = _registry.trackers;
}
