import 'package:soliplex_agent/soliplex_agent.dart';

import 'agent_runtime_manager.dart';
import 'thread_list_state.dart';
import 'thread_view_state.dart';

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
        );

  final ServerConnection _connection;
  final String _roomId;
  final AgentRuntimeManager _runtimeManager;
  final void Function(String threadId)? onNavigateToThread;

  final ThreadListState threadList;
  ThreadViewState? _activeThreadView;

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
  Future<String> createThread() async {
    final (threadInfo, _) = await _connection.api.createThread(_roomId);
    threadList.refresh();
    selectThread(threadInfo.id);
    onNavigateToThread?.call(threadInfo.id);
    return threadInfo.id;
  }

  /// Implicit thread creation (send message with no thread selected).
  ///
  /// Spawns a session which creates the thread server-side, then creates a
  /// [ThreadViewState] and attaches the session to it.
  Future<void> sendToNewThread(String prompt) async {
    final session = await runtime.spawn(
      roomId: _roomId,
      prompt: prompt,
    );
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
  }

  void dispose() {
    threadList.dispose();
    _activeThreadView?.dispose();
  }
}
