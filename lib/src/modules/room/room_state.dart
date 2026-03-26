import 'package:soliplex_agent/soliplex_agent.dart';

import 'agent_runtime_manager.dart';
import 'thread_list_state.dart';
import 'thread_view_state.dart';

export 'thread_view_state.dart' show SendError;

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
    this.onNavigateToThread,
  })  : _connection = connection,
        _roomId = roomId,
        _runtimeManager = runtimeManager,
        threadList = ThreadListState(
          connection: connection,
          roomId: roomId,
        ) {
    _fetchRoom();
  }

  final ServerConnection _connection;
  final String _roomId;
  final AgentRuntimeManager _runtimeManager;
  final void Function(String threadId)? onNavigateToThread;

  final ThreadListState threadList;
  ThreadViewState? _activeThreadView;
  bool _isDisposed = false;

  final Signal<RoomStatus> _room = Signal<RoomStatus>(RoomLoading());
  ReadonlySignal<RoomStatus> get room => _room;

  final Signal<SendError?> _lastError = Signal<SendError?>(null);
  ReadonlySignal<SendError?> get lastError => _lastError;

  void clearError() => _lastError.value = null;

  void _fetchRoom() {
    _connection.api.getRooms().then((rooms) {
      if (_isDisposed) return;
      final match = rooms.where((r) => r.id == _roomId).firstOrNull;
      if (match != null) {
        _room.value = RoomLoaded(match);
      } else {
        _room.value = RoomFailed(StateError('Room $_roomId not found'));
      }
    }).catchError((Object error) {
      if (_isDisposed) return;
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
  Future<void> sendToNewThread(String prompt) async {
    _lastError.value = null;
    try {
      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
      );
      if (_isDisposed) return;
      final newThreadId = session.threadKey.threadId;
      threadList.refresh();

      _activeThreadView?.dispose();
      _activeThreadView = ThreadViewState(
        connection: _connection,
        roomId: _roomId,
        threadId: newThreadId,
      );
      _activeThreadView!.attachSession(session);
      onNavigateToThread?.call(newThreadId);
    } on Object catch (error) {
      if (_isDisposed) return;
      _lastError.value = SendError(error, unsentText: prompt);
    }
  }

  void dispose() {
    _isDisposed = true;
    threadList.dispose();
    _activeThreadView?.dispose();
  }
}
