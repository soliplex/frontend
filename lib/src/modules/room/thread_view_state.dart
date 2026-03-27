import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';
import 'send_error.dart';

export 'send_error.dart';

/// Sentinel key for the execution tracker created before a message ID is known.
const awaitingTrackerKey = '_awaiting';

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
  bool _isDisposed = false;

  final Signal<ThreadViewStatus> _messages =
      Signal<ThreadViewStatus>(MessagesLoading());
  ReadonlySignal<ThreadViewStatus> get messages => _messages;

  final Signal<StreamingState?> _streamingState = Signal<StreamingState?>(null);
  ReadonlySignal<StreamingState?> get streamingState => _streamingState;

  final Signal<AgentSessionState?> _sessionState =
      Signal<AgentSessionState?>(null);
  ReadonlySignal<AgentSessionState?> get sessionState => _sessionState;

  final Signal<SendError?> _lastSendError = Signal<SendError?>(null);
  ReadonlySignal<SendError?> get lastSendError => _lastSendError;

  final Map<String, ExecutionTracker> _executionTrackers = {};
  Map<String, ExecutionTracker> get executionTrackers =>
      Map.unmodifiable(_executionTrackers);

  String? _activeTrackerMessageId;

  void clearSendError() => _lastSendError.value = null;

  void refresh() => _fetch();

  Future<void> sendMessage(String prompt, AgentRuntime runtime) async {
    _lastSendError.value = null;
    final current = _messages.value;
    final cachedHistory = current is MessagesLoaded
        ? ThreadHistory(
            messages: current.messages,
            messageStates: current.messageStates,
          )
        : null;
    try {
      final session = await runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
        threadId: threadId,
        cachedHistory: cachedHistory,
      );
      if (_isDisposed) return;
      _attachSession(session);
    } on Object catch (error) {
      if (_isDisposed) return;
      _lastSendError.value = SendError(error, unsentText: prompt);
    }
  }

  void attachSession(AgentSession session) {
    _attachSession(session);
  }

  void cancelRun() {
    _activeSession?.cancel();
  }

  void _attachSession(AgentSession session) {
    if (_isDisposed) return;
    _detachSession();
    _cancelToken?.cancel('session attached');
    _activeSession = session;
    _sessionState.value = session.state;
    _runStateUnsub = session.runState.subscribe(_onRunState);
  }

  void _onRunState(RunState runState) {
    switch (runState) {
      case RunningState(:final conversation, :final streaming):
        _messages.value = _loadedFrom(conversation);
        _streamingState.value = streaming;
        _sessionState.value = AgentSessionState.running;
        if (streaming is TextStreaming &&
            _activeTrackerMessageId != streaming.messageId) {
          if (_activeTrackerMessageId == awaitingTrackerKey) {
            // Re-key the awaiting tracker to the actual message ID
            final tracker = _executionTrackers.remove(awaitingTrackerKey);
            if (tracker != null) {
              _executionTrackers[streaming.messageId] = tracker;
            }
          } else {
            _freezeActiveTracker();
            _executionTrackers[streaming.messageId] = ExecutionTracker(
              executionEvents: _activeSession!.lastExecutionEvent,
            );
          }
          _activeTrackerMessageId = streaming.messageId;
        } else if (streaming is AwaitingText &&
            _activeTrackerMessageId == null &&
            _activeSession != null) {
          _activeTrackerMessageId = awaitingTrackerKey;
          _executionTrackers[awaitingTrackerKey] = ExecutionTracker(
            executionEvents: _activeSession!.lastExecutionEvent,
          );
        }
      case CompletedState(:final conversation):
        _freezeActiveTracker();
        _detachSession();
        _messages.value = _loadedFrom(conversation);
      case FailedState(:final conversation, :final error):
        _freezeActiveTracker();
        _detachSession();
        _lastSendError.value = SendError(error);
        if (conversation != null) {
          _messages.value = _loadedFrom(conversation);
        }
      case CancelledState(:final conversation):
        _freezeActiveTracker();
        _detachSession();
        if (conversation != null) {
          _messages.value = _loadedFrom(conversation);
        }
      case IdleState():
      case ToolYieldingState():
        break;
    }
  }

  void _freezeActiveTracker() {
    if (_activeTrackerMessageId != null) {
      _executionTrackers[_activeTrackerMessageId!]?.freeze();
      _activeTrackerMessageId = null;
    }
  }

  static MessagesLoaded _loadedFrom(Conversation conversation) =>
      MessagesLoaded(
        messages: conversation.messages,
        messageStates: conversation.messageStates,
      );

  void _detachSession() {
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _activeSession = null;
    _streamingState.value = null;
    _sessionState.value = null;
  }

  void _fetch() {
    if (_isDisposed) return;
    _cancelToken?.cancel('re-fetch');
    final token = CancelToken();
    _cancelToken = token;

    if (_messages.value is! MessagesLoaded) {
      _messages.value = MessagesLoading();
    }

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
      if (_messages.value is! MessagesLoaded) {
        _messages.value = MessagesFailed(error);
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _cancelToken?.cancel('disposed');
    _detachSession();
    for (final tracker in _executionTrackers.values) {
      tracker.dispose();
    }
    _executionTrackers.clear();
  }
}
