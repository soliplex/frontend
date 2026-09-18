import 'package:flutter/foundation.dart' show visibleForTesting;
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
      : _logger = logger,
        _registry = TrackerRegistry(logger: logger) {
    setInitialState(const <String, ExecutionTracker>{});
  }

  final Logger _logger;
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

  /// Test entrypoint for [_onRunState]. Production code routes through
  /// the signal subscription; tests use this to drive the post-dispose
  /// path that production can't reach without racing the signals teardown.
  @visibleForTesting
  void debugPushRunState(RunState runState) => _onRunState(runState);

  void _onRunState(RunState runState) {
    final session = _session;
    if (session == null) {
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
      case RunningState(:final streaming):
        if (streaming case TextStreaming(:final messageId)) {
          _openedMessageId = messageId;
        }
        _registry.onStreaming(
          streaming,
          session.lastExecutionEvent,
          session.conversationActivities,
        );
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

  /// Hands the band still collecting to the tile this run left behind, so the
  /// steps the user watched attach to something the timeline renders.
  ///
  /// Two tiles can be that: the synthesized "no response" message for this
  /// run, and a reply that opened and streamed reasoning but was cut off
  /// before saying anything — a band goes to a message once it has spoken, so
  /// that one holds none of its own, and a terminal commits it anyway for the
  /// reasoning the user watched stream.
  ///
  /// Does nothing unless a band is actually open and the tile has none: a run
  /// whose reply spoke already handed its band over by speaking, and calling
  /// the registry there would report a handover that never needed to happen.
  void _rekeyAwaitingForNoResponseIfPresent(
    String? runId,
    Conversation? conversation,
  ) {
    final openedId = _openedMessageId;
    _openedMessageId = null;
    if (conversation == null) return;
    final trackers = _registry.trackers;
    if (!trackers.containsKey(awaitingTrackerKey)) return;
    for (final candidate in <String>[
      if (runId != null) noResponseMessageId(runId),
      if (openedId != null) openedId,
    ]) {
      if (trackers.containsKey(candidate)) continue;
      if (conversation.messages.any((m) => m.id == candidate)) {
        _registry.renameAwaitingTo(candidate);
        return;
      }
    }
  }

  /// The message the run last opened a text stream for, so a terminal can hand
  /// the band to it when that message turns out to be what the run left
  /// behind. Cleared at every terminal.
  String? _openedMessageId;

  void _sync() => state = _registry.trackers;
}
