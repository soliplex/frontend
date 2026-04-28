import 'dart:async' show unawaited;

import 'package:soliplex_agent/soliplex_agent.dart';

import '../auth/server_entry.dart';
import 'agent_runtime_manager.dart';
import 'run_registry.dart';
import 'session_spawner.dart';
import 'thread_list_state.dart';
import 'thread_view_state.dart';
import 'upload_tracker.dart';
import 'upload_tracker_registry.dart';

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
    required ServerEntry serverEntry,
    required String roomId,
    required AgentRuntimeManager runtimeManager,
    required RunRegistry registry,
    required UploadTrackerRegistry uploadRegistry,
    this.onNavigateToThread,
  })  : _connection = serverEntry.connection,
        _roomId = roomId,
        _runtimeManager = runtimeManager,
        _registry = registry,
        threadList = ThreadListState(
          connection: serverEntry.connection,
          roomId: roomId,
        ),
        uploadTracker =
            uploadRegistry.trackerFor(entry: serverEntry, roomId: roomId) {
    _fetchRoom();
    // Every room entry forces a refresh so the list reflects server
    // state from other devices and self-heals any pending record that
    // got stuck behind a transient refresh failure.
    unawaited(uploadTracker.refreshRoom(_roomId));
  }

  final ServerConnection _connection;
  final String _roomId;
  final AgentRuntimeManager _runtimeManager;
  final RunRegistry _registry;
  final void Function(String? threadId)? onNavigateToThread;

  final ThreadListState threadList;

  /// Shared tracker; lifecycle owned by [UploadTrackerRegistry].
  final UploadTracker uploadTracker;
  ThreadViewState? _activeThreadView;
  CancelToken? _roomFetchToken;
  bool _isDisposed = false;

  final SessionSpawner _spawner = SessionSpawner();

  final Signal<RoomStatus> _room = Signal<RoomStatus>(RoomLoading());
  ReadonlySignal<RoomStatus> get room => _room;

  late final ReadonlySignal<Set<String>> runningThreadIds =
      computed<Set<String>>(
    () => _registry.activeKeys.value
        .where((k) => k.serverId == _connection.serverId && k.roomId == _roomId)
        .map((k) => k.threadId)
        .toSet(),
  );

  /// Tracks the spawn lifecycle: null → spawning → null.
  /// Non-null while a new-thread spawn is in progress.
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
      onHistoryLoaded: (id, history) {
        runtime.seedThreadHistory(
          (
            serverId: _connection.serverId,
            roomId: _roomId,
            threadId: id,
          ),
          history,
        );
      },
    );
    // Thread switch → force a refresh for the same reasons as room
    // entry. Reselecting the same thread is a no-op earlier in the
    // method, so this doesn't fire spuriously.
    unawaited(uploadTracker.refreshThread(_roomId, threadId));
  }

  /// Explicit thread creation (the "+" button path).
  Future<String?> createThread() async {
    _lastError.value = null;
    try {
      final result = await threadList.createThread();
      if (result == null) return null; // disposed
      final (threadInfo, aguiState) = result;
      if (_isDisposed) return threadInfo.id;
      runtime.seedThreadState(
        (
          serverId: _connection.serverId,
          roomId: _roomId,
          threadId: threadInfo.id,
        ),
        aguiState,
      );
      selectThread(threadInfo.id);
      onNavigateToThread?.call(threadInfo.id);
      return threadInfo.id;
    } on Object catch (error) {
      if (_isDisposed) return null;
      _lastError.value = SendError(error);
      return null;
    }
  }

  /// Deletes a thread. Disposes the active view if it belongs to this
  /// thread. Navigates to the next available thread, or null if none.
  Future<void> deleteThread(String threadId) async {
    // Pick the next thread from the list we can *see now*. Reading after
    // the await risks seeing a list that a concurrent fetch has replaced
    // (e.g., with ThreadsLoading). If we can't see a Loaded list now,
    // there's no successor to pick and we'll navigate to null.
    final nextThreadId = _pickNextThreadId(excluding: threadId);

    await threadList.deleteThread(threadId);

    if (_activeThreadView?.threadId == threadId) {
      _activeThreadView?.cancelRun();
      _activeThreadView?.dispose();
      _activeThreadView = null;

      if (nextThreadId != null) selectThread(nextThreadId);
      onNavigateToThread?.call(nextThreadId);
    }
  }

  String? _pickNextThreadId({required String excluding}) {
    final current = threadList.threads.value;
    if (current is! ThreadsLoaded) return null;
    for (final t in current.threads) {
      if (t.id != excluding) return t.id;
    }
    return null;
  }

  /// Cancels a pending new-thread spawn. No-op if nothing is in progress.
  void cancelSpawn() {
    if (_spawner.cancel()) _sessionState.value = null;
  }

  /// Implicit thread creation (send message with no thread selected).
  ///
  /// Spawns a session which creates the thread server-side, then creates a
  /// [ThreadViewState] and attaches the session to it.
  Future<void> sendToNewThread(
    String prompt, {
    Map<String, dynamic>? stateOverlay,
  }) =>
      _spawner.spawn(
        spawnFn: () => runtime.spawn(
          roomId: _roomId,
          prompt: prompt,
          stateOverlay: stateOverlay,
        ),
        errorSignal: _lastError,
        prompt: prompt,
        isDisposed: () => _isDisposed,
        onSpawned: (session) {
          // Clear room-level spawn state — the thread view takes over.
          _sessionState.value = null;
          final key = session.threadKey;
          _registry.register(key, session);
          if (_isDisposed) return;
          // Spawn only exposes a threadKey — no ThreadInfo. Insert a stub so
          // the sidebar reflects the new thread immediately. The backend
          // generates the thread's name lazily after the run finishes; the
          // sidebar picks that up on the next natural refresh (room change,
          // pull-to-refresh, re-entry).
          threadList.noteSpawnedThread(ThreadInfo(
            id: key.threadId,
            roomId: _roomId,
            createdAt: DateTime.now(),
          ));
          selectThread(key.threadId);
          _activeThreadView!.attachSession(session);
          onNavigateToThread?.call(key.threadId);
        },
        onStateTransition: (state) {
          if (_isDisposed) return;
          _sessionState.value = state;
        },
      );

  void dispose() {
    _isDisposed = true;
    _roomFetchToken?.cancel('disposed');
    threadList.dispose();
    _activeThreadView?.dispose();
    _sessionState.dispose();
    runningThreadIds.dispose();
  }
}
