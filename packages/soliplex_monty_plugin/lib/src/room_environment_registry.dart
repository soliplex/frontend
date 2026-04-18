import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';

/// Manages a cache of [ScriptEnvironment] instances shared across sessions
/// in the same room.
///
/// Use this to persist Python state (variables, imports) across multiple
/// agent turns in a single room.
class RoomEnvironmentRegistry {
  final Map<String, ScriptEnvironment> _cache = {};

  /// Returns an existing environment for the room in [ctx], or creates
  /// a new one using [factory].
  Future<ScriptEnvironment> getOrCreate(
    SessionContext ctx,
    ScriptEnvironmentFactory factory,
  ) async {
    final key = '${ctx.serverId}:${ctx.roomId}';
    final existing = _cache[key];
    if (existing != null) return existing;

    final env = await factory(ctx);
    _cache[key] = env;
    return env;
  }

  /// Disposes all cached environments and clears the cache.
  void dispose() {
    for (final env in _cache.values) {
      env.dispose();
    }
    _cache.clear();
  }
}

/// Wraps a [ScriptEnvironmentFactory] to use a [RoomEnvironmentRegistry]
/// for sharing environments across sessions in the same room.
SessionExtensionFactory toRoomSharedFactory(
  RoomEnvironmentRegistry registry,
  ScriptEnvironmentFactory factory,
) {
  return (ctx) async {
    final env = await registry.getOrCreate(ctx, factory);
    return [SharedScriptEnvironmentProxy(env)];
  };
}
