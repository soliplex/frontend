import 'dart:async' show unawaited;
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart';

import '../auth/auth_session.dart';
import '../auth/auth_tokens.dart';
import '../auth/return_to_storage.dart';
import 'execution_tracker.dart';
import 'execution_tracker_extension.dart';
import 'historical_replay.dart';
import 'human_approval_extension.dart';
import 'run_registry.dart';
import 'send_error.dart';
import 'session_spawner.dart';
import 'tool_calls_extension.dart';

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
    required AuthSession auth,
    required String roomId,
    required this.threadId,
    required RunRegistry registry,
    this.onHistoryLoaded,
  })  : _connection = connection,
        _auth = auth,
        _roomId = roomId,
        _registry = registry {
    _authUnsub = _auth.session.subscribe(_onAuthChanged);
    _sendErrorUnsub = _lastSendError.subscribe(_onSendError);
    if (!_restoreFromRegistry()) _fetch();
  }

  final ServerConnection _connection;
  final AuthSession _auth;
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
  final Signal<AgentSession?> _activeSession = Signal<AgentSession?>(null);
  void Function()? _runStateUnsub;
  void Function()? _reconnectStatusUnsub;
  void Function()? _authUnsub;
  void Function()? _sendErrorUnsub;
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

  /// Mirror of the active session's reconnect lifecycle. `null` means
  /// no reconnect activity. UI surfaces this for [Reconnecting] and
  /// [Reconnected] only — [ReconnectFailed] flows through
  /// [lastSendError] with friendly copy applied.
  final Signal<ReconnectStatus?> _reconnectStatus =
      Signal<ReconnectStatus?>(null);
  ReadonlySignal<ReconnectStatus?> get reconnectStatus => _reconnectStatus;

  /// Clears the reconnect banner. The "Reconnected" tile also auto-
  /// dismisses; this is for explicit user dismissal.
  void dismissReconnectStatus() => _reconnectStatus.value = null;

  // Persists historical trackers from loaded thread history and from
  // completed sessions (absorbed in _detachSession). Plain map — the live
  // registry lives inside ExecutionTrackerExtension, which outlives the
  // view when the session runs in the background.
  final Map<String, ExecutionTracker> _historicalTrackers = {};

  /// Returns all execution trackers for this thread: historical (from loaded
  /// thread history) merged with any live trackers from the active session.
  Map<String, ExecutionTracker> get executionTrackers {
    final ext = _activeSession.value?.getExtension<ExecutionTrackerExtension>();
    if (ext == null) return Map.unmodifiable(_historicalTrackers);
    return {..._historicalTrackers, ...ext.trackers};
  }

  /// Live tool call statuses from the active session, or null if no session
  /// is attached or the active session has no [ToolCallsExtension].
  ///
  /// Status is intentionally not persisted past the session's lifetime: this
  /// signal returns null the moment the session detaches, even if its list
  /// had populated entries.
  ReadonlySignal<List<ToolCallEntry>>? get toolCalls =>
      _activeSession.value?.getExtension<ToolCallsExtension>()?.stateSignal;

  /// Pending approval for the active session, or `null` when no session is
  /// attached, the session has no `HumanApprovalExtension`, or nothing is
  /// pending. Updates across session swaps via `computed`.
  late final ReadonlySignal<ApprovalRequest?> pendingApproval = computed(() {
    final session = _activeSession.value;
    return session?.getExtension<HumanApprovalExtension>()?.stateSignal.value;
  });

  /// Whether the cancel/stop affordance should take effect.
  ///
  /// True when a spawn is in progress, or when the active session's
  /// orchestrator is in a state from which [cancelRun] can actually
  /// transition to [CancelledState]. False during the IdleState window
  /// between session attach and the first SSE event, where [cancelRun]
  /// would be a silent no-op.
  late final ReadonlySignal<bool> isCancellable = computed(() {
    if (_sessionState.value == AgentSessionState.spawning &&
        _activeSession.value == null) {
      return true;
    }
    final session = _activeSession.value;
    if (session == null) return false;
    return switch (session.runState.value) {
      RunningState() => true,
      ToolYieldingState() => true,
      IdleState() => false,
      CompletedState() => false,
      FailedState() => false,
      CancelledState() => false,
    };
  });

  /// Resolves [request] on the active session's [HumanApprovalExtension]
  /// with [approved]. No-op if no session is attached, the session has no
  /// extension, or [request] is not the currently pending request.
  void respondToApproval(ApprovalRequest request, bool approved) {
    _activeSession.value
        ?.getExtension<HumanApprovalExtension>()
        ?.respond(request, approved);
  }

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
    _activeSession.value?.cancel();
  }

  void _attachSession(AgentSession session) {
    if (_isDisposed) return;
    _detachSession();
    _cancelToken?.cancel('session attached');
    _activeSession.value = session;
    _sessionState.value = session.state;
    _runStateUnsub = session.runState.subscribe(_onRunState);
    // `subscribe` fires synchronously with the new session's current
    // value — null for fresh sessions, the live status for sessions
    // restored from the registry. Either way, the mirror is up to date
    // without an explicit reset (which would erase a live status from
    // a restored session).
    _reconnectStatusUnsub =
        session.reconnectStatus.subscribe(_onReconnectStatus);
  }

  void _onReconnectStatus(ReconnectStatus? status) {
    if (_isDisposed) return;
    _reconnectStatus.value = status;
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
      case FailedState(:final conversation, :final reason, :final error):
        _detachSession();
        if (reason == FailureReason.authExpired) {
          // Funnel to the per-server auth funnel so the route guard
          // (and any lobby UX) can react. The screen also surfaces a
          // banner so the user sees what happened before the redirect.
          _auth.markSessionExpired();
        }
        _lastSendError.value = SendError(_friendlyMessage(reason, error));
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
    final ext = _activeSession.value?.getExtension<ExecutionTrackerExtension>();
    if (ext != null) {
      // Live tracker wins over any historical entry with the same key.
      for (final entry in ext.trackers.entries) {
        _historicalTrackers[entry.key] = entry.value;
      }
    }
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _reconnectStatusUnsub?.call();
    _reconnectStatusUnsub = null;
    _activeSession.value = null;
    _streamingState.value = null;
    _sessionState.value = null;
    // Preserve `Reconnected` so its banner-side auto-dismiss runs.
    // Other states have no auto-dismiss; clear them here.
    if (_reconnectStatus.value is! Reconnected) {
      _reconnectStatus.value = null;
    }
  }

  /// Translates orchestrator failure copy into user-facing copy.
  ///
  /// `streamResumeFailed` failures get a friendly base message; other
  /// failures pass through unchanged.
  String _friendlyMessage(FailureReason reason, String error) {
    if (reason != FailureReason.streamResumeFailed) return error;
    return 'Connection lost. The response may be incomplete — '
        'you can send your message again.';
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
      case FailedRun(:final conversation, :final error, :final reason):
        // Apply friendly copy on re-attach, same as the live FailedState arm.
        _lastSendError.value =
            SendError(_friendlyMessage(reason, error.toString()));
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
      // putIfAbsent (not []=) on refresh: server replay must not overwrite a
      // tracker already absorbed from a live session (`_detachSession`), which
      // captured the full client-side event stream.
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
    _authUnsub?.call();
    _authUnsub = null;
    _sendErrorUnsub?.call();
    _sendErrorUnsub = null;
    _cancelToken?.cancel('disposed');
    _detachSession();
    _sessionState.dispose();
    _reconnectStatus.dispose();
    isCancellable.dispose();
    pendingApproval.dispose();
  }

  /// Cancels the active run and pending history fetch when the auth
  /// session leaves [ActiveSession] (expired or signed out). The
  /// route guard handles navigation; this just stops in-flight work
  /// so the SSE client doesn't reconnect-loop with a dead token.
  void _onAuthChanged(SessionState state) {
    if (_isDisposed) return;
    if (state is ActiveSession) return;
    _cancelToken?.cancel('auth expired');
    _activeSession.value?.cancel();
  }

  /// Persists composer text when a spawn-failure SendError lands with
  /// the original prompt attached AND the underlying error is an
  /// auth failure. The auth path is the only one where the user gets
  /// navigated away (route guard) — for non-auth errors the screen
  /// stays mounted and the in-memory [SendError.unsentText] +
  /// `_restoreUnsentText` path handles restoration without touching
  /// storage.
  void _onSendError(SendError? err) {
    if (_isDisposed) return;
    if (err == null) return;
    final text = err.unsentText;
    if (text == null || text.trim().isEmpty) return;
    if (err.error is! AuthException) return;
    unawaited(
      ReturnToStorage.saveComposer(
        serverId: _connection.serverId,
        roomId: _roomId,
        unsentText: text,
      ).catchError((Object e, StackTrace st) {
        dev.log(
          'Failed to persist composer draft for auth roundtrip',
          error: e,
          stackTrace: st,
          level: 1000,
        );
      }),
    );
  }
}
