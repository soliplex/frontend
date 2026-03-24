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
    required String threadId,
  })  : _connection = connection,
        _roomId = roomId,
        _threadId = threadId {
    _fetch();
  }

  final ServerConnection _connection;
  final String _roomId;
  final String _threadId;
  CancelToken? _cancelToken;

  String get threadId => _threadId;

  final Signal<ThreadViewStatus> _messages =
      Signal<ThreadViewStatus>(MessagesLoading());
  ReadonlySignal<ThreadViewStatus> get messages => _messages;

  void refresh() => _fetch();

  void _fetch() {
    _cancelToken?.cancel('re-fetch');
    final token = CancelToken();
    _cancelToken = token;

    _messages.value = MessagesLoading();

    _connection.api
        .getThreadHistory(_roomId, _threadId, cancelToken: token)
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
  }
}
