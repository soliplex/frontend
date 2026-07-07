import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';

import '../auth/server_entry.dart';

/// Factory and cache for [AgentRuntime] instances, keyed by server ID.
///
/// Create one manager per app session and pass it to modules that need to
/// spawn agent sessions. Calling [dispose] shuts down all cached runtimes.
class AgentRuntimeManager {
  /// [servers] wires the removal-eviction path: when a server disappears from
  /// the signal, its cached runtime is disposed and dropped so it doesn't
  /// linger until the whole manager is disposed. Eviction is driven entirely by
  /// the signal, so a signal that never changes simply never evicts.
  AgentRuntimeManager({
    required PlatformConstraints platform,
    required Future<ToolRegistry> Function(String roomId) toolRegistryResolver,
    required Logger logger,
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    SessionExtensionFactory? extensionFactory,
  })  : _platform = platform,
        _toolRegistryResolver = toolRegistryResolver,
        _extensionFactory = extensionFactory,
        _logger = logger {
    _unsubscribe = servers.subscribe(_evictRemoved);
  }

  final PlatformConstraints _platform;
  final Future<ToolRegistry> Function(String roomId) _toolRegistryResolver;
  final SessionExtensionFactory? _extensionFactory;
  final Logger _logger;
  final Map<String, ({ServerConnection connection, AgentRuntime runtime})>
      _cache = {};
  late final void Function() _unsubscribe;
  bool _isDisposed = false;

  /// Resolves the [ToolRegistry] for a given room ID.
  Future<ToolRegistry> Function(String roomId) get toolRegistryResolver =>
      _toolRegistryResolver;

  /// Returns the cached [AgentRuntime] for [connection], creating it if
  /// needed.
  ///
  /// If the same server ID appears with a different [ServerConnection]
  /// (e.g., after server removal and re-addition), the stale runtime is
  /// disposed and replaced.
  AgentRuntime getRuntime(ServerConnection connection) {
    if (_isDisposed) {
      throw StateError('AgentRuntimeManager has been disposed');
    }
    final existing = _cache[connection.serverId];
    if (existing != null && identical(existing.connection, connection)) {
      return existing.runtime;
    }
    existing?.runtime.dispose();
    final runtime = _createRuntime(connection);
    _cache[connection.serverId] = (connection: connection, runtime: runtime);
    return runtime;
  }

  AgentRuntime _createRuntime(ServerConnection connection) {
    return AgentRuntime(
      connection: connection,
      toolRegistryResolver: _toolRegistryResolver,
      platform: _platform,
      extensionFactory: _extensionFactory,
      logger: _logger,
    );
  }

  /// Disposes and drops the cached runtime for every server no longer present
  /// in [snapshot], so a removed server's runtime doesn't linger until the
  /// whole manager is disposed. Disposal is fire-and-forget: it runs teardown
  /// that can throw, and this eviction must not strand the other disposals or
  /// propagate, so a throw is logged.
  void _evictRemoved(Map<String, ServerEntry> snapshot) {
    if (_isDisposed) return;
    final liveIds = snapshot.keys.toSet();
    final dead = _cache.entries.where((e) => !liveIds.contains(e.key)).toList();
    for (final entry in dead) {
      _cache.remove(entry.key);
      unawaited(_disposeRuntime(entry.key, entry.value.runtime));
    }
  }

  Future<void> _disposeRuntime(String serverId, AgentRuntime runtime) async {
    try {
      await runtime.dispose();
    } on Object catch (e, st) {
      _logger.error(
        'Failed to dispose runtime $serverId',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Disposes all cached runtimes and clears the cache. Idempotent.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
    final entries = _cache.values.toList();
    _cache.clear();
    for (final entry in entries) {
      await _disposeRuntime(entry.connection.serverId, entry.runtime);
    }
  }
}
