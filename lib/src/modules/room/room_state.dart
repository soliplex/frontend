import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart';

import 'agent_runtime_manager.dart';
import 'run_registry.dart';
import 'thread_list_state.dart';
import 'thread_view_state.dart';

export 'send_error.dart';

sealed class RoomStatus {}

class RoomLoading extends RoomStatus {}

class RoomLoaded extends RoomStatus {
  RoomLoaded(this.room);
  final Room room;
}

class RoomFailed extends RoomStatus {
  RoomFailed(this.error);
  final Object error;
}

class RoomState {
  RoomState({
    required ServerConnection connection,
    required String roomId,
    required AgentRuntimeManager runtimeManager,
    required RunRegistry registry,
    this.onNavigateToThread,
  })  : _connection = connection,
        _roomId = roomId,
        _runtimeManager = runtimeManager,
        _registry = registry,
        threadList = ThreadListState(
          connection: connection,
          roomId: roomId,
        ) {
    _fetchRoom();
  }

  final ServerConnection _connection;
  final String _roomId;
  final AgentRuntimeManager _runtimeManager;
  final RunRegistry _registry;
  final void Function(String threadId)? onNavigateToThread;

  final ThreadListState threadList;
  ThreadViewState? _activeThreadView;
  CancelToken? _roomFetchToken;
  Future<AgentSession>? _pendingSpawn;
  bool _isDisposed = false;

  final Signal<RoomStatus> _room = Signal<RoomStatus>(RoomLoading());
  ReadonlySignal<RoomStatus> get room => _room;

  final Signal<AgentSessionState?> _sessionState =
      Signal<AgentSessionState?>(null);
  ReadonlySignal<AgentSessionState?> get sessionState => _sessionState;

  final Signal<SendError?> _lastError = Signal<SendError?>(null);
  ReadonlySignal<SendError?> get lastError => _lastError;

  void clearError() => _lastError.value = null;

  void _fetchRoom() {
    final token = CancelToken();
    _roomFetchToken = token;
    _connection.api.getRoom(_roomId, cancelToken: token).then((room) {
      if (token.isCancelled) return;
      _roomFetchToken = null;
      _room.value = RoomLoaded(room);
    }).catchError((Object error) {
      if (token.isCancelled) return;
      _roomFetchToken = null;
      _room.value = RoomFailed(error);
    });
  }

  ThreadViewState? get activeThreadView => _activeThreadView;

  AgentRuntime get runtime => _runtimeManager.getRuntime(_connection);

  void selectThread(String threadId) {
    if (_activeThreadView?.threadId == threadId) return;
    _activeThreadView?.dispose();
    _activeThreadView = ThreadViewState(
      connection: _connection,
      roomId: _roomId,
      threadId: threadId,
      registry: _registry,
    );
  }

  /// Explicit thread creation (the "+" button path).
  Future<String?> createThread() async {
    _lastError.value = null;
    try {
      final (threadInfo, _) = await _connection.api.createThread(_roomId);
      if (_isDisposed) return threadInfo.id;
      threadList.refresh();
      selectThread(threadInfo.id);
      onNavigateToThread?.call(threadInfo.id);
      return threadInfo.id;
    } on Object catch (error) {
      if (_isDisposed) return null;
      _lastError.value = SendError(error);
      return null;
    }
  }

  /// Implicit thread creation (send message with no thread selected).
  ///
  /// Spawns a session which creates the thread server-side, then creates a
  /// [ThreadViewState] and attaches the session to it.
  void cancelSpawn() {
    final pending = _pendingSpawn;
    if (pending == null) return;
    _pendingSpawn = null;
    _sessionState.value = null;
    unawaited(pending.then((s) {
      s.cancel();
      s.dispose();
    }).catchError((Object e) {
      debugPrint('Cancelled spawn cleanup failed: $e');
    }));
  }

  Future<void> sendToNewThread(String prompt) async {
    if (_sessionState.value != null) return;
    _lastError.value = null;
    _sessionState.value = AgentSessionState.spawning;
    Future<AgentSession>? spawnFuture;
    try {
      spawnFuture = runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
      );
      _pendingSpawn = spawnFuture;
      final session = await spawnFuture;
      if (_pendingSpawn != spawnFuture) return;
      _pendingSpawn = null;
      final key = session.threadKey;
      _registry.register(key, session);
      if (_isDisposed) return;
      threadList.refresh();
      selectThread(key.threadId);
      _activeThreadView!.attachSession(session);
      onNavigateToThread?.call(key.threadId);
    } on Object catch (error) {
      if (_isDisposed) return;
      _lastError.value = SendError(error, unsentText: prompt);
    } finally {
      if (_pendingSpawn == spawnFuture) {
        _pendingSpawn = null;
        _sessionState.value = null;
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    cancelSpawn();
    _roomFetchToken?.cancel('disposed');
    threadList.dispose();
    _activeThreadView?.dispose();
  }
}
