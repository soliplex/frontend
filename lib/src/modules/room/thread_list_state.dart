import 'dart:async';
import 'dart:developer' as dev;

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
    unawaited(_fetch());
  }

  final ServerConnection _connection;
  final String _roomId;
  CancelToken? _cancelToken;
  bool _isDisposed = false;

  final Signal<ThreadListStatus> _threads =
      Signal<ThreadListStatus>(ThreadsLoading());
  ReadonlySignal<ThreadListStatus> get threads => _threads;

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    if (_isDisposed) return;
    _cancelToken?.cancel('re-fetch');
    final token = CancelToken();
    _cancelToken = token;

    if (_threads.value is! ThreadsLoaded) {
      _threads.value = ThreadsLoading();
    }

    try {
      final threads =
          await _connection.api.getThreads(_roomId, cancelToken: token);
      if (token.isCancelled) return;
      _cancelToken = null;
      final sorted = threads.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _threads.value = ThreadsLoaded(sorted);
    } on Object catch (error) {
      if (token.isCancelled) return;
      _cancelToken = null;
      // Preserve existing loaded threads on refresh failure.
      if (_threads.value is ThreadsLoaded) {
        dev.log(
          'Thread refresh failed, keeping stale list',
          error: error,
          name: 'ThreadListState',
        );
      } else {
        _threads.value = ThreadsFailed(error);
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _cancelToken?.cancel('disposed');
  }
}
