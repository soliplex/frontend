import 'package:soliplex_agent/soliplex_agent.dart';

sealed class ThreadListStatus {}

class ThreadsLoading extends ThreadListStatus {}

class ThreadsLoaded extends ThreadListStatus {
  ThreadsLoaded(this.threads);
  final List<ThreadInfo> threads;
}

class ThreadsFailed extends ThreadListStatus {
  ThreadsFailed(this.error);
  final Object error;
}

class ThreadListState {
  ThreadListState({
    required ServerConnection connection,
    required String roomId,
  })  : _connection = connection,
        _roomId = roomId {
    _fetch();
  }

  final ServerConnection _connection;
  final String _roomId;
  CancelToken? _cancelToken;

  final Signal<ThreadListStatus> _threads =
      Signal<ThreadListStatus>(ThreadsLoading());
  ReadonlySignal<ThreadListStatus> get threads => _threads;

  void refresh() => _fetch();

  void _fetch() {
    _cancelToken?.cancel('re-fetch');
    final token = CancelToken();
    _cancelToken = token;

    _threads.value = ThreadsLoading();

    _connection.api.getThreads(_roomId, cancelToken: token).then((threads) {
      if (token.isCancelled) return;
      _cancelToken = null;
      final sorted = threads.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _threads.value = ThreadsLoaded(sorted);
    }).catchError((Object error) {
      if (token.isCancelled) return;
      _cancelToken = null;
      _threads.value = ThreadsFailed(error);
    });
  }

  void dispose() {
    _cancelToken?.cancel('disposed');
  }
}
