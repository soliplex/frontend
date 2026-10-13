import 'dart:async';

import 'package:soliplex_agent/src/models/failure_reason.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_agent/src/orchestration/error_classifier.dart';
import 'package:soliplex_agent/src/orchestration/run_state.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Callback invoked when the model yields client-side tool calls.
///
/// Returns executed tools with status and result populated.
typedef ToolExecutorCallback = Future<List<ToolCallInfo>> Function(
  List<ToolCallInfo> pendingToolCalls,
);

/// Orchestrates a single AG-UI run lifecycle.
///
/// State machine: Idle -> Running -> Completed/ToolYielding/Failed/Cancelled.
/// Only one run at a time; concurrent calls throw [StateError].
///
/// ## Recommended: `runToCompletion()`
///
/// The recommended entry point is [runToCompletion], which drives the full
/// tool-yield/resume cycle internally and returns the terminal [RunState].
///
/// ```dart
/// final result = await orchestrator.runToCompletion(
///   key: key,
///   userMessage: [TextPart('Hello')],
///   toolExecutor: (pending) async {
///     return pending.map((tc) => tc.copyWith(
///       status: ToolCallStatus.completed,
///       result: await executeMyTool(tc),
///     )).toList();
///   },
/// );
/// ```
///
/// ## Backend flow
///
/// The caller is responsible for creating the thread before calling
/// [runToCompletion] or [startRun]. Typical sequence:
///
/// ```dart
/// // 1. Create thread (POST /rooms/{roomId}/agui)
/// final (threadInfo, aguiState) = await api.createThread(roomId);
///
/// // 2. Build ThreadKey from server-assigned thread ID
/// final key = (serverId: 'default', roomId: roomId, threadId: threadInfo.id);
///
/// // 3. Run to completion
/// final result = await orchestrator.runToCompletion(
///   key: key,
///   userMessage: [TextPart('Hello')],
///   toolExecutor: myToolExecutor,
///   existingRunId: threadInfo.hasInitialRun ? threadInfo.initialRunId : null,
/// );
/// ```
///
/// **Important:** Each [Tool] definition must include a `parameters` field
/// (JSON Schema). The backend rejects tool definitions without it.
class RunOrchestrator {
  /// Creates a [RunOrchestrator] with the given dependencies.
  RunOrchestrator({
    required AgentLlmProvider llmProvider,
    required ToolRegistry toolRegistry,
    required Logger logger,
    int maxToolDepth = defaultMaxToolDepth,
  })  : _llmProvider = llmProvider,
        _toolRegistry = toolRegistry,
        _logger = logger,
        _maxToolDepth = maxToolDepth;

  /// Default maximum tool-call depth before the orchestrator aborts.
  static const defaultMaxToolDepth = 10;

  final AgentLlmProvider _llmProvider;
  final ToolRegistry _toolRegistry;
  final Logger _logger;
  final int _maxToolDepth;

  /// The run being folded, kept past its end until the next turn starts: a
  /// continuation run carries the turn's citations forward from it, and an
  /// ending recorded while a run waits on a client tool is recorded on it.
  /// Null at turn start.
  RunFold? _fold;
  String? _userMessageId;

  final StreamController<RunState> _controller =
      StreamController<RunState>.broadcast();
  final StreamController<BaseEvent> _baseEventController =
      StreamController<BaseEvent>.broadcast();

  RunState _currentState = const IdleState();
  bool _disposed = false;
  bool _disposing = false;
  CancelToken? _cancelToken;
  StreamSubscription<DecodeOutcome>? _subscription;
  bool _receivedTerminalEvent = false;
  int _toolDepth = 0;

  // runToCompletion infrastructure
  Completer<RunState>? _terminalCompleter;
  int _subscriptionEpoch = 0;
  bool _runToCompletionActive = false;

  /// Reconnect callback for the active `runToCompletion`, threaded
  /// through every `startRun` call (initial + post-tool-yield resumes).
  void Function(ReconnectStatus)? _activeOnReconnectStatus;

  /// The current state of the orchestrator.
  RunState get currentState => _currentState;

  /// Broadcast stream of state transitions.
  Stream<RunState> get stateChanges => _controller.stream;

  /// Broadcast stream of AG-UI events whose application-layer
  /// processing succeeded on the active subscription.
  ///
  /// Used by `AgentSession` to bridge server-side events into the
  /// `ExecutionEvent` signal without duplicating event processing logic.
  /// Decode failures and `processEvent` throws surface as
  /// [DroppedEventMessage] tiles in the conversation and never reach
  /// this stream, so a tracker observing it stays consistent with the
  /// conversation state.
  Stream<BaseEvent> get baseEvents => _baseEventController.stream;

  /// Runs a complete agent interaction including all tool yield/resume cycles.
  ///
  /// State emissions continue on [stateChanges] for UI observers.
  /// Returns the terminal [RunState] (Completed, Failed, or Cancelled).
  ///
  /// While active, [startRun] and [submitToolOutputs] throw [StateError].
  Future<RunState> runToCompletion({
    required ThreadKey key,
    required List<MessagePart> userMessage,
    required ToolExecutorCallback toolExecutor,
    String? existingRunId,
    ThreadHistory? cachedHistory,
    Map<String, dynamic>? stateOverlay,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    _guardRunToCompletion();
    _runToCompletionActive = true;
    _activeOnReconnectStatus = (status) {
      _logReconnectStatus(status);
      onReconnectStatus?.call(status);
    };
    _toolDepth = 0;
    try {
      try {
        await _initializeStream(
          key,
          userMessage,
          existingRunId,
          cachedHistory,
          stateOverlay,
        );
      } on Object catch (error, stackTrace) {
        _handleStartError(key, error, stackTrace);
        return _currentState;
      }
      if (_disposed) return CancelledState.preRun(threadKey: key);
      return await _driveToolLoop(key, toolExecutor);
    } finally {
      _runToCompletionActive = false;
      _activeOnReconnectStatus = null;
    }
  }

  /// **Deprecated.** Use [runToCompletion] instead.
  ///
  /// Starts a new agent run. The caller must observe [stateChanges] and
  /// handle [ToolYieldingState] by calling [submitToolOutputs] manually.
  ///
  /// Throws [StateError] if already running, disposed, or
  /// [runToCompletion] is active.
  Future<void> startRun({
    required ThreadKey key,
    required List<MessagePart> userMessage,
    String? existingRunId,
    ThreadHistory? cachedHistory,
  }) async {
    _guardNotRunning();
    _toolDepth = 0;
    try {
      final conversation =
          _buildConversation(key, userMessage, cachedHistory, null);
      final input = _buildInput(key, conversation);
      final handle = await _llmProvider.startRun(
        key: key,
        input: input,
        existingRunId: existingRunId,
        cancelToken: _cancelToken,
      );
      if (_disposedDuringAwait()) return;
      final initialState = RunningState(
        threadKey: key,
        runId: handle.runId,
        conversation: conversation,
        streaming: const AwaitingText(),
      );
      _subscribeToStream(handle.events, initialState);
    } on Object catch (error, stackTrace) {
      _handleStartError(key, error, stackTrace);
    }
  }

  /// Cancels the current run. No-op if idle.
  void cancelRun() {
    _guardNotDisposed();
    switch (_currentState) {
      case final RunningState running:
        _cancelToken?.cancel();
        _cleanup();
        _setState(
          CancelledState.duringRun(
            threadKey: running.threadKey,
            runId: running.runId,
            conversation: _recordRunEndedAsCancelled(
              terminalEvent: 'cancelRun',
            ),
          ),
        );
      case final ToolYieldingState yielding:
        // A pending `_resumeStream` may be awaiting `_llmProvider.startRun`
        // with the live cancel token. Cancel the token + cleanup so that
        // await aborts before `_subscribeToStream` fires and overwrites
        // the CancelledState we set below.
        _cancelToken?.cancel();
        _cleanup();
        _setState(
          CancelledState.duringRun(
            threadKey: yielding.threadKey,
            runId: yielding.runId,
            // A yielding run withdrew its completion candidate; stopping here
            // ends it for real, so it parks one again as a cancel.
            conversation: _recordYieldEndedAsCancelled(),
          ),
        );
      case IdleState():
        // `_initializeStream` wires `_cancelToken` before awaiting
        // `startRun`, so an Idle state with `_runToCompletionActive` and
        // a live token is the in-flight-createRun window. Cancelling the
        // token aborts that await; `_handleStartError` then routes to
        // `CancelledState.preRun`. Without this, the user's Stop press
        // during a slow createRun is silently ignored and the run
        // continues once the response arrives.
        if (_runToCompletionActive && _cancelToken != null) {
          _cancelToken!.cancel();
          return;
        }
        _logger.warning(
          'cancelRun ignored: idle (no run active)',
          attributes: {'state': _currentState.runtimeType.toString()},
        );
        return;
      case CompletedState(:final threadKey) ||
            FailedState(:final threadKey) ||
            CancelledState(:final threadKey):
        _logger.warning(
          'cancelRun ignored: already terminal',
          attributes: {
            'state': _currentState.runtimeType.toString(),
            'threadKey': threadKey.toString(),
          },
        );
        return;
    }
  }

  /// Resets to [IdleState], cancelling any active run.
  void reset() {
    _guardNotDisposed();
    _cancelToken?.cancel();
    _cleanup();
    _fold = null;
    _userMessageId = null;
    _setState(const IdleState());
  }

  /// Syncs to a thread without starting a run.
  ///
  /// Pass `null` to clear (reset to idle).
  void syncToThread(ThreadKey? key) {
    _guardNotDisposed();
    if (key == null) {
      reset();
      return;
    }
    if (_currentState is RunningState || _currentState is ToolYieldingState) {
      throw StateError('Cannot sync while a run is active');
    }
    _fold = null;
    _userMessageId = null;
    _setState(const IdleState());
  }

  /// **Deprecated.** Use [runToCompletion] instead.
  ///
  /// Submits executed tool results and resumes the agent. Creates a **new
  /// backend run** for the continuation.
  ///
  /// Throws [StateError] if not in [ToolYieldingState], disposed, or
  /// [runToCompletion] is active.
  Future<void> submitToolOutputs(List<ToolCallInfo> executedTools) async {
    _guardSubmitToolOutputs();
    final yielding = _currentState as ToolYieldingState;
    _toolDepth++;
    if (_toolDepth > _maxToolDepth) {
      _failDepthExceeded(yielding.threadKey, yielding);
      return;
    }
    final conversation = _buildResumeConversation(yielding, executedTools);
    try {
      final input = _buildInput(yielding.threadKey, conversation);
      final handle = await _llmProvider.startRun(
        key: yielding.threadKey,
        input: input,
        cancelToken: _cancelToken,
      );
      if (_interruptedDuringResume()) return;
      final initialState = RunningState(
        threadKey: yielding.threadKey,
        runId: handle.runId,
        conversation: conversation,
        streaming: const AwaitingText(),
      );
      _subscribeToStream(handle.events, initialState);
    } on Object catch (error, stackTrace) {
      _handleStartError(yielding.threadKey, error, stackTrace);
    }
  }

  /// Releases all resources. Must be called when done.
  ///
  /// Safe to call during an active run — stream errors triggered by
  /// cancellation are silently absorbed to prevent unhandled exceptions.
  void dispose() {
    if (_disposed) return;
    _disposing = true;
    _disposed = true;
    _cancelToken?.cancel();
    _cancelToken = null;
    _completeTerminalOnDispose();
    if (!_receivedTerminalEvent) {
      _absorbTeardown(_subscription?.cancel(), 'dispose');
    }
    _subscription = null;
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
    if (!_baseEventController.isClosed) {
      unawaited(_baseEventController.close());
    }
    _disposing = false;
  }

  // ---------------------------------------------------------------------------
  // Private helpers — each <=40 LOC, <=4 params
  // ---------------------------------------------------------------------------

  /// Sets up the initial SSE subscription for [runToCompletion].
  Future<void> _initializeStream(
    ThreadKey key,
    List<MessagePart> userMessage,
    String? existingRunId,
    ThreadHistory? cachedHistory,
    Map<String, dynamic>? stateOverlay,
  ) async {
    _cancelToken ??= CancelToken();
    final conversation =
        _buildConversation(key, userMessage, cachedHistory, stateOverlay);
    final input = _buildInput(key, conversation);
    final handle = await _llmProvider.startRun(
      key: key,
      input: input,
      existingRunId: existingRunId,
      cancelToken: _cancelToken,
      onReconnectStatus: _activeOnReconnectStatus,
    );
    // Dispose during the await leaves us with an unowned stream; not
    // draining here leaks the SSE socket. Token-cancellation race
    // (Stop pressed during the await but resolved before cancellation
    // propagated) leaves us with an unwanted subscription that would
    // overwrite the user's cancel intent. Both paths drain and bail
    // before _subscribeToStream.
    if (_disposed) {
      _drainUnownedStream(handle.events, 'initialize drain (disposed)');
      return;
    }
    if (_cancelToken?.isCancelled ?? false) {
      _drainUnownedStream(handle.events, 'initialize drain (cancelled)');
      throw CancelledException(reason: _cancelToken?.reason);
    }
    _subscribeToStream(
      handle.events,
      RunningState(
        threadKey: key,
        runId: handle.runId,
        conversation: conversation,
        streaming: const AwaitingText(),
      ),
    );
  }

  /// Drains an SSE stream we no longer own (cancel/dispose during a
  /// post-`startRun` await), releasing the underlying socket.
  ///
  /// The listen and the cancel happen in one turn, and every provider in
  /// this package returns a cold `async*`, so no event can be delivered
  /// first and an `onData`/`onError` pair would never fire. Whatever the generator raises as it unwinds arrives on the cancel
  /// future instead, which is what [_absorbTeardown] reads; [site] labels the
  /// record so each drain is distinguishable in the log.
  void _drainUnownedStream(Stream<DecodeOutcome> events, String site) {
    _absorbTeardown(events.listen(null).cancel(), site);
  }

  /// Drives the tool yield/resume loop for [runToCompletion].
  ///
  /// Every operation inside the loop is wrapped in try/catch that returns
  /// a terminal [RunState], so a thrown exception cannot leave the
  /// orchestrator in a non-terminal state with the future still hanging.
  Future<RunState> _driveToolLoop(
    ThreadKey key,
    ToolExecutorCallback toolExecutor,
  ) async {
    while (true) {
      final state = await _terminalCompleter!.future;
      if (state is! ToolYieldingState) return state;
      if (_disposed) return _cancelledFromYielding(key, state);
      List<ToolCallInfo> results;
      try {
        results = await toolExecutor(state.pendingToolCalls);
      } on Object catch (e, stackTrace) {
        if (e is CancelledException || e is CancellationError) {
          return _cancelledFromYielding(key, state);
        }
        return _failToolExecution(key, state, e, stackTrace);
      }
      if (_disposed) return _cancelledFromYielding(key, state);
      if (_currentState is CancelledState) return _currentState;
      try {
        _toolDepth++;
        if (_toolDepth > _maxToolDepth) {
          return _failDepthExceeded(key, state);
        }
        await _resumeStream(state, results);
      } on Object catch (e, stackTrace) {
        // If `cancelRun` already transitioned to CancelledState, the
        // exception is the byproduct of cancellation propagating through
        // the in-flight `startRun` await — not a true failure.
        if (_currentState is CancelledState) return _currentState;
        return _failResume(key, state, e, stackTrace);
      }
    }
  }

  /// Resumes the SSE stream after tool execution.
  ///
  /// Creates a new backend run and subscribes to the continuation stream.
  Future<void> _resumeStream(
    ToolYieldingState yielding,
    List<ToolCallInfo> executedTools,
  ) async {
    // `_handleRunFinished` cleared the token for the tool-yield window;
    // mint a fresh one for the resume.
    _cancelToken ??= CancelToken();
    final conversation = _buildResumeConversation(yielding, executedTools);
    final input = _buildInput(yielding.threadKey, conversation);
    final handle = await _llmProvider.startRun(
      key: yielding.threadKey,
      input: input,
      cancelToken: _cancelToken,
      onReconnectStatus: _activeOnReconnectStatus,
    );
    // Cancel/reset/dispose during the await leaves state as CancelledState,
    // IdleState, or disposed. Subscribing here would overwrite that with
    // RunningState and silently resume the run after the user pressed Stop
    // (or synced away). Drain the unowned event stream so the underlying
    // SSE socket releases, then re-mint the terminal completer holding the
    // current state: `_setState` already consumed the old completer with
    // the now-stale ToolYieldingState, so without this `_driveToolLoop`'s
    // next await would return that yield and re-run the tool.
    if (_disposed || _currentState is! ToolYieldingState) {
      if (!_disposed &&
          _currentState is! CancelledState &&
          _currentState is! IdleState) {
        _logger.warning(
          'resumeStream aborted: unexpected post-await state '
          '(state=${_currentState.runtimeType})',
        );
      }
      _drainUnownedStream(handle.events, 'resume drain');
      _terminalCompleter = Completer<RunState>()..complete(_currentState);
      return;
    }
    _subscribeToStream(
      handle.events,
      RunningState(
        threadKey: yielding.threadKey,
        runId: handle.runId,
        conversation: conversation,
        streaming: const AwaitingText(),
      ),
    );
  }

  /// Transitions to [CancelledState] from a tool-yielding context.
  ///
  /// Mirrors the `_failX` helpers: fires the state through `_setState` so
  /// `stateChanges` observers see the terminal transition. A no-op
  /// constructor would leave `_currentState` at `ToolYieldingState`,
  /// so `AgentSession._completeWith` would never run and `result` would
  /// hang.
  CancelledState _cancelledFromYielding(
    ThreadKey key,
    ToolYieldingState state,
  ) {
    final cancelled = CancelledState.duringRun(
      threadKey: key,
      runId: state.runId,
      conversation: _recordYieldEndedAsCancelled(),
    );
    _setState(cancelled);
    return cancelled;
  }

  /// Returns a [FailedState] for an error thrown by the tool executor.
  RunState _failToolExecution(
    ThreadKey key,
    ToolYieldingState state,
    Object error,
    StackTrace stackTrace,
  ) {
    _logger.error(
      'Tool execution failed',
      error: error,
      stackTrace: stackTrace,
    );
    final detail = _messageOf(error);
    final failed = FailedState.duringRun(
      threadKey: key,
      runId: state.runId,
      reason: FailureReason.toolExecutionFailed,
      error: detail,
      conversation: _recordYieldEndedAsFailed(detail),
    );
    _setState(failed);
    return failed;
  }

  /// Returns a [FailedState] for an error thrown while resuming the run
  /// after a tool yield. Routes the reason through [classifyError] so
  /// transport-layer failures surface as their actual category rather
  /// than as `toolExecutionFailed`.
  RunState _failResume(
    ThreadKey key,
    ToolYieldingState state,
    Object error,
    StackTrace stackTrace,
  ) {
    _logger.error('Resume run failed', error: error, stackTrace: stackTrace);
    final detail = _messageOf(error);
    final failed = FailedState.duringRun(
      threadKey: key,
      runId: state.runId,
      reason: classifyError(error),
      error: detail,
      conversation: _recordYieldEndedAsFailed(detail),
    );
    _setState(failed);
    return failed;
  }

  /// Returns a [FailedState] when the tool depth limit is exceeded.
  RunState _failDepthExceeded(ThreadKey key, ToolYieldingState state) {
    final detail = 'Tool depth limit exceeded ($_maxToolDepth)';
    final failed = FailedState.duringRun(
      threadKey: key,
      runId: state.runId,
      reason: FailureReason.toolExecutionFailed,
      error: detail,
      conversation: _recordYieldEndedAsFailed(detail),
    );
    _setState(failed);
    return failed;
  }

  /// The waiting run's conversation with a record that it ended in failure.
  ///
  /// A run waiting on a client tool withdrew its completion candidate on the
  /// way in, because it was not over. Every exit from that wait ends it for
  /// real, and has to say so — a run that ended recording nothing has no tile
  /// to render the work the user watched it do, and reads to the thread as a
  /// run still in flight.
  Conversation _recordYieldEndedAsFailed(String detail) =>
      (_fold = _fold!.failed(detail, terminalEvent: 'toolYieldEnded'))
          .conversation;

  /// The waiting run's conversation with a record that it was stopped.
  Conversation _recordYieldEndedAsCancelled() =>
      (_fold = _fold!.cancelled(terminalEvent: 'toolYieldCancelled'))
          .conversation;

  /// The run's conversation with a record that it was stopped, stamped when
  /// the user stopped it. [terminalEvent] names the ending in the log.
  Conversation _recordRunEndedAsCancelled({required String terminalEvent}) =>
      (_fold = _fold!.cancelled(terminalEvent: terminalEvent).resolveTurn())
          .conversation;

  /// The run's conversation with a record that it failed with [detail],
  /// stamped with the last event the run delivered. [terminalEvent] names the
  /// ending in the log.
  Conversation _recordRunEndedAsFailed(
    String detail, {
    required String terminalEvent,
  }) =>
      (_fold =
              _fold!.failed(detail, terminalEvent: terminalEvent).resolveTurn())
          .conversation;

  /// [state] showing the run as the fold holds it.
  RunningState _runningFrom(RunningState state) => state.copyWith(
        conversation: _fold!.conversation,
        streaming: _fold!.streaming,
      );

  /// Whether [state] is terminal for the SSE subscription completer.
  ///
  /// Exhaustive switch expression — adding a new [RunState] variant
  /// without updating this method causes a compile error.
  bool _isTerminal(RunState state) => switch (state) {
        CompletedState() => true,
        FailedState() => true,
        CancelledState() => true,
        ToolYieldingState() => true,
        RunningState() => false,
        IdleState() => false,
      };

  /// Completes [_terminalCompleter] when [dispose] runs while a backend
  /// run is in flight, so `runToCompletion`'s await of the completer
  /// future doesn't hang.
  ///
  /// The early return covers two of the three reachable states:
  ///   - `IdleState` (and pre-run paths): completer is null because
  ///     [_subscribeToStream] hasn't run yet; `?.isCompleted ?? true`
  ///     evaluates to true.
  ///   - Terminal states (`Completed`/`Failed`/`Cancelled`) and
  ///     `ToolYieldingState`: [_setState] already completed the completer
  ///     because [_isTerminal] returns true for all four.
  ///
  /// That leaves only `RunningState` reachable past the early return —
  /// the synchronous window between [_subscribeToStream]'s completer
  /// assignment and the next event-driven transition. There is no
  /// microtask boundary where dispose could fall on any other state with
  /// an uncompleted completer, so the other arms throw `StateError` to
  /// surface invariant breakage instead of fabricating data.
  void _completeTerminalOnDispose() {
    if (_terminalCompleter?.isCompleted ?? true) return;
    if (_currentState case RunningState(:final threadKey, :final runId)) {
      _terminalCompleter!.complete(
        CancelledState.duringRun(
          threadKey: threadKey,
          runId: runId,
          // Disposal ends the run as a stop does, so whoever awaits the run
          // gets the conversation a stop would have left: the partial reply
          // committed and what the run was sent restored.
          conversation: _recordRunEndedAsCancelled(terminalEvent: 'dispose'),
        ),
      );
      return;
    }
    throw StateError(
      '_completeTerminalOnDispose: unexpected state '
      '${_currentState.runtimeType} with uncompleted terminalCompleter',
    );
  }

  void _guardRunToCompletion() {
    _guardNotDisposed();
    if (_runToCompletionActive) {
      throw StateError('runToCompletion is already active');
    }
    if (_currentState is RunningState || _currentState is ToolYieldingState) {
      throw StateError('A run is already active');
    }
  }

  void _guardNotRunning() {
    _guardNotDisposed();
    if (_runToCompletionActive) {
      throw StateError('Cannot call startRun while runToCompletion is active');
    }
    if (_currentState is RunningState || _currentState is ToolYieldingState) {
      throw StateError('A run is already active');
    }
  }

  void _guardNotDisposed() {
    if (_disposed) {
      throw StateError('RunOrchestrator has been disposed');
    }
  }

  void _guardSubmitToolOutputs() {
    _guardNotDisposed();
    if (_runToCompletionActive) {
      throw StateError(
        'Cannot call submitToolOutputs while runToCompletion is active',
      );
    }
    if (_currentState is! ToolYieldingState) {
      throw StateError('Not in ToolYieldingState');
    }
  }

  /// Returns true if the orchestrator was disposed during an async gap.
  ///
  /// Use after `await` in [startRun] where the pre-await state is [IdleState].
  bool _disposedDuringAwait() => _disposed;

  /// Returns true if the state was changed during an async gap.
  ///
  /// Use after `await` in [submitToolOutputs] where the pre-await state is
  /// [ToolYieldingState]. Detects cancel, reset, or dispose.
  bool _interruptedDuringResume() {
    return _disposed || _currentState is! ToolYieldingState;
  }

  List<ToolCallInfo> _extractPendingTools(Conversation conversation) {
    return conversation.toolCalls
        .where(
          (tc) =>
              tc.status == ToolCallStatus.pending &&
              _toolRegistry.contains(tc.name),
        )
        .toList();
  }

  Conversation _buildResumeConversation(
    ToolYieldingState state,
    List<ToolCallInfo> executedTools,
  ) {
    final executedIds = {for (final tc in executedTools) tc.id};
    final updatedToolCalls = state.conversation.toolCalls.map((tc) {
      if (executedIds.contains(tc.id)) {
        return executedTools.firstWhere((e) => e.id == tc.id);
      }
      return tc;
    }).toList();
    final toolMsg = ToolCallMessage.fromExecuted(
      id: 'tool-result-${DateTime.now().microsecondsSinceEpoch}',
      toolCalls: executedTools,
      runId: state.runId,
    );
    // Appended where the result arrived: after whatever its run streamed. A
    // failed call's error goes too, as its content, so the model can respond
    // to it. pydantic-ai marks a result failed only from its `error` field or
    // an encrypted outcome; neither is set here, so pydantic-ai reads a failed
    // client call back as a success.
    final transcript = executedTools.fold(
      state.conversation.transcript,
      (transcript, tc) => appendToolResult(
        transcript,
        ToolMessage(
          id: 'tool_result_${tc.id}',
          toolCallId: tc.id,
          content: tc.result,
        ),
      ),
    );
    return state.conversation.copyWith(
      messages: [...state.conversation.messages, toolMsg],
      toolCalls: updatedToolCalls,
      transcript: transcript,
    );
  }

  /// The highest attachment number already handed out in [messages].
  int _highestAttachmentNumber(List<ChatMessage> messages) {
    var highest = 0;
    for (final message in messages) {
      if (message is! TextMessage) continue;
      final number = message.parts?.highestAttachmentNumber;
      if (number != null && number > highest) highest = number;
    }
    return highest;
  }

  Conversation _buildConversation(
    ThreadKey key,
    List<MessagePart> userMessage,
    ThreadHistory? cachedHistory,
    Map<String, dynamic>? stateOverlay,
  ) {
    final priorMessages = cachedHistory?.messages ?? <ChatMessage>[];
    // Attachments are named here, once, and carry that name for the rest of the
    // thread. Counting from one past the highest already handed out — rather
    // than from how many there are — is what keeps a name unique: an attachment
    // that stopped being sent leaves a gap, and reusing its number would point
    // an earlier answer at a different picture.
    final numbered = userMessage.numberedFrom(
      _highestAttachmentNumber(priorMessages) + 1,
    );
    // No authoritative time exists at submit — the run has no server time yet —
    // so the optimistic echo starts without one (createdAt: null, the default).
    // It is stamped with the run's server start time when RunStartedEvent
    // arrives, and fills from the run's server `created` on replay. The
    // frontend never displays a client-generated time. now() here is only for
    // a unique id.
    //
    // Text alone travels the wire as a bare string, which a reload reads back
    // without parts, so the echo keeps its parts only when they say more than
    // its text: when it carries an attachment.
    final id = 'user-${DateTime.now().microsecondsSinceEpoch}';
    final userMsg = numbered.hasAttachment
        ? TextMessage.fromParts(id: id, parts: numbered)
        : TextMessage.create(
            id: id,
            user: ChatUser.user,
            text: numbered.plainText,
          );
    // Seeding with the run-scoped keys emptied is what makes a namespace's
    // non-empty `citations` in the run's terminal snapshot definitionally this
    // turn's. The overlay merges on top, so a caller-set `document_filter`
    // still applies. A scope value or `citation_index` entry no backend
    // accepts is cleared first, or every send from the thread would fail on it.
    final baseState = RagSnapshot.withEmptyRunScopedKeys(
      RagSnapshot.withUnreadableCitationsDropped(
        withRejectedScopeCleared(cachedHistory?.aguiState ?? const {}),
      ),
    );
    final aguiState =
        stateOverlay == null ? baseState : _mergeState(baseState, stateOverlay);
    _fold = null;
    _userMessageId = userMsg.id;
    return appendUserMessage(
      Conversation(
        threadId: key.threadId,
        messages: priorMessages,
        aguiState: aguiState,
        aguiStateIncomplete: cachedHistory?.aguiStateIncomplete ?? false,
        messageStates: cachedHistory?.messageStates ?? const {},
        // Every send builds this afresh, so a run that ended earlier in the
        // thread loses its outcome unless it is carried over here.
        runOutcomes: cachedHistory?.runOutcomes ?? const {},
        transcript: cachedHistory?.transcript ?? const Transcript(),
      ),
      userMsg,
    );
  }

  /// Recursively deep-merges [overlay] into [base].
  ///
  /// When both sides have a `Map` for the same key the maps are merged
  /// recursively. Otherwise the [overlay] value wins — including `List`s,
  /// which are replaced entirely, not concatenated.
  static Map<String, dynamic> _mergeState(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final result = Map<String, dynamic>.of(base);
    for (final entry in overlay.entries) {
      final existing = result[entry.key];
      if (existing is Map && entry.value is Map) {
        result[entry.key] = _mergeState(
          Map<String, dynamic>.from(existing),
          Map<String, dynamic>.from(entry.value as Map),
        );
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  SimpleRunAgentInput _buildInput(ThreadKey key, Conversation conversation) {
    return SimpleRunAgentInput(
      threadId: key.threadId,
      runId: '', // Assigned by the provider during startRun.
      messages: conversation.transcript.messages,
      tools: _toolRegistry.toolDefinitions,
      state: conversation.aguiState,
    );
  }

  void _subscribeToStream(
    Stream<DecodeOutcome> events,
    RunningState initialState,
  ) {
    // Cancel stale subscription from the previous run.
    // `_subscriptionEpoch` (incremented below) guards `onDone` only,
    // which can fire after the new subscription replaces the old one.
    // `onData`/`onError` cease firing on the cancelled subscription, so
    // they need no epoch guard.
    _absorbTeardown(_subscription?.cancel(), 'stale subscription');
    _subscription = null;
    _cancelToken ??= CancelToken();
    _receivedTerminalEvent = false;
    _terminalCompleter = Completer<RunState>();
    _subscriptionEpoch++;
    final epoch = _subscriptionEpoch;
    // The provider returned this run's id before the stream opened, so the run
    // is known before any of its events is read. Leaving the conversation to
    // learn that from a `RUN_STARTED` leaves a stream carrying none with every
    // message unattributed and no record of how the run ended — the same gap
    // replay closes from the id its events were fetched under. Every path that
    // opens a stream arrives here, so this is where the two agree. A
    // continuation run carries the turn's citations on from the run it
    // continues.
    _fold = RunFold.start(
      initialState.conversation,
      runId: initialState.runId,
      userMessageId: _userMessageId,
      turnCitations: _fold?.turnCitations ?? const TurnCitations.empty(),
    );
    _setState(_runningFrom(initialState));
    _subscription = events.listen(
      _onEvent,
      onError: _onStreamError,
      onDone: () {
        if (epoch != _subscriptionEpoch) return;
        _onStreamDone();
      },
    );
  }

  void _onEvent(DecodeOutcome outcome) {
    final running = _currentState;
    final fold = _fold;
    if (running is! RunningState || fold == null) {
      _ignoreStrayEvent(outcome, running);
      return;
    }
    final applied = fold.apply(outcome);
    _fold = applied.fold;
    final event = applied.processed;
    if (event == null) {
      _setState(_runningFrom(running));
      return;
    }
    _mapEventResult(running, event, pausedIn: fold.streaming);
    if (!_baseEventController.isClosed) {
      _baseEventController.add(event);
    }
  }

  /// An event that arrived after its run ended (a stray event after terminal
  /// cleanup) has no run to fold into. A decode failure is still logged at
  /// error, as it would have been mid-run, because the tile that would have
  /// shown it cannot be appended.
  void _ignoreStrayEvent(DecodeOutcome outcome, RunState state) {
    if (outcome case DecodeFailed(:final error, :final stackTrace)) {
      _logger.error(
        'Dropped event with no run in progress; no tile appended',
        stackTrace: stackTrace,
        attributes: {
          'failure': describeFailure(error),
          'state': state.runtimeType.toString(),
        },
      );
    }
  }

  /// Publishes what [event], just folded in, did to the run. [pausedIn] is
  /// the streaming state before it, which a run that yields to a client tool
  /// keeps.
  void _mapEventResult(
    RunningState previous,
    BaseEvent event, {
    required StreamingState pausedIn,
  }) {
    if (event is RunFinishedEvent) {
      _handleRunFinished(previous, pausedIn);
      return;
    }
    if (event is RunErrorEvent) {
      _receivedTerminalEvent = true;
      _cleanup();
      final fold = _fold = _fold!.resolveTurn();
      _setState(
        FailedState.duringRun(
          threadKey: previous.threadKey,
          runId: previous.runId,
          reason: FailureReason.serverError,
          error: event.message,
          conversation: fold.conversation,
        ),
      );
      return;
    }
    _setState(_runningFrom(previous));
  }

  void _handleRunFinished(RunningState previous, StreamingState pausedIn) {
    _receivedTerminalEvent = true;
    // Leave `_subscription` set so `_subscribeToStream` cancels it on
    // resume. Nulling here would silently leak the prior subscription on
    // a resume, since `_subscribeToStream`'s cancel-and-replace would
    // skip its `?.cancel()` call. `onDone` (the natural SSE close) is
    // also handled by `_onStreamDone`, which nulls the field.
    _cancelToken = null;
    final fold = _fold = _fold!.resolveTurn();
    final pendingTools = _extractPendingTools(fold.conversation);
    if (pendingTools.isNotEmpty) {
      // `processEvent` parked a completion candidate when it saw RUN_FINISHED,
      // before this branch knew the run is waiting on a client tool rather
      // than over. This is where that is known, so the candidate is taken
      // back — before any subscriber has seen it.
      final paused = _fold = fold.pausedForClientTools(streaming: pausedIn);
      _setState(
        ToolYieldingState(
          threadKey: previous.threadKey,
          runId: previous.runId,
          streaming: paused.streaming,
          conversation: paused.conversation,
          pendingToolCalls: pendingTools,
          toolDepth: _toolDepth,
        ),
      );
    } else {
      _setState(
        CompletedState(
          threadKey: previous.threadKey,
          runId: previous.runId,
          conversation: fold.conversation,
        ),
      );
    }
  }

  void _onStreamDone() {
    _subscription = null;
    if (_disposing || _disposed) return;
    if (_receivedTerminalEvent) return;
    final running = _currentState;
    if (running is! RunningState) return;
    _cleanup();
    _logger.warning('Stream ended without terminal event');
    final detail = _fold!.cutOffDetail;
    _setState(
      FailedState.duringRun(
        threadKey: running.threadKey,
        runId: running.runId,
        reason: FailureReason.streamEndedEarly,
        error: detail,
        conversation: _recordRunEndedAsFailed(
          detail,
          terminalEvent: 'streamEndedWithoutTerminal',
        ),
      ),
    );
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    if (_disposing || _disposed) return;
    final running = _currentState;
    if (running is! RunningState) return;
    _cleanup();
    if (error is CancelledException || error is CancellationError) {
      _setState(
        CancelledState.duringRun(
          threadKey: running.threadKey,
          runId: running.runId,
          conversation: _recordRunEndedAsCancelled(
            terminalEvent: 'streamCancelled',
          ),
        ),
      );
      return;
    }
    final reason = classifyError(error);
    _logger.error('Run failed', error: error, stackTrace: stackTrace);
    _setState(
      FailedState.duringRun(
        threadKey: running.threadKey,
        runId: running.runId,
        reason: reason,
        error: _messageOf(error),
        conversation: _recordRunEndedAsFailed(
          _messageOf(error),
          terminalEvent: 'streamError',
        ),
      ),
    );
  }

  void _handleStartError(ThreadKey key, Object error, StackTrace stackTrace) {
    _cleanup();
    if (error is CancelledException || error is CancellationError) {
      // A cancel that fired while `_initializeStream → startRun` was
      // in flight surfaces here. Route to `CancelledState` so the
      // user-visible result mirrors mid-stream cancel handling —
      // not a `FailedState(reason: internalError)`. Accepts both
      // `CancelledException` (from our `CancelToken`) and
      // `CancellationError` (ag_ui's, for interop with its client).
      _setState(CancelledState.preRun(threadKey: key));
      return;
    }
    final reason = classifyError(error);
    _logger.error('Failed to start run', error: error, stackTrace: stackTrace);
    _setState(
      FailedState.preRun(
        threadKey: key,
        reason: reason,
        error: _messageOf(error),
      ),
    );
  }

  void _setState(RunState newState) {
    _currentState = newState;
    if (!_controller.isClosed) {
      _controller.add(newState);
    }
    if (_isTerminal(newState) && !(_terminalCompleter?.isCompleted ?? true)) {
      _terminalCompleter!.complete(newState);
    }
  }

  /// Absorbs whatever the teardown of an SSE subscription surfaces, where
  /// [pending] is the future returned by [StreamSubscription.cancel] and
  /// [site] names the teardown on the log record.
  ///
  /// Cancelling that subscription unwinds the provider's `async*` generator.
  /// An error raised while it unwinds is delivered here rather than to the
  /// subscription's `onError`, so discarding this future lets it reach the
  /// zone as an unhandled error.
  ///
  /// The expected one is the cancellation the transport injects when the
  /// run's token fires, scheduled by the token's completer and so still
  /// undelivered when the caller's cancel runs. Every caller has its own
  /// route to the outcome — a terminal state it publishes, or an exception
  /// it throws — so this second copy carries nothing its recipient does not
  /// already have: deliberate silence. Anything else is a real teardown
  /// failure and is logged.
  void _absorbTeardown(Future<void>? pending, String site) {
    if (pending == null) return;
    unawaited(
      pending.catchError((Object e, StackTrace st) {
        if (e is CancelledException || e is CancellationError) return;
        _logger.warning(
          'SSE subscription teardown failed: $site',
          attributes: {'failure': describeFailure(e)},
          stackTrace: st,
        );
      }),
    );
  }

  void _cleanup() {
    _absorbTeardown(_subscription?.cancel(), 'cleanup');
    _subscription = null;
    _cancelToken = null;
  }

  /// Returns a clean message string for [error], unwrapping
  /// [SoliplexException] so prefix-based matching downstream
  /// (e.g. on [streamResumeFailedPrefix]) sees the raw message rather
  /// than `RuntimeType: …`.
  String _messageOf(Object error) =>
      error is SoliplexException ? error.message : error.toString();

  void _logReconnectStatus(ReconnectStatus status) {
    switch (status) {
      case Reconnecting(:final attempt, :final lastEventId, :final error):
        _logger.info(
          'SSE reconnecting (attempt $attempt)',
          error: error,
          attributes: {
            'attempt': attempt,
            if (lastEventId != null) 'lastEventId': lastEventId,
          },
        );
      case Reconnected(:final attempt):
        _logger.info(
          'SSE reconnected after $attempt attempt(s)',
          attributes: {'attempt': attempt},
        );
      case ReconnectFailed(:final attempt, :final error):
        _logger.warning(
          'SSE reconnect failed after $attempt attempt(s)',
          error: error,
          attributes: {'attempt': attempt},
        );
    }
  }
}
