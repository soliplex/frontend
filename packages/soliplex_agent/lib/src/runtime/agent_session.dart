import 'dart:async';

import 'package:meta/meta.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/models/agent_result.dart';
import 'package:soliplex_agent/src/models/failure_reason.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/execution_event.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_agent/src/orchestration/run_state.dart';
import 'package:soliplex_agent/src/runtime/agent_runtime.dart';
import 'package:soliplex_agent/src/runtime/agent_session_state.dart';
import 'package:soliplex_agent/src/runtime/agent_ui_delegate.dart';
import 'package:soliplex_agent/src/runtime/session_coordinator.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/runtime/tool_approval_extension.dart';
import 'package:soliplex_agent/src/tools/tool_execution_context.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// A single autonomous agent session.
///
/// Wraps a [RunOrchestrator] and automatically executes client-side tool
/// calls via [RunOrchestrator.runToCompletion]. Callers receive a single
/// [AgentResult] when the session reaches a terminal state.
///
/// Implements [ToolExecutionContext] so tools can access cancellation,
/// child spawning, event emission, and session-scoped extensions.
///
/// Sessions form a parent-child tree: when a parent is cancelled or
/// disposed, all children are cancelled/disposed first. Child sessions
/// are created via [spawnChild], which delegates to the owning
/// [AgentRuntime].
///
/// Created exclusively by `AgentRuntime.spawn()`.
class AgentSession implements ToolExecutionContext {
  @internal
  AgentSession({
    required this.threadKey,
    required this.ephemeral,
    required this.depth,
    required AgentRuntime runtime,
    required RunOrchestrator orchestrator,
    required ToolRegistry toolRegistry,
    required Logger logger,
    required SessionCoordinator coordinator,
    AgentUiDelegate? uiDelegate,
  })  : _runtime = runtime,
        _orchestrator = orchestrator,
        _toolRegistry = toolRegistry,
        _coordinator = coordinator,
        _uiDelegate = uiDelegate,
        _logger = logger,
        id = '${threadKey.threadId}-'
            '${DateTime.now().microsecondsSinceEpoch}';

  /// Unique session identifier.
  final String id;

  /// The thread this session operates on.
  final ThreadKey threadKey;

  /// Whether the thread should be deleted on completion.
  final bool ephemeral;

  /// Depth in the parent-child spawn tree. Root sessions have depth 0.
  final int depth;

  final AgentRuntime _runtime;
  final RunOrchestrator _orchestrator;
  final ToolRegistry _toolRegistry;
  final SessionCoordinator _coordinator;
  final AgentUiDelegate? _uiDelegate;
  final Logger _logger;

  static const _toolTimeout = Duration(seconds: 60);

  final List<AgentSession> _children = [];
  final Completer<AgentResult> _resultCompleter = Completer<AgentResult>();
  StreamSubscription<RunState>? _subscription;
  StreamSubscription<BaseEvent>? _baseEventSubscription;
  AgentSessionState _state = AgentSessionState.spawning;
  bool _disposed = false;
  final Signal<RunState> _runStateSignal = signal(const IdleState());
  final Signal<AgentSessionState> _sessionStateSignal = signal(
    AgentSessionState.spawning,
  );
  final Signal<ExecutionEvent?> _executionEventSignal = signal(null);

  /// Child sessions spawned by this session.
  List<AgentSession> get children => List.unmodifiable(_children);

  /// Current session lifecycle state.
  AgentSessionState get state => _state;

  /// Completes when the session reaches a terminal state.
  Future<AgentResult> get result => _resultCompleter.future;

  /// Broadcast stream of [RunState] changes from the underlying orchestrator.
  ///
  /// **Deprecated.** Use [runState] signal instead.
  ///
  /// Use this to observe live token streaming, tool calls, and other
  /// intermediate events. The stream completes when the orchestrator is
  /// disposed.
  ///
  /// ```dart
  /// session.stateChanges.listen((state) {
  ///   if (state case RunningState(:final streaming)) {
  ///     if (streaming case TextStreaming(:final text)) {
  ///       stdout.write(text);
  ///     }
  ///   }
  /// });
  /// ```
  Stream<RunState> get stateChanges => _orchestrator.stateChanges;

  /// Reactive signal tracking the latest [RunState] from the orchestrator.
  ReadonlySignal<RunState> get runState => _runStateSignal.readonly();

  /// Reactive signal tracking the [AgentSessionState] lifecycle.
  ReadonlySignal<AgentSessionState> get sessionState =>
      _sessionStateSignal.readonly();

  /// Reactive signal tracking the most recent [ExecutionEvent].
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent =>
      _executionEventSignal.readonly();

  /// Waits for the session result with an optional timeout.
  Future<AgentResult> awaitResult({Duration? timeout}) {
    if (timeout == null) return result;
    final start = DateTime.now();
    return result.timeout(
      timeout,
      onTimeout: () => AgentTimedOut(
        threadKey: threadKey,
        elapsed: DateTime.now().difference(start),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ToolExecutionContext implementation
  // ---------------------------------------------------------------------------

  @override
  CancelToken get cancelToken => _orchestrator.cancelToken;

  @override
  Future<AgentSession> spawnChild({
    required String prompt,
    String? roomId,
    String? threadId,
    Duration? timeout,
    bool ephemeral = true,
  }) {
    return _runtime.spawn(
      roomId: roomId ?? threadKey.roomId,
      prompt: prompt,
      threadId: threadId,
      timeout: timeout,
      ephemeral: ephemeral,
      autoDispose: true,
      parent: this,
    );
  }

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async {
    emitEvent(
      AwaitingApproval(
        toolCallId: toolCallId,
        toolName: toolName,
        rationale: rationale,
      ),
    );

    final approvalExt = _coordinator.getExtension<ToolApprovalExtension>();
    if (approvalExt != null) {
      return Future.any([
        approvalExt.requestApproval(
          toolCallId: toolCallId,
          toolName: toolName,
          arguments: arguments,
          rationale: rationale,
        ),
        cancelToken.whenCancelled.then((_) => false),
      ]);
    }

    if (_uiDelegate == null) return false;
    return Future.any([
      _uiDelegate.requestToolApproval(
        session: this,
        toolName: toolName,
        arguments: arguments,
        rationale: rationale,
      ),
      cancelToken.whenCancelled.then((_) => false),
    ]);
  }

  @override
  Future<String> delegateTask({
    required String prompt,
    String? roomId,
    Duration? timeout,
  }) async {
    final child = await spawnChild(roomId: roomId, prompt: prompt);
    final result = await child.awaitResult(timeout: timeout);
    return switch (result) {
      AgentSuccess(:final output) => output,
      AgentFailure(:final error) => throw StateError('Child failed: $error'),
      AgentTimedOut() => throw TimeoutException('Child timed out'),
    };
  }

  @override
  void emitEvent(ExecutionEvent event) {
    if (_disposed) return;
    _executionEventSignal.value = event;
  }

  @override
  T? getExtension<T extends SessionExtension>() =>
      _coordinator.getExtension<T>();

  /// Yields `(namespace, signal)` for every stateful extension with a
  /// non-empty namespace registered in this session.
  Iterable<(String, ReadonlySignal<Object?>)> statefulObservations() =>
      _coordinator.statefulObservations();

  // ---------------------------------------------------------------------------
  // Child management
  // ---------------------------------------------------------------------------

  /// Registers a child session. Called by [AgentRuntime.spawn].
  @internal
  void addChild(AgentSession child) {
    _children.add(child);
  }

  /// Removes a child session. Called when a child completes or is disposed.
  @internal
  void removeChild(AgentSession child) {
    _children.remove(child);
  }

  /// Cancels the session and all children. No-op if already terminal.
  void cancel() {
    if (_isTerminal) return;
    for (final child in _children.toList()) {
      child.cancel();
    }
    _orchestrator.cancelRun();
  }

  /// Starts the orchestrator run and subscribes to state changes.
  ///
  /// Called internally by `AgentRuntime`. Extensions are attached before
  /// the run starts. The run is fire-and-forget — terminal states flow
  /// through [_onStateChange] into [_completeWith].
  Future<void> start({
    required String userMessage,
    String? existingRunId,
    ThreadHistory? cachedHistory,
    Map<String, dynamic>? stateOverlay,
  }) async {
    await _attachExtensions();
    _subscription = _orchestrator.stateChanges.listen(_onStateChange);
    _baseEventSubscription = _orchestrator.baseEvents.listen(_bridgeBaseEvent);
    unawaited(
      _orchestrator.runToCompletion(
        key: threadKey,
        userMessage: userMessage,
        toolExecutor: _executeAll,
        existingRunId: existingRunId,
        cachedHistory: cachedHistory,
        stateOverlay: stateOverlay,
      ),
    );
  }

  /// Releases all resources, cascading to children first.
  ///
  /// Called by [AgentRuntime] when the session completes or the runtime
  /// is disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final child in _children.toList()) {
      child.dispose();
    }
    _children.clear();
    _disposeExtensions();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_baseEventSubscription?.cancel());
    _baseEventSubscription = null;
    _orchestrator.dispose();
    _completeIfPending();
    _runStateSignal.dispose();
    _sessionStateSignal.dispose();
    _executionEventSignal.dispose();
  }

  // ---------------------------------------------------------------------------
  // Extension lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _attachExtensions() => _coordinator.attachAll(this);

  void _disposeExtensions() => _coordinator.disposeAll();

  // ---------------------------------------------------------------------------
  // State listener
  // ---------------------------------------------------------------------------

  void _onStateChange(RunState runState) {
    if (_disposed) return;
    _runStateSignal.value = runState;
    switch (runState) {
      case RunningState():
        _state = AgentSessionState.running;
        _sessionStateSignal.value = _state;
      case ToolYieldingState():
        break;
      case CompletedState():
        _completeWith(_mapCompleted(runState));
      case FailedState():
        _completeWith(_mapFailed(runState));
      case CancelledState():
        _completeWith(_mapCancelled(runState));
      case IdleState():
        break;
    }
  }

  /// Maps raw AG-UI [BaseEvent]s to [ExecutionEvent] emissions so that
  /// consumers observing [lastExecutionEvent] see streaming text, thinking,
  /// server tool calls, and terminal events without polling [runState].
  void _bridgeBaseEvent(BaseEvent event) {
    final executionEvent = bridgeBaseEvent(event);
    if (executionEvent != null) emitEvent(executionEvent);
  }

  // ---------------------------------------------------------------------------
  // Tool execution (callback for runToCompletion)
  // ---------------------------------------------------------------------------

  Future<List<ToolCallInfo>> _executeAll(List<ToolCallInfo> pendingTools) {
    return Future.wait(pendingTools.map(_executeSingle));
  }

  Future<ToolCallInfo> _executeSingle(ToolCallInfo toolCall) async {
    emitEvent(
      ClientToolExecuting(toolName: toolCall.name, toolCallId: toolCall.id),
    );
    try {
      final result =
          await _toolRegistry.execute(toolCall, this).timeout(_toolTimeout);
      emitEvent(
        ClientToolCompleted(
          toolCallId: toolCall.id,
          result: result,
          status: ToolCallStatus.completed,
        ),
      );
      return toolCall.copyWith(
        status: ToolCallStatus.completed,
        result: result,
      );
    } on Object catch (error, stackTrace) {
      return _handleToolError(toolCall, error, stackTrace);
    }
  }

  ToolCallInfo _handleToolError(
    ToolCallInfo toolCall,
    Object error,
    StackTrace stackTrace,
  ) {
    _logger.warning(
      'Tool "${toolCall.name}" failed',
      error: error,
      stackTrace: stackTrace,
    );
    final errorStr = error is TimeoutException
        ? 'Tool "${toolCall.name}" timed out after ${_toolTimeout.inSeconds}s'
        : error.toString();
    emitEvent(
      ClientToolCompleted(
        toolCallId: toolCall.id,
        result: errorStr,
        status: ToolCallStatus.failed,
      ),
    );
    return toolCall.copyWith(status: ToolCallStatus.failed, result: errorStr);
  }

  // ---------------------------------------------------------------------------
  // Result mapping
  // ---------------------------------------------------------------------------

  AgentResult _mapCompleted(CompletedState state) {
    final output = _extractLastAssistantText(state.conversation);
    return AgentSuccess(
      threadKey: threadKey,
      output: output,
      runId: state.runId,
    );
  }

  AgentResult _mapFailed(FailedState state) {
    return AgentFailure(
      threadKey: threadKey,
      reason: state.reason,
      error: state.error,
    );
  }

  AgentResult _mapCancelled(CancelledState state) {
    return AgentFailure(
      threadKey: threadKey,
      reason: FailureReason.cancelled,
      error: 'Session cancelled',
    );
  }

  String _extractLastAssistantText(Conversation conversation) {
    final assistantMessages = conversation.messages
        .whereType<TextMessage>()
        .where((m) => m.user == ChatUser.assistant);
    return assistantMessages.lastOrNull?.text ?? '';
  }

  // ---------------------------------------------------------------------------
  // Completion helpers
  // ---------------------------------------------------------------------------

  void _completeWith(AgentResult agentResult) {
    switch (agentResult) {
      case AgentSuccess():
        _state = AgentSessionState.completed;
      case AgentFailure(:final reason):
        _state = reason == FailureReason.cancelled
            ? AgentSessionState.cancelled
            : AgentSessionState.failed;
      case AgentTimedOut():
        _state = AgentSessionState.failed;
    }
    _sessionStateSignal.value = _state;
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.complete(agentResult);
    }
  }

  void _completeIfPending() {
    if (_resultCompleter.isCompleted) return;
    _state = AgentSessionState.failed;
    _sessionStateSignal.value = _state;
    _resultCompleter.complete(
      AgentFailure(
        threadKey: threadKey,
        reason: FailureReason.internalError,
        error: 'Session disposed before completion',
      ),
    );
  }

  bool get _isTerminal =>
      _state == AgentSessionState.completed ||
      _state == AgentSessionState.failed ||
      _state == AgentSessionState.cancelled;
}

/// Translates a raw AG-UI [BaseEvent] into the [ExecutionEvent] that
/// consumers of [AgentSession.lastExecutionEvent] should observe, or
/// `null` when the event does not map to an execution-event emission.
///
/// Used on the live path by [AgentSession] and on the historical replay
/// path by the app layer when hydrating execution-tracker state from a
/// loaded `ThreadHistory`.
ExecutionEvent? bridgeBaseEvent(BaseEvent event) {
  return switch (event) {
    TextMessageContentEvent(:final delta) => TextDelta(delta: delta),
    ThinkingTextMessageStartEvent() ||
    ReasoningMessageStartEvent() =>
      const ThinkingStarted(),
    ThinkingTextMessageContentEvent(:final delta) ||
    ReasoningMessageContentEvent(:final delta) =>
      ThinkingContent(delta: delta),
    ToolCallStartEvent(:final toolCallId, :final toolCallName) =>
      ServerToolCallStarted(toolCallId: toolCallId, toolName: toolCallName),
    ToolCallResultEvent(:final toolCallId, :final content) =>
      ServerToolCallCompleted(toolCallId: toolCallId, result: content),
    RunFinishedEvent() => const RunCompleted(),
    RunErrorEvent(:final message) => RunFailed(error: message),
    ActivitySnapshotEvent(
      :final messageId,
      :final activityType,
      :final content,
      :final timestamp,
      :final replace,
    ) =>
      ActivitySnapshot(
        messageId: messageId,
        activityType: activityType,
        content: content,
        timestamp: timestamp,
        replace: replace,
      ),
    StepStartedEvent(:final stepName) => StepProgress(stepName: stepName),

    // Events that don't need ExecutionEvent bridging.
    RunStartedEvent() ||
    TextMessageStartEvent() ||
    TextMessageEndEvent() ||
    ThinkingStartEvent() ||
    ThinkingTextMessageEndEvent() ||
    ThinkingEndEvent() ||
    ThinkingContentEvent() ||
    ToolCallArgsEvent() ||
    ToolCallEndEvent() ||
    StateSnapshotEvent() ||
    StateDeltaEvent() ||
    StepFinishedEvent() ||
    TextMessageChunkEvent() ||
    ToolCallChunkEvent() ||
    MessagesSnapshotEvent() ||
    RawEvent() ||
    CustomEvent() ||
    ReasoningStartEvent() ||
    ReasoningEndEvent() ||
    ReasoningMessageEndEvent() ||
    ReasoningMessageChunkEvent() ||
    ReasoningEncryptedValueEvent() ||
    ActivityDeltaEvent() =>
      null,
  };
}
