import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';
import 'run_registry.dart';
import 'send_error.dart';
import 'tracker_registry.dart';

export 'send_error.dart';

sealed class ThreadViewStatus {}

class MessagesLoading extends ThreadViewStatus {}

class MessagesLoaded extends ThreadViewStatus {
  MessagesLoaded({required this.messages, required this.messageStates});
  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessagesLoaded &&
          identical(messages, other.messages) &&
          identical(messageStates, other.messageStates);

  @override
  int get hashCode => Object.hash(messages, messageStates);
}

class MessagesFailed extends ThreadViewStatus {
  MessagesFailed(this.error);
  final Object error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessagesFailed && identical(error, other.error);

  @override
  int get hashCode => error.hashCode;
}

/// Callback invoked when thread history is loaded from the server.
///
/// Provides the thread ID and the full loaded history so callers can
/// seed the runtime's thread history cache with messages and AG-UI state.
typedef HistoryLoadedCallback = void Function(
  String threadId,
  ThreadHistory history,
);

class ThreadViewState {
  ThreadViewState({
    required ServerConnection connection,
    required String roomId,
    required this.threadId,
    required RunRegistry registry,
    this.onHistoryLoaded,
  })  : _connection = connection,
        _roomId = roomId,
        _registry = registry {
    if (!_restoreFromRegistry()) _fetch();
  }

  final ServerConnection _connection;
  final String _roomId;
  final String threadId;
  final HistoryLoadedCallback? onHistoryLoaded;
  final RunRegistry _registry;

  ThreadKey get threadKey => (
        serverId: _connection.serverId,
        roomId: _roomId,
        threadId: threadId,
      );

  CancelToken? _cancelToken;
  AgentSession? _activeSession;
  Future<AgentSession>? _pendingSpawn;
  void Function()? _runStateUnsub;
  void Function()? _approvalUnsub;
  bool _isDisposed = false;

  final Signal<ThreadViewStatus> _messages =
      Signal<ThreadViewStatus>(MessagesLoading());
  ReadonlySignal<ThreadViewStatus> get messages => _messages;

  final Signal<StreamingState?> _streamingState = Signal<StreamingState?>(null);
  ReadonlySignal<StreamingState?> get streamingState => _streamingState;

  // Lifecycle: null → spawning (sendMessage) → running (_onRunState)
  //            → null (_detachSession on terminal state, or cancelRun).
  //            Doubles as a concurrency guard (sendMessage rejects if non-null)
  //            and the UI signal for ChatInput's cancel button.
  final Signal<AgentSessionState?> _sessionState =
      Signal<AgentSessionState?>(null);
  ReadonlySignal<AgentSessionState?> get sessionState => _sessionState;

  final Signal<SendError?> _lastSendError = Signal<SendError?>(null);
  ReadonlySignal<SendError?> get lastSendError => _lastSendError;

  final Signal<PendingApprovalRequest?> _pendingApproval =
      Signal<PendingApprovalRequest?>(null);
  ReadonlySignal<PendingApprovalRequest?> get pendingApproval =>
      _pendingApproval;

  final TrackerRegistry _trackerRegistry = TrackerRegistry();
  Map<String, ExecutionTracker> get executionTrackers =>
      _trackerRegistry.trackers;

  void submitFeedback(String runId, FeedbackType feedback, String? reason) {
    unawaited(
      _connection.api
          .submitFeedback(_roomId, threadId, runId, feedback, reason: reason)
          .catchError((Object e) {
        debugPrint('Feedback submission failed: $e');
      }),
    );
  }

  void clearSendError() => _lastSendError.value = null;

  void refresh() => _fetch();

  Future<void> sendMessage(
    String prompt,
    AgentRuntime runtime, {
    Map<String, dynamic>? stateOverlay,
  }) async {
    if (_sessionState.value != null) return;
    _lastSendError.value = null;
    _sessionState.value = AgentSessionState.spawning;
    Future<AgentSession>? spawnFuture;
    try {
      spawnFuture = runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
        threadId: threadId,
        stateOverlay: stateOverlay,
      );
      _pendingSpawn = spawnFuture;
      final session = await spawnFuture;
      if (_pendingSpawn != spawnFuture) return;
      _pendingSpawn = null;
      _registry.register(threadKey, session);
      if (_isDisposed) return;
      _attachSession(session);
    } on Object catch (error) {
      if (_isDisposed || _sessionState.value == null) return;
      _lastSendError.value = SendError(error, unsentText: prompt);
    } finally {
      if (_pendingSpawn == spawnFuture) {
        _pendingSpawn = null;
        _sessionState.value = null;
      }
    }
  }

  void attachSession(AgentSession session) {
    _attachSession(session);
  }

  void cancelRun() {
    if (_cancelPendingSpawn()) return;
    _activeSession?.cancel();
  }

  void approveToolCall(String toolCallId) =>
      _activeSession?.approveToolCall(toolCallId);

  void denyToolCall(String toolCallId) =>
      _activeSession?.denyToolCall(toolCallId);

  /// Cancels a pending spawn if one exists. Returns true if a spawn was
  /// cancelled, false if there was nothing pending.
  bool _cancelPendingSpawn() {
    final pending = _pendingSpawn;
    if (pending == null) return false;
    _pendingSpawn = null;
    _sessionState.value = null;
    unawaited(pending.then((s) {
      s.cancel();
      s.dispose();
    }).catchError((Object e) {
      debugPrint('Cancelled spawn cleanup failed: $e');
    }));
    return true;
  }

  void _attachSession(AgentSession session) {
    if (_isDisposed) return;
    _detachSession();
    _cancelToken?.cancel('session attached');
    _activeSession = session;
    _sessionState.value = session.state;
    _runStateUnsub = session.runState.subscribe(_onRunState);
    _approvalUnsub =
        session.pendingApproval.subscribe((r) => _pendingApproval.value = r);
  }

  void _onRunState(RunState runState) {
    final session = _activeSession;
    if (session == null) return;
    switch (runState) {
      case RunningState(:final conversation, :final streaming):
        final current = _messages.value;
        if (current is! MessagesLoaded ||
            !identical(current.messages, conversation.messages)) {
          _messages.value = _messagesLoaded(conversation);
        }
        _streamingState.value = streaming;
        _sessionState.value = AgentSessionState.running;
        _trackerRegistry.onStreaming(
          streaming,
          session.lastExecutionEvent,
        );
      case CompletedState(:final conversation):
        _trackerRegistry.onRunTerminated();
        _detachSession();
        _messages.value = _messagesLoaded(conversation);
      case FailedState(:final conversation, :final error):
        _trackerRegistry.onRunTerminated();
        _detachSession();
        _lastSendError.value = SendError(error);
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case CancelledState(:final conversation):
        _trackerRegistry.onRunTerminated();
        _detachSession();
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case IdleState():
      case ToolYieldingState():
        break;
    }
  }

  MessagesLoaded _messagesLoaded(Conversation conversation) {
    final existing = switch (_messages.value) {
      MessagesLoaded(:final messageStates) => messageStates,
      _ => const <String, MessageState>{},
    };
    final merged = {...existing, ...conversation.messageStates};
    return MessagesLoaded(
      messages: conversation.messages,
      messageStates: merged,
    );
  }

  void _detachSession() {
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _approvalUnsub?.call();
    _approvalUnsub = null;
    _activeSession = null;
    _streamingState.value = null;
    _sessionState.value = null;
    _pendingApproval.value = null;
  }

  bool _restoreFromRegistry() {
    final session = _registry.activeSession(threadKey);
    if (session != null) {
      _attachSession(session);
      return true;
    }
    final outcome = _registry.completedOutcome(threadKey);
    if (outcome != null) {
      _applyOutcome(outcome);
      return true;
    }
    return false;
  }

  void _applyOutcome(RunOutcome outcome) {
    switch (outcome) {
      case CompletedRun(:final conversation):
        _messages.value = _messagesLoaded(conversation);
      case FailedRun(:final conversation, :final error):
        _lastSendError.value = SendError(error);
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case CancelledRun(:final conversation):
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
    }
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
      onHistoryLoaded?.call(threadId, history);
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
    _trackerRegistry.dispose();
  }
}
