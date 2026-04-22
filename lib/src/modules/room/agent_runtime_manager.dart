import 'package:soliplex_agent/soliplex_agent.dart';

/// Factory and cache for [AgentRuntime] instances, keyed by server ID.
///
/// Create one manager per app session and pass it to modules that need to
/// spawn agent sessions. Calling [dispose] shuts down all cached runtimes.
class AgentRuntimeManager {
  AgentRuntimeManager({
    required PlatformConstraints platform,
    required Future<ToolRegistry> Function(String roomId) toolRegistryResolver,
    required Logger logger,
    SessionExtensionFactory? extensionFactory,
  })  : _platform = platform,
        _toolRegistryResolver = toolRegistryResolver,
        _extensionFactory = extensionFactory,
        _logger = logger;

  final PlatformConstraints _platform;
  final Future<ToolRegistry> Function(String roomId) _toolRegistryResolver;
  final SessionExtensionFactory? _extensionFactory;
  final Logger _logger;
  final Map<String, ({ServerConnection connection, AgentRuntime runtime})>
      _cache = {};
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

  /// Disposes all cached runtimes and clears the cache.
  Future<void> dispose() async {
    _isDisposed = true;
    final entries = _cache.values.toList();
    _cache.clear();
    for (final entry in entries) {
      try {
        await entry.runtime.dispose();
      } on Object catch (e) {
        _logger.warning(
            'Failed to dispose runtime ${entry.connection.serverId}: $e');
      }
    }
  }
}
