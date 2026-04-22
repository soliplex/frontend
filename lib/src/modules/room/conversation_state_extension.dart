import 'package:soliplex_agent/soliplex_agent.dart';

/// A [SessionExtension] that surfaces the ag-ui conversation state as a
/// reactive signal.
///
/// Subscribes to `session.runState` in [onAttach] and updates [stateSignal]
/// whenever [Conversation.aguiState] changes. The orchestrator already applies
/// [StateSnapshotEvent] and [StateDeltaEvent] into the conversation, so this
/// extension just reads the already-merged result from each [RunningState] and
/// [CompletedState] transition.
class ConversationStateExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, dynamic>> {
  ConversationStateExtension() {
    setInitialState(const <String, dynamic>{});
  }

  void Function()? _runStateUnsub;

  @override
  String get namespace => 'conversation_state';

  @override
  int get priority => 20;

  @override
  List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {
    _runStateUnsub = session.runState.subscribe(_onRunState);
  }

  @override
  void onDispose() {
    _runStateUnsub?.call();
    _runStateUnsub = null;
    super.onDispose();
  }

  void _onRunState(RunState runState) {
    final aguiState = switch (runState) {
      RunningState(:final conversation) => conversation.aguiState,
      CompletedState(:final conversation) => conversation.aguiState,
      FailedState(:final conversation) => conversation?.aguiState,
      CancelledState(:final conversation) => conversation?.aguiState,
      _ => null,
    };
    if (aguiState != null && aguiState != state) {
      state = aguiState;
    }
  }
}
