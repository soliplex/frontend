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
  ExecutionTrackerExtension({required Logger logger})
      : _registry = TrackerRegistry(logger: logger) {
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
    // Order is load-bearing: unsubscribe must precede clearing _session, so
    // _onRunState can rely on _session being non-null while subscribed.
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _session = null;
    _registry.dispose();
    super.onDispose();
  }

  void _onRunState(RunState runState) {
    final session = _session!;
    switch (runState) {
      case RunningState(:final streaming):
        _registry.onStreaming(streaming, session.lastExecutionEvent);
        _sync();
      // Order is load-bearing across the three terminal arms: rekey must
      // run before `onRunTerminated`, because rekey moves the awaiting
      // tracker to its synthesized id while the entry is still present;
      // a future change that drops the awaiting entry on terminate would
      // silently break the rekey if invoked first.
      case CompletedState(:final runId, :final conversation):
        _rekeyAwaitingForNoResponseIfPresent(runId, conversation);
        _registry.onRunTerminated();
        _sync();
      case FailedState(:final runId, :final conversation):
        _rekeyAwaitingForNoResponseIfPresent(runId, conversation);
        _registry.onRunTerminated();
        _sync();
      case CancelledState(:final runId, :final conversation):
        _rekeyAwaitingForNoResponseIfPresent(runId, conversation);
        _registry.onRunTerminated();
        _sync();
      case IdleState() || ToolYieldingState():
        break;
    }
  }

  /// If the terminal conversation contains a synthesized "no response"
  /// assistant message for this run, rekey the awaiting tracker under
  /// that message's id so its captured thinking attaches to the rendered
  /// tile.
  ///
  /// Safe to call unconditionally on every terminal transition — the
  /// registry call is a no-op when the awaiting tracker doesn't exist or
  /// when the synthesized id isn't present in the conversation.
  void _rekeyAwaitingForNoResponseIfPresent(
    String? runId,
    Conversation? conversation,
  ) {
    if (runId == null || conversation == null) return;
    final synthesizedId = noResponseMessageId(runId);
    if (conversation.messages.any((m) => m.id == synthesizedId)) {
      _registry.renameAwaitingTo(synthesizedId);
    }
  }

  void _sync() => state = _registry.trackers;
}
