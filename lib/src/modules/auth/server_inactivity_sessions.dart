import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';

import '../../core/inactivity/inactivity_sessions.dart';
import 'auth_tokens.dart';
import 'inactivity_logout_storage.dart';
import 'server_entry.dart';

/// [InactivitySessions] over the [ServerManager]'s servers: a session is
/// active when its entry's auth holds an [ActiveSession].
class ServerInactivitySessions implements InactivitySessions {
  ServerInactivitySessions({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    InactivityLogoutFlagStorage? inactivityLogoutFlags,
  })  : _servers = servers,
        _inactivityLogoutFlags = inactivityLogoutFlags;

  final ReadonlySignal<Map<String, ServerEntry>> _servers;
  final InactivityLogoutFlagStorage? _inactivityLogoutFlags;

  @override
  late final ReadonlySignal<bool> hasActiveSession = computed(
    () =>
        _servers.value.values.any((e) => e.auth.session.value is ActiveSession),
  );

  @override
  void signOutForInactivity() {
    final active = _servers.value.values
        .where((e) => e.auth.session.value is ActiveSession)
        .toList();
    for (final entry in active) {
      // Persist the flag best-effort (fire-and-forget); logout proceeds
      // regardless. The storage layer swallows and logs its own failures,
      // so the unawaited future never rejects.
      unawaited(_inactivityLogoutFlags?.mark(entry.serverId) ?? Future.value());
      entry.auth.logout();
    }
  }
}
