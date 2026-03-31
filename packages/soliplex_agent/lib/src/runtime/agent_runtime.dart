import 'dart:async';

import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/host/platform_constraints.dart';
import 'package:soliplex_agent/src/models/agent_result.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/ag_ui_llm_provider.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_agent/src/orchestration/run_state.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/agent_session_state.dart';
import 'package:soliplex_agent/src/runtime/agent_ui_delegate.dart';
import 'package:soliplex_agent/src/runtime/server_connection.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry_resolver.dart';
import 'package:soliplex_client/soliplex_client.dart' show ThreadHistory;
import 'package:soliplex_logging/soliplex_logging.dart';

/// Facade for spawning and coordinating multiple [AgentSession]s.
///
/// Each runtime is bound to a single backend server via [AgentLlmProvider].
/// The [serverId] identifies which server this runtime talks to and is
/// embedded into every [ThreadKey] created by [spawn].
///
/// ```dart
/// final runtime = AgentRuntime(
///   connection: connection,
///   toolRegistryResolver: resolver,
///   platform: NativePlatformConstraints(),
///   logger: logger,
/// );
///
/// final session = await runtime.spawn(
///   roomId: 'weather',
///   prompt: 'Need umbrella?',
/// );
/// final result = await session.result;
/// ```
class AgentRuntime {
  /// Creates a runtime bound to a single [ServerConnection].
  ///
  /// [maxSpawnDepth] limits how deep the parent-child spawn tree can grow.
  /// Set to `0` to disable depth checking (default: 10).
  ///
  /// [rootTimeout] is an optional wall-clock timeout applied to root sessions
  /// (those without a parent). When the timeout fires, the root session and
  /// all its children are cancelled.
  AgentRuntime({
    required ServerConnection connection,
    required ToolRegistryResolver toolRegistryResolver,
    required PlatformConstraints platform,
    required Logger logger,
    AgentLlmProvider? llmProvider,
    SessionExtensionFactory? extensionFactory,
    AgentUiDelegate? uiDelegate,
    this.maxSpawnDepth = 10,
    this.rootTimeout,
  })  : serverId = connection.serverId,
        _connection = connection,
        _llmProvider = llmProvider ??
            AgUiLlmProvider(
              api: connection.api,
              agUiStreamClient: connection.agUiStreamClient,
            ),
        _toolRegistryResolver = toolRegistryResolver,
        _extensionFactory = extensionFactory,
        _uiDelegate = uiDelegate,
        _platform = platform,
        _logger = logger;

  final ServerConnection _connection;
  final AgentLlmProvider _llmProvider;
  final ToolRegistryResolver _toolRegistryResolver;
  final SessionExtensionFactory? _extensionFactory;
  final AgentUiDelegate? _uiDelegate;
  final PlatformConstraints _platform;
  final Logger _logger;

  /// Identifies which backend server this runtime targets.
  final String serverId;

  /// Maximum depth of the parent-child spawn tree. `0` disables the check.
  final int maxSpawnDepth;

  /// Optional wall-clock timeout for root sessions (no parent).
  ///
  /// When set, a [Timer] fires after this duration and cancels the root
  /// session, cascading to all children.
  final Duration? rootTimeout;

  final Map<String, AgentSession> _sessions = {};
  final Map<String, Timer> _rootTimeoutTimers = {};
  final Set<String> _deletedThreadIds = {};
  final Map<String, ThreadHistory> _threadHistories = {};
  final _spawnQueue = <Completer<void>>[];
  final StreamController<List<AgentSession>> _sessionController =
      StreamController<List<AgentSession>>.broadcast();
  final Signal<List<AgentSession>> _sessionsSignal = signal([]);
  bool _disposed = false;

  /// Currently tracked (non-disposed) sessions.
  List<AgentSession> get activeSessions =>
      List.unmodifiable(_sessions.values.toList());

  /// Emits whenever the active session list changes.
  ///
  /// **Deprecated.** Use [sessions] signal instead.
  Stream<List<AgentSession>> get sessionChanges => _sessionController.stream;

  /// Reactive signal of currently tracked sessions.
  ///
  /// Updates synchronously when sessions are spawned or completed.
  ReadonlySignal<List<AgentSession>> get sessions => _sessionsSignal.readonly();

  /// Looks up a session by its [ThreadKey]. Returns `null` if not found.
  AgentSession? getSession(ThreadKey key) {
    return _sessions.values.where((s) => s.threadKey == key).firstOrNull;
  }

  /// Number of spawn requests waiting for a concurrency slot.
  int get pendingSpawnCount => _spawnQueue.length;

  /// Spawns a new agent session.
  ///
  /// Creates a thread (or reuses [threadId]), resolves tools for [roomId],
  /// builds an [AgentSession], and starts the run. If the concurrency limit
  /// is reached, waits for a slot to open before proceeding.
  ///
  /// When [parent] is provided, the new session is registered as a child
  /// of that parent. Cancelling or disposing the parent will cascade to
  /// all children.
  Future<AgentSession> spawn({
    required String roomId,
    required String prompt,
    String? threadId,
    Duration? timeout,
    bool ephemeral = false,
    bool autoDispose = false,
    AgentSession? parent,
  }) async {
    _guardNotDisposed();
    await _waitForSlot();
    _guardSpawnDepth(parent);
    final depth = parent == null ? 0 : parent.depth + 1;
    final (key, existingRunId) = await _resolveThread(roomId, threadId);
    final history = _threadHistories[key.threadId];
    final session = await _buildSession(
      key: key,
      roomId: roomId,
      ephemeral: ephemeral,
      depth: depth,
    );
    _trackSession(session);
    parent?.addChild(session);
    try {
      await session.start(
        userMessage: prompt,
        existingRunId: existingRunId,
        cachedHistory: history,
      );
    } on Object {
      parent?.removeChild(session);
      _removeSession(session);
      if (ephemeral) {
        await _deleteThreadSafe(key);
      }
      session.dispose();
      rethrow;
    }
    _scheduleCompletion(session, timeout, autoDispose: autoDispose);
    _scheduleRootTimeout(session, parent);
    return session;
  }

  /// Waits for all sessions to complete, collecting results.
  Future<List<AgentResult>> waitAll(
    List<AgentSession> sessions, {
    Duration? timeout,
  }) {
    return Future.wait(sessions.map((s) => s.awaitResult(timeout: timeout)));
  }

  /// Returns the first result from any of the given sessions.
  Future<AgentResult> waitAny(
    List<AgentSession> sessions, {
    Duration? timeout,
  }) {
    return Future.any(sessions.map((s) => s.awaitResult(timeout: timeout)));
  }

  /// Cancels all active sessions.
  Future<void> cancelAll() async {
    for (final session in _sessions.values.toList()) {
      session.cancel();
    }
  }

  /// Disposes the runtime and all sessions.
  ///
  /// Cancels active sessions, deletes ephemeral threads (swallowing
  /// errors), and closes the session stream.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final completer in _spawnQueue) {
      completer.complete();
    }
    _spawnQueue.clear();
    for (final timer in _rootTimeoutTimers.values) {
      timer.cancel();
    }
    _rootTimeoutTimers.clear();
    await cancelAll();
    await _cleanupEphemeralThreads();
    for (final session in _sessions.values.toList()) {
      session.dispose();
    }
    _sessions.clear();
    _sessionsSignal.dispose();
    unawaited(_sessionController.close());
  }

  // ---------------------------------------------------------------------------
  // Guards
  // ---------------------------------------------------------------------------

  void _guardNotDisposed() {
    if (_disposed) {
      throw StateError('AgentRuntime has been disposed');
    }
  }

  Future<void> _waitForSlot() async {
    if (_activeCount < _platform.maxConcurrentSessions) return;
    final completer = Completer<void>();
    _spawnQueue.add(completer);
    await completer.future;
    _guardNotDisposed();
  }

  void _drainQueue() {
    if (_spawnQueue.isEmpty) return;
    if (_activeCount >= _platform.maxConcurrentSessions) return;
    _spawnQueue.removeAt(0).complete();
  }

  void _guardSpawnDepth(AgentSession? parent) {
    if (maxSpawnDepth <= 0 || parent == null) return;
    if (parent.depth + 1 >= maxSpawnDepth) {
      throw StateError(
        'Spawn depth limit reached '
        '(${parent.depth + 1} / $maxSpawnDepth)',
      );
    }
  }

  int get _activeCount =>
      _sessions.values.where((s) => !s.state.isTerminal).length;

  // ---------------------------------------------------------------------------
  // Thread resolution
  // ---------------------------------------------------------------------------

  Future<(ThreadKey, String?)> _resolveThread(
    String roomId,
    String? threadId,
  ) async {
    if (threadId != null) {
      final key = (serverId: serverId, roomId: roomId, threadId: threadId);
      return (key, null);
    }
    final (threadInfo, _) = await _connection.api.createThread(roomId);
    final key = (serverId: serverId, roomId: roomId, threadId: threadInfo.id);
    final existingRunId =
        threadInfo.hasInitialRun ? threadInfo.initialRunId : null;
    return (key, existingRunId);
  }

  // ---------------------------------------------------------------------------
  // Session building
  // ---------------------------------------------------------------------------

  Future<AgentSession> _buildSession({
    required ThreadKey key,
    required String roomId,
    required bool ephemeral,
    required int depth,
  }) async {
    var toolRegistry = await _toolRegistryResolver(roomId);
    final extensions = await _createExtensions();
    for (final ext in extensions) {
      for (final tool in ext.tools) {
        toolRegistry = toolRegistry.register(tool);
      }
    }
    final orchestrator = RunOrchestrator(
      llmProvider: _llmProvider,
      toolRegistry: toolRegistry,
      logger: _logger,
    );
    return AgentSession(
      threadKey: key,
      ephemeral: ephemeral,
      depth: depth,
      runtime: this,
      orchestrator: orchestrator,
      toolRegistry: toolRegistry,
      extensions: extensions,
      uiDelegate: _uiDelegate,
      logger: _logger,
    );
  }

  Future<List<SessionExtension>> _createExtensions() async {
    if (_extensionFactory == null) return const [];
    return _extensionFactory();
  }

  // ---------------------------------------------------------------------------
  // Session tracking
  // ---------------------------------------------------------------------------

  void _trackSession(AgentSession session) {
    _sessions[session.id] = session;
    _emitSessions();
  }

  void _removeSession(AgentSession session) {
    _sessions.remove(session.id);
    _emitSessions();
    _drainQueue();
  }

  void _emitSessions() {
    if (_disposed) return;
    final current = activeSessions;
    _sessionsSignal.value = current;
    if (!_sessionController.isClosed) {
      _sessionController.add(current);
    }
  }

  // ---------------------------------------------------------------------------
  // Completion scheduling
  // ---------------------------------------------------------------------------

  void _scheduleCompletion(
    AgentSession session,
    Duration? timeout, {
    required bool autoDispose,
  }) {
    final future = timeout != null
        ? session.awaitResult(timeout: timeout)
        : session.result;
    unawaited(
      future.then((_) async {
        if (_disposed) return;
        _captureThreadHistory(session);
        if (autoDispose) {
          await _handleSessionComplete(session);
        } else {
          // Caller owns the lifecycle — just update tracking and
          // drain the spawn queue so waiting spawns can proceed.
          _emitSessions();
          _drainQueue();
        }
      }),
    );
  }

  void _scheduleRootTimeout(AgentSession session, AgentSession? parent) {
    if (parent != null || rootTimeout == null) return;
    _rootTimeoutTimers[session.id] = Timer(rootTimeout!, () {
      _logger.warning(
        'Root session ${session.id} timed out after $rootTimeout',
      );
      session.cancel();
    });
  }

  Future<void> _handleSessionComplete(AgentSession session) async {
    _rootTimeoutTimers.remove(session.id)?.cancel();
    if (session.ephemeral) {
      await _deleteThreadSafe(session.threadKey);
    }
    session.dispose();
    _removeSession(session);
  }

  /// Captures conversation state from a completed or cancelled session so
  /// subsequent spawns on the same thread automatically include prior context.
  void _captureThreadHistory(AgentSession session) {
    if (session.ephemeral) return;
    final state = session.runState.value;
    final history = switch (state) {
      CompletedState(:final conversation) => ThreadHistory(
          messages: conversation.messages,
          aguiState: conversation.aguiState,
          messageStates: conversation.messageStates,
        ),
      CancelledState(:final conversation) when conversation != null =>
        ThreadHistory(
          messages: conversation.messages,
          aguiState: conversation.aguiState,
          messageStates: conversation.messageStates,
        ),
      _ => null,
    };
    if (history == null) return;
    _threadHistories[session.threadKey.threadId] = history;
  }

  // ---------------------------------------------------------------------------
  // Ephemeral cleanup
  // ---------------------------------------------------------------------------

  Future<void> _cleanupEphemeralThreads() async {
    final ephemeral = _sessions.values.where((s) => s.ephemeral).toList();
    for (final session in ephemeral) {
      await _deleteThreadSafe(session.threadKey);
    }
  }

  Future<void> _deleteThreadSafe(ThreadKey key) async {
    if (!_deletedThreadIds.add(key.threadId)) return;
    try {
      await _connection.api.deleteThread(key.roomId, key.threadId);
    } on Object catch (error) {
      _logger.warning('Failed to delete thread ${key.threadId}', error: error);
    }
  }
}

/// Extension to check terminal states on [AgentSessionState].
extension _AgentSessionStateX on AgentSessionState {
  bool get isTerminal =>
      this == AgentSessionState.completed ||
      this == AgentSessionState.failed ||
      this == AgentSessionState.cancelled;
}
