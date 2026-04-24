import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';
import 'execution_tracker_extension.dart';
import 'historical_replay.dart';
import 'tool_calls_extension.dart';
import 'run_registry.dart';
import 'send_error.dart';
import 'session_spawner.dart';

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
  void Function()? _runStateUnsub;
  bool _isDisposed = false;

  final SessionSpawner _spawner = SessionSpawner();

  final Signal<ThreadViewStatus> _messages =
      Signal<ThreadViewStatus>(MessagesLoading());
  ReadonlySignal<ThreadViewStatus> get messages => _messages;

  final Signal<StreamingState?> _streamingState = Signal<StreamingState?>(null);
  ReadonlySignal<StreamingState?> get streamingState => _streamingState;

  /// Tracks the session lifecycle: null → spawning → running → null.
  /// Driven by [_spawner] during spawn (via its state-transition callback)
  /// and updated directly here for attach, running, and detach transitions.
  final Signal<AgentSessionState?> _sessionState =
      Signal<AgentSessionState?>(null);
  ReadonlySignal<AgentSessionState?> get sessionState => _sessionState;

  final Signal<SendError?> _lastSendError = Signal<SendError?>(null);
  ReadonlySignal<SendError?> get lastSendError => _lastSendError;

  // Persists historical trackers from loaded thread history and from
  // completed sessions (absorbed in _detachSession). Plain map — the live
  // registry lives inside ExecutionTrackerExtension, which outlives the
  // view when the session runs in the background.
  final Map<String, ExecutionTracker> _historicalTrackers = {};

  /// Returns all execution trackers for this thread: historical (from loaded
  /// thread history) merged with any live trackers from the active session.
  Map<String, ExecutionTracker> get executionTrackers {
    final ext = _activeSession?.getExtension<ExecutionTrackerExtension>();
    if (ext == null) return Map.unmodifiable(_historicalTrackers);
    return {..._historicalTrackers, ...ext.trackers};
  }

  /// Live tool call statuses from the active session, or null if no session
  /// is attached.
  ReadonlySignal<List<ToolCallEntry>>? get toolCalls =>
      _activeSession?.getExtension<ToolCallsExtension>()?.stateSignal;

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
  }) {
    // Guard against sends while a session is already spawning/running.
    // The spawner's own re-entrancy guard only covers in-flight spawns;
    // this blocks overlapping sends when a prior session is attached.
    if (_sessionState.value != null) return Future<void>.value();
    return _spawner.spawn(
      spawnFn: () => runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
        threadId: threadId,
        stateOverlay: stateOverlay,
      ),
      errorSignal: _lastSendError,
      prompt: prompt,
      isDisposed: () => _isDisposed,
      onSpawned: (session) {
        _registry.register(threadKey, session);
        if (_isDisposed) return;
        _attachSession(session);
      },
      onStateTransition: (state) {
        if (_isDisposed) return;
        _sessionState.value = state;
      },
    );
  }

  void attachSession(AgentSession session) {
    _attachSession(session);
  }

  void cancelRun() {
    if (_spawner.cancel()) {
      _sessionState.value = null;
      return;
    }
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
        final current = _messages.value;
        if (current is! MessagesLoaded ||
            !identical(current.messages, conversation.messages)) {
          _messages.value = _messagesLoaded(conversation);
        }
        _streamingState.value = streaming;
        _sessionState.value = AgentSessionState.running;
      case CompletedState(:final conversation):
        _detachSession();
        _messages.value = _messagesLoaded(conversation);
      case FailedState(:final conversation, :final error):
        _detachSession();
        _lastSendError.value = SendError(error);
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case CancelledState(:final conversation):
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
    // Absorb live trackers from the extension before clearing the session
    // reference, so historical data persists after the session ends.
    final ext = _activeSession?.getExtension<ExecutionTrackerExtension>();
    if (ext != null) {
      // Live tracker wins over any historical entry with the same key.
      for (final entry in ext.trackers.entries) {
        _historicalTrackers.putIfAbsent(entry.key, () => entry.value);
      }
    }
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _activeSession = null;
    _streamingState.value = null;
    _sessionState.value = null;
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
      for (final entry in replayToTrackers(history.runs).entries) {
        _historicalTrackers.putIfAbsent(entry.key, () => entry.value);
      }
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
    _sessionState.dispose();
  }
}
