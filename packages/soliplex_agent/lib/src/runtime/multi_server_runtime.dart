import 'dart:async';

import 'package:soliplex_agent/src/host/platform_constraints.dart';
import 'package:soliplex_agent/src/models/agent_result.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/ag_ui_llm_provider.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_agent/src/runtime/agent_runtime.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/server_connection.dart';
import 'package:soliplex_agent/src/runtime/server_registry.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry_resolver.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Creates an [AgentLlmProvider] from a [ServerConnection].
///
/// Defaults to [AgUiLlmProvider] when not specified in
/// [MultiServerRuntime].
typedef LlmProviderFactory =
    AgentLlmProvider Function(
      ServerConnection connection,
    );

/// Coordinator wrapping per-server [AgentRuntime] instances.
///
/// Routes operations to the correct server's runtime based on
/// `serverId`. Runtimes are created lazily on first access via
/// [runtimeFor].
class MultiServerRuntime {
  MultiServerRuntime({
    required ServerRegistry registry,
    required ToolRegistryResolver toolRegistryResolver,
    required PlatformConstraints platform,
    required Logger logger,
    LlmProviderFactory? llmProviderFactory,
    SessionExtensionFactory? extensionFactory,
  }) : _registry = registry,
       _toolRegistryResolver = toolRegistryResolver,
       _llmProviderFactory = llmProviderFactory ?? _defaultLlmProviderFactory,
       _extensionFactory = extensionFactory,
       _platform = platform,
       _logger = logger;

  final ServerRegistry _registry;
  final ToolRegistryResolver _toolRegistryResolver;
  final LlmProviderFactory _llmProviderFactory;
  final SessionExtensionFactory? _extensionFactory;
  final PlatformConstraints _platform;
  final Logger _logger;

  static AgentLlmProvider _defaultLlmProviderFactory(
    ServerConnection connection,
  ) => AgUiLlmProvider(
    api: connection.api,
    agUiStreamClient: connection.agUiStreamClient,
  );

  final Map<String, AgentRuntime> _runtimes = {};
  bool _disposed = false;

  /// Returns (lazily creating) the [AgentRuntime] for [serverId].
  ///
  /// Throws [StateError] if [serverId] is not in the registry or
  /// this runtime is disposed.
  AgentRuntime runtimeFor(String serverId) {
    _guardNotDisposed();
    return _runtimes.putIfAbsent(serverId, () {
      final connection = _registry.require(serverId);
      return AgentRuntime(
        connection: connection,
        llmProvider: _llmProviderFactory(connection),
        toolRegistryResolver: _toolRegistryResolver,
        extensionFactory: _extensionFactory,
        platform: _platform,
        logger: _logger,
      );
    });
  }

  /// Spawns a session on the specified server.
  ///
  /// Delegates to the per-server [AgentRuntime].
  Future<AgentSession> spawn({
    required String serverId,
    required String roomId,
    required String prompt,
    String? threadId,
    Duration? timeout,
    bool ephemeral = true,
    bool autoDispose = false,
  }) {
    return runtimeFor(serverId).spawn(
      roomId: roomId,
      prompt: prompt,
      threadId: threadId,
      timeout: timeout,
      ephemeral: ephemeral,
      autoDispose: autoDispose,
    );
  }

  /// All active sessions across all servers.
  List<AgentSession> get activeSessions {
    return [for (final runtime in _runtimes.values) ...runtime.activeSessions];
  }

  /// Finds a session by [ThreadKey], routing via `serverId`.
  AgentSession? getSession(ThreadKey key) {
    final runtime = _runtimes[key.serverId];
    return runtime?.getSession(key);
  }

  /// Waits for all given sessions to complete.
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

  /// Cancels all active sessions across all servers.
  Future<void> cancelAll() async {
    for (final runtime in _runtimes.values) {
      await runtime.cancelAll();
    }
  }

  /// Disposes all per-server runtimes. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final runtime in _runtimes.values) {
      await runtime.dispose();
    }
    _runtimes.clear();
  }

  void _guardNotDisposed() {
    if (_disposed) {
      throw StateError('MultiServerRuntime has been disposed');
    }
  }
}
