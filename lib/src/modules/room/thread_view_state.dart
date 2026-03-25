import 'package:soliplex_agent/soliplex_agent.dart';

sealed class ThreadViewStatus {}

class MessagesLoading extends ThreadViewStatus {}

class MessagesLoaded extends ThreadViewStatus {
  MessagesLoaded({required this.messages, required this.messageStates});
  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;
}

class MessagesFailed extends ThreadViewStatus {
  MessagesFailed(this.error);
  final Object error;
}

class ThreadViewState {
  ThreadViewState({
    required ServerConnection connection,
    required String roomId,
    required this.threadId,
  })  : _connection = connection,
        _roomId = roomId {
    _fetch();
  }

  final ServerConnection _connection;
  final String _roomId;
  final String threadId;
  CancelToken? _cancelToken;
  AgentSession? _activeSession;
  void Function()? _runStateUnsub;

  final Signal<ThreadViewStatus> _messages =
      Signal<ThreadViewStatus>(MessagesLoading());
  ReadonlySignal<ThreadViewStatus> get messages => _messages;

  final Signal<StreamingState?> _streamingState = Signal<StreamingState?>(null);
  ReadonlySignal<StreamingState?> get streamingState => _streamingState;

  final Signal<AgentSessionState?> _sessionState =
      Signal<AgentSessionState?>(null);
  ReadonlySignal<AgentSessionState?> get sessionState => _sessionState;

  void refresh() => _fetch();

  Future<void> sendMessage(String prompt, AgentRuntime runtime) async {
    try {
      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
        threadId: threadId,
      );
      _attachSession(session);
    } on Object catch (error) {
      _messages.value = MessagesFailed(error);
    }
  }

  void attachSession(AgentSession session) {
    _attachSession(session);
  }

  void cancelRun() {
    _activeSession?.cancel();
  }

  void _attachSession(AgentSession session) {
    _activeSession = session;
    _sessionState.value = session.state;
    _runStateUnsub = session.runState.subscribe(_onRunState);
  }

  void _onRunState(RunState runState) {
    switch (runState) {
      case RunningState(:final conversation, :final streaming):
        _messages.value = MessagesLoaded(
          messages: conversation.messages,
          messageStates: conversation.messageStates,
        );
        _streamingState.value = streaming;
        _sessionState.value = AgentSessionState.running;
      case CompletedState():
      case FailedState():
      case CancelledState():
        _detachSession();
        _fetch();
      case IdleState():
      case ToolYieldingState():
        break;
    }
  }

  void _detachSession() {
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _activeSession = null;
    _streamingState.value = null;
    _sessionState.value = null;
  }

  void _fetch() {
    _cancelToken?.cancel('re-fetch');
    final token = CancelToken();
    _cancelToken = token;

    _messages.value = MessagesLoading();

    _connection.api
        .getThreadHistory(_roomId, threadId, cancelToken: token)
        .then((history) {
      if (token.isCancelled) return;
      _cancelToken = null;
      _messages.value = MessagesLoaded(
        messages: history.messages,
        messageStates: history.messageStates,
      );
    }).catchError((Object error) {
      if (token.isCancelled) return;
      _cancelToken = null;
      _messages.value = MessagesFailed(error);
    });
  }

  void dispose() {
    _cancelToken?.cancel('disposed');
    _detachSession();
  }
}
