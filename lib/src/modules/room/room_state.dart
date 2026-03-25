import 'package:soliplex_agent/soliplex_agent.dart';

import 'thread_list_state.dart';
import 'thread_view_state.dart';

class RoomState {
  RoomState({
    required ServerConnection connection,
    required String roomId,
  })  : _connection = connection,
        _roomId = roomId,
        threadList = ThreadListState(
          connection: connection,
          roomId: roomId,
        );

  final ServerConnection _connection;
  final String _roomId;

  final ThreadListState threadList;
  ThreadViewState? _activeThreadView;

  ThreadViewState? get activeThreadView => _activeThreadView;

  void selectThread(String threadId) {
    if (_activeThreadView?.threadId == threadId) return;
    _activeThreadView?.dispose();
    _activeThreadView = ThreadViewState(
      connection: _connection,
      roomId: _roomId,
      threadId: threadId,
    );
  }

  void dispose() {
    threadList.dispose();
    _activeThreadView?.dispose();
  }
}
