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

  /// Cancels any in-flight fetch so its completion can't overwrite a local
  /// mutation. Only safe to call when we're about to write authoritative
  /// state derived from an existing [ThreadsLoaded] baseline — otherwise
  /// we'd be cancelling work we have nothing to replace with.
  void _cancelInFlightFetch() {
    _cancelToken?.cancel('local mutation');
    _cancelToken = null;
  }

  /// Creates a new thread on the backend and reflects it in the local list.
  ///
  /// Returns the server's [ThreadInfo] plus the initial AGUI state the
  /// caller needs to seed into the agent runtime, or `null` if this state
  /// was disposed before the call could complete.
  Future<(ThreadInfo, Map<String, dynamic>)?> createThread() async {
    if (_isDisposed) return null;
    final result = await _connection.api.createThread(_roomId);
    if (_isDisposed) return null;
    _insertLocally(result.$1);
    return result;
  }

  /// Reflects a thread that was created outside this class — specifically,
  /// by the agent runtime during an implicit spawn (see
  /// [RoomState.sendToNewThread]). Does **not** call the backend: the
  /// thread already exists server-side by the time this runs.
  void noteSpawnedThread(ThreadInfo thread) {
    if (_isDisposed) return;
    _insertLocally(thread);
  }

  void _insertLocally(ThreadInfo thread) {
    final current = _threads.value;
    if (current is ThreadsLoaded) {
      _cancelInFlightFetch();
      if (current.threads.any((t) => t.id == thread.id)) return;
      final updated = [...current.threads, thread]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _threads.value = ThreadsLoaded(updated);
      return;
    }
    // No loaded baseline to merge into. The thread already exists
    // server-side; let a fresh fetch populate the full list rather than
    // synthesizing a single-element ThreadsLoaded here.
    unawaited(_fetch());
  }

  Future<void> deleteThread(String threadId) async {
    if (_isDisposed) return;
    await _connection.api.deleteThread(_roomId, threadId);
    if (_isDisposed) return;
    final latest = _threads.value;
    if (latest is ThreadsLoaded) {
      _cancelInFlightFetch();
      final updated = latest.threads.where((t) => t.id != threadId).toList();
      _threads.value = ThreadsLoaded(updated);
      return;
    }
    // Same reasoning as [_insertLocally]: no baseline to merge into; re-fetch.
    unawaited(_fetch());
  }

  Future<void> renameThread(String threadId, String name) async {
    assert(name.trim().isNotEmpty, 'caller must not submit an empty name');
    if (_isDisposed) return;

    // The backend replaces all metadata on update, so we must re-send
    // existing fields to avoid losing them.
    final current = _threads.value;
    if (current is! ThreadsLoaded) {
      throw StateError(
        'Cannot rename: thread list not loaded. '
        'Existing metadata would be lost.',
      );
    }
    final existing = current.threads.where((t) => t.id == threadId).firstOrNull;
    if (existing == null) {
      throw StateError(
        'Cannot rename thread $threadId: not in cached list. '
        'Existing metadata would be lost.',
      );
    }
    final rawDesc = existing.description;
    final description = rawDesc.isNotEmpty ? rawDesc : null;

    await _connection.api.updateThreadMetadata(
      _roomId,
      threadId,
      name: name,
      description: description,
    );
    if (_isDisposed) return;

    final latest = _threads.value;
    if (latest is ThreadsLoaded) {
      _cancelInFlightFetch();
      final updated = latest.threads.map((t) {
        if (t.id == threadId) return t.copyWith(name: name);
        return t;
      }).toList();
      _threads.value = ThreadsLoaded(updated);
      return;
    }
    // State transitioned to non-Loaded during the await (no current code
    // path does this, but it's cheap to handle). Server already has the
    // new name; a fresh fetch reconciles.
    unawaited(_fetch());
  }

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
