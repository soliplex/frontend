// Four upstream types are deprecated, scheduled for removal in ag_ui 1.0.0:
// THINKING_TEXT_MESSAGE_{START,CONTENT,END} and THINKING_CONTENT.
// `ThinkingStartEvent` and `ThinkingEndEvent` are NOT deprecated and their arms
// stay regardless — a removal sweep grepping "THINKING" must not touch them.
// The THINKING_TEXT_MESSAGE_* arms stay because stored threads still decode to
// them; the THINKING_CONTENT arm stays only to keep `bridgeBaseEvent`'s switch
// over sealed `BaseEvent` exhaustive (upstream documents it as Dart-only legacy
// that was never part of the canonical protocol). Suppressed per line so the
// 1.0.0 sweep can enumerate them and an unrelated deprecation here still
// raises.

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
  })  : _runtime = runtime,
        _orchestrator = orchestrator,
        _toolRegistry = toolRegistry,
        _coordinator = coordinator,
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
  final Logger _logger;

  static const _toolTimeout = Duration(seconds: 60);

  final List<AgentSession> _children = [];

  /// Cancellation signal for the session as a whole. Never replaced, and
  /// cancelled at most once — [CancelToken.cancel] is idempotent — by
  /// [cancel] or by [dispose].
  ///
  /// Deliberately not the token `RunOrchestrator` passes to the transport.
  /// That one is scoped to a single HTTP request: it is re-minted for every
  /// resume segment and cleared whenever no request is in flight, including
  /// for the whole of the tool-execution window. Readers that need to know
  /// whether *the session* was cancelled — tools polling
  /// [ToolExecutionContext.cancelToken], and extensions that subscribe in
  /// `onAttach`, which runs before the first request exists — need a token
  /// whose lifetime is the session's.
  final CancelToken _cancelToken = CancelToken();

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
  final Signal<ReconnectStatus?> _reconnectStatusSignal =
      signal<ReconnectStatus?>(null);

  /// Child sessions spawned by this session.
  List<AgentSession> get children => List.unmodifiable(_children);

  /// Current session lifecycle state.
  AgentSessionState get state => _state;

  /// Whether [dispose] has run. Deferred callbacks that might fire after
  /// the session's owner has torn down should short-circuit on this
  /// before reading the session's signals (which are disposed inside
  /// [dispose]).
  bool get isDisposed => _disposed;

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

  /// Reactive signal exposing `Conversation.activities` for whichever
  /// run-state variant currently carries a [Conversation]. Empty list
  /// while idle or in a terminal state that didn't capture a
  /// conversation. Used by `ExecutionTracker`, which mirrors it into a
  /// signal of its own so that freezing pins the records a run ended with.
  late final ReadonlySignal<List<ActivityRecord>> conversationActivities =
      computed(() => conversationActivitiesOf(runState.value));

  /// Reactive signal tracking the agent's `aguiState` map across the
  /// session lifetime.
  ///
  /// View of the per-thread [bus]'s `agentState` signal. The bus is
  /// fed by `_onStateChange` on every [RunState] transition, so
  /// `session.agentState` and `bus.agentState` see the same snapshot
  /// at all times — no parallel compute path.
  ReadonlySignal<Map<String, dynamic>> get agentState => bus.agentState;

  /// The per-thread reactive bus this session writes into. Owned by
  /// the runtime; survives session boundaries within the thread's
  /// lifetime.
  ///
  /// Resolves through `runtime.ensureThreadState(threadKey).bus`,
  /// creating a fresh `ThreadState` if no prior `seedThreadState` /
  /// `seedThreadHistory` call registered one. Late-evaluated, so a
  /// session that never reads `bus` never causes a `StateBus` to be
  /// constructed.
  StateBus get bus => _runtime.ensureThreadState(threadKey).bus;

  /// Reactive signal tracking the [AgentSessionState] lifecycle.
  ReadonlySignal<AgentSessionState> get sessionState =>
      _sessionStateSignal.readonly();

  /// Reactive signal tracking the most recent [ExecutionEvent].
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent =>
      _executionEventSignal.readonly();

  /// Reactive signal tracking SSE stream reconnect lifecycle.
  ///
  /// `null` means no reconnect activity. Emits [Reconnecting] while a
  /// resume attempt is in flight, [Reconnected] on the first decoded
  /// event after a successful resume, [ReconnectFailed] when the retry
  /// budget is exhausted. Hosts can mirror this into a banner.
  ReadonlySignal<ReconnectStatus?> get reconnectStatus =>
      _reconnectStatusSignal.readonly();

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

  /// The session's cancellation signal. Stable for the session's lifetime,
  /// so a listener registered in `onAttach` still sees a later [cancel].
  ///
  /// [dispose] cancels it, so a late tool caller (a microtask resuming after
  /// teardown) reads a cancelled token and short-circuits cleanly instead of
  /// surfacing an opaque "tool failed" error.
  @override
  CancelToken get cancelToken => _cancelToken;

  @override
  Future<AgentSession> spawnChild({
    required String prompt,
    String? roomId,
    String? threadId,
    Duration? timeout,
    bool ephemeral = true,
  }) {
    if (_disposed) {
      _logger.debug(
        'spawnChild denied: session $id already disposed '
        '(prompt="$prompt", roomId=$roomId).',
      );
      // Future.error rather than sync-throw so a fire-and-forget caller or
      // a chained .catchError sees the failure instead of crashing the
      // isolate with an uncaught synchronous exception.
      return Future<AgentSession>.error(
        StateError('Cannot spawnChild on disposed session $id'),
        StackTrace.current,
      );
    }
    return _runtime.spawn(
      roomId: roomId ?? threadKey.roomId,
      // A text-only signature: the prompt becomes one run rather than
      // widening an API whose callers have no image to pass.
      prompt: [TextPart(prompt)],
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
  }) {
    // Late callers (microtask resuming after dispose): deny without
    // touching the already-disposed extension.
    if (_disposed) {
      _logger.debug(
        'requestApproval denied: session $id already disposed '
        '(tool $toolName, $toolCallId).',
      );
      return Future<bool>.value(false);
    }
    // Short-circuit before the extension call so a cancelled session never
    // surfaces an approval dialog the orchestrator is about to throw away.
    if (cancelToken.isCancelled) {
      _logger.debug(
        'requestApproval denied: session $id already cancelled '
        '(tool $toolName, $toolCallId).',
      );
      return Future<bool>.value(false);
    }
    final ext = _coordinator.getExtension<ToolApprovalExtension>();
    if (ext == null) {
      _logger.warning(
        'Tool $toolName ($toolCallId) requested approval on session $id '
        'but no ToolApprovalExtension is registered; denying by default.',
      );
      return Future<bool>.value(false);
    }
    emitEvent(
      AwaitingApproval(
        toolCallId: toolCallId,
        toolName: toolName,
        rationale: rationale,
      ),
    );
    return ext.requestApproval(
      toolCallId: toolCallId,
      toolName: toolName,
      arguments: arguments,
      rationale: rationale,
    );
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

  /// See [SessionCoordinator.statefulObservations].
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

  /// Cancels the session and all children.
  ///
  /// The cancellation signal always fires; the child cascade and the
  /// orchestrator cancel are skipped once the session is terminal.
  ///
  /// Cannot throw. The callers that press Stop are widget callbacks, where
  /// Flutter prints a throw and carries on — so an error escaping here is a
  /// press that silently did nothing while the run kept streaming. And since
  /// `AgentRuntime` waits on [result] before disposing this session and
  /// draining the spawn queue, a cancel that leaves no terminal state stalls
  /// every spawn queued behind it, which is why the catch settles the session
  /// itself rather than only recording the fault.
  void cancel() {
    // Ahead of the terminal check: a run that already failed is terminal, and
    // a tool parked on an approval is still waiting on this token.
    _cancelToken.cancel('session cancelled');
    if (_isTerminal) return;
    try {
      // No per-child guard: the cascade calls this same method, and it does
      // not throw.
      for (final child in _children.toList()) {
        child.cancel();
      }
      _orchestrator.cancelRun();
    } on Object catch (e, st) {
      // The stack trace is what locates this one: `describeFailure` reduces a
      // `StateError` to its type name, and the guard that threw it is a frame.
      _logger.error(
        'AgentSession cancel threw (session=$id, '
        'thread=${threadKey.threadId})',
        attributes: {'failure': describeFailure(e)},
        stackTrace: st,
      );
      // Only here. Every other path out of `cancelRun` publishes a terminal
      // `RunState`, or leaves one already published, and `_onStateChange`
      // settles the session from it; a throw is the one exit that publishes
      // nothing, so this is the one exit that has to settle it.
      if (!_isTerminal && !_disposed) {
        _completeWith(
          AgentFailure(
            threadKey: threadKey,
            reason: FailureReason.cancelled,
            error: 'Session cancelled',
          ),
        );
      }
    }
  }

  /// Starts the orchestrator run and subscribes to state changes.
  ///
  /// Called internally by `AgentRuntime`. Extensions are attached before
  /// the run starts. The run is fire-and-forget — terminal states flow
  /// through [_onStateChange] into [_completeWith].
  Future<void> start({
    required List<MessagePart> userMessage,
    String? existingRunId,
    ThreadHistory? cachedHistory,
    Map<String, dynamic>? stateOverlay,
  }) async {
    await _attachExtensions();
    // `AgentRuntime.spawn` registers this session with its parent before
    // awaiting `start`, so a parent cancel can land during the attach above.
    // Starting anyway would create a backend run the user already stopped.
    //
    // Settle the result rather than just returning: `AgentRuntime` awaits it
    // before draining the spawn queue, and before disposing the session when
    // it owns the lifecycle, so leaving it pending would strand both.
    if (_cancelToken.isCancelled) {
      // [dispose] cancels the token too, and settles the result itself
      // through `_completeIfPending` before disposing the signals that
      // `_completeWith` writes.
      if (_disposed) return;
      _completeWith(
        AgentFailure(
          threadKey: threadKey,
          reason: FailureReason.cancelled,
          error: 'Cancelled before the run started',
        ),
      );
      return;
    }
    _subscription = _orchestrator.stateChanges.listen(_onStateChange);
    _baseEventSubscription = _orchestrator.baseEvents.listen(_bridgeBaseEvent);
    // Fire and forget, but not unobserved: `AgentRuntime` waits on this
    // session's result before disposing it and draining the spawn queue, so a
    // throw escaping here would leave the run with no terminal state, the
    // session never torn down, and later spawns queued behind it. Every
    // expected outcome — including a cancel — comes back as a terminal
    // `RunState`, so reaching this handler means a bug, not a failed run.
    unawaited(
      _orchestrator
          .runToCompletion(
            key: threadKey,
            userMessage: userMessage,
            toolExecutor: _executeAll,
            existingRunId: existingRunId,
            cachedHistory: cachedHistory,
            stateOverlay: stateOverlay,
            onReconnectStatus: _onReconnectStatus,
          )
          .catchError(_settleFailedRun),
    );
  }

  /// Settles the session when `runToCompletion` throws instead of returning a
  /// terminal state, so the runtime's wait on [result] cannot hang.
  RunState _settleFailedRun(Object error, StackTrace stackTrace) {
    _logger.error(
      'runToCompletion threw (session=$id, thread=${threadKey.threadId})',
      attributes: {'failure': describeFailure(error)},
      stackTrace: stackTrace,
    );
    if (!_disposed) {
      _completeWith(
        AgentFailure(
          threadKey: threadKey,
          reason: FailureReason.internalError,
          error: 'Run did not reach a terminal state',
        ),
      );
    }
    return _orchestrator.currentState;
  }

  /// Bridges reconnect-lifecycle callbacks from `RunOrchestrator` /
  /// `AgUiStreamClient` into the [reconnectStatus] signal.
  void _onReconnectStatus(ReconnectStatus status) {
    if (_disposed) return;
    _reconnectStatusSignal.value = status;
  }

  /// Releases all resources, cascading to children first.
  ///
  /// Called by [AgentRuntime] when the session completes or the runtime
  /// is disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelToken.cancel('session disposed');
    for (final child in _children.toList()) {
      try {
        child.dispose();
      } on Object catch (e, st) {
        _logger.error(
          'Child AgentSession dispose threw (parent=$id, '
          'thread=${threadKey.threadId}, child=${child.id})',
          error: e,
          stackTrace: st,
        );
      }
    }
    _children.clear();
    _disposeExtensions();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_baseEventSubscription?.cancel());
    _baseEventSubscription = null;
    try {
      _orchestrator.dispose();
    } on Object catch (e, st) {
      _logger.error(
        'Orchestrator dispose threw (session=$id, '
        'thread=${threadKey.threadId})',
        error: e,
        stackTrace: st,
      );
    }
    _completeIfPending();
    _runStateSignal.dispose();
    _sessionStateSignal.dispose();
    _executionEventSignal.dispose();
    _reconnectStatusSignal.dispose();
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
    // Forward the new agent state into the per-thread bus. AG-UI
    // events were already applied to the conversation by
    // `processEvent`; this propagates the result so bus consumers
    // (projections, render targets) see it on every state-altering
    // event without each consumer re-listening to the orchestrator.
    final next = _aguiStateOf(runState);
    if (next != null) {
      bus.setAgentState(next);
    }
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

  /// Pulls the `aguiState` map out of any [RunState] variant. Returns
  /// null when the variant carries no conversation (Idle, or a
  /// Failed/Cancelled state with no captured conversation).
  static Map<String, dynamic>? _aguiStateOf(RunState state) {
    return switch (state) {
      IdleState() => null,
      RunningState(:final conversation) => conversation.aguiState,
      ToolYieldingState(:final conversation) => conversation.aguiState,
      CompletedState(:final conversation) => conversation.aguiState,
      FailedState(:final conversation) => conversation?.aguiState,
      CancelledState(:final conversation) => conversation?.aguiState,
    };
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

/// Extracts the activity list carried by [runState], or `const []` for
/// variants that don't carry a [Conversation]. Backs
/// [AgentSession.conversationActivities] — exposed as a top-level
/// function so the switch can be exercised directly without
/// orchestrator scaffolding.
List<ActivityRecord> conversationActivitiesOf(RunState runState) =>
    switch (runState) {
      RunningState(:final conversation) ||
      ToolYieldingState(:final conversation) ||
      CompletedState(:final conversation) =>
        conversation.activities,
      FailedState(:final conversation?) ||
      CancelledState(:final conversation?) =>
        conversation.activities,
      // Exhaustive over the remaining sealed variants so adding a new
      // RunState forces an explicit decision here rather than silently
      // falling back to an empty list.
      IdleState() ||
      FailedState(conversation: null) ||
      CancelledState(conversation: null) =>
        const <ActivityRecord>[],
    };

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
    // Deprecated upstream; retained to decode stored threads.
    // ignore: deprecated_member_use
    ThinkingTextMessageStartEvent() ||
    ReasoningMessageStartEvent() =>
      const ThinkingStarted(),
    // Deprecated upstream; retained to decode stored threads.
    // ignore: deprecated_member_use
    ThinkingTextMessageContentEvent(:final delta) ||
    ReasoningMessageContentEvent(:final delta) =>
      ThinkingContent(delta: delta),
    // Deprecated upstream; retained to decode stored threads.
    // ignore: deprecated_member_use
    ThinkingTextMessageEndEvent() ||
    ThinkingEndEvent() ||
    ReasoningEndEvent() ||
    ReasoningMessageEndEvent() =>
      const ThinkingEnded(),
    ToolCallStartEvent(:final toolCallId, :final toolCallName) =>
      ServerToolCallStarted(toolCallId: toolCallId, toolName: toolCallName),
    ToolCallArgsEvent(:final toolCallId, :final delta) =>
      ServerToolCallArgs(toolCallId: toolCallId, delta: delta),
    ToolCallResultEvent(:final toolCallId, :final content) =>
      ServerToolCallCompleted(toolCallId: toolCallId, result: content),
    RunFinishedEvent() => const RunCompleted(),
    RunErrorEvent(:final message) => RunFailed(error: message),
    ActivitySnapshotEvent(
      :final messageId,
      :final activityType,
      content: final Map<String, dynamic> content,
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
    //
    // `ActivityDeltaEvent` is intentionally dropped here: the domain
    // layer (`agui_event_processor._processActivityDelta`) applies the
    // patch to `Conversation.activities`, and the tracker observes
    // activities reactively via the resulting signal. Bridging the
    // delta into an `ExecutionEvent` would duplicate that work.
    //
    // The bare `ActivitySnapshotEvent` reaches here only when `content` is not
    // a `Map<String, dynamic>`, which AG-UI's `Object?` typing permits. Such a
    // snapshot is dropped rather than synthesized into an empty one: the
    // tracker must not hold an entry with no matching `ActivityRecord`. The
    // live path never reaches this arm — `processEvent` throws on that shape
    // and the orchestrator returns before republishing the event. Historical
    // replay does reach it and drops silently by design, because the
    // chat-message side already mints one tile for the same event.
    RunStartedEvent() ||
    TextMessageStartEvent() ||
    TextMessageEndEvent() ||
    ThinkingStartEvent() ||
    // Deprecated upstream; arm only keeps the sealed switch exhaustive.
    // ignore: deprecated_member_use
    ThinkingContentEvent() ||
    ToolCallEndEvent() ||
    StateSnapshotEvent() ||
    StateDeltaEvent() ||
    ActivitySnapshotEvent() ||
    StepFinishedEvent() ||
    TextMessageChunkEvent() ||
    ToolCallChunkEvent() ||
    MessagesSnapshotEvent() ||
    ActivityDeltaEvent() ||
    RawEvent() ||
    CustomEvent() ||
    ReasoningStartEvent() ||
    ReasoningMessageChunkEvent() ||
    ReasoningEncryptedValueEvent() =>
      null,
  };
}
