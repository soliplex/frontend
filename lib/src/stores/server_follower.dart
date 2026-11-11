import 'package:soliplex_agent/soliplex_agent.dart' show ReadonlySignal;

import '../modules/auth/auth_tokens.dart' show ExpiredSession;
import '../modules/auth/server_entry.dart';

/// Follows a selected server, and whether it can currently serve requests.
///
/// For state that loads one server's data and has to keep up with the
/// lobby's selection: a different server, a sign-out or session expiry, a
/// sign-in again, the server's removal. Each is reported once, as a
/// transition.
///
/// A `null` selection is ignored rather than reported. The lobby emits
/// `null` while it restores its persisted selection, and a holder that
/// cleared on it would throw away what it still holds for the server about
/// to be re-selected.
class ServerFollower {
  ServerFollower({
    required ReadonlySignal<String?> selection,
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    required void Function(ServerEntry entry) onServer,
    required void Function() onConnected,
    required void Function({required bool expired}) onDisconnected,
    required void Function() onRemoved,
  })  : _selection = selection,
        _servers = servers,
        _onServer = onServer,
        _onConnected = onConnected,
        _onDisconnected = onDisconnected,
        _onRemoved = onRemoved {
    _unsubscribeSelection = selection.subscribe((_) => _sync());
    _unsubscribeServers = servers.subscribe((_) => _sync());
  }

  final ReadonlySignal<String?> _selection;
  final ReadonlySignal<Map<String, ServerEntry>> _servers;
  final void Function(ServerEntry entry) _onServer;
  final void Function() _onConnected;
  final void Function({required bool expired}) _onDisconnected;
  final void Function() _onRemoved;

  late final void Function() _unsubscribeSelection;
  late final void Function() _unsubscribeServers;
  void Function()? _unsubscribeSession;

  /// The server being followed, or `null` before the first selection.
  ServerEntry? _entry;

  /// Whether [_entry] could serve requests when last checked.
  bool _connected = false;

  void _sync() {
    final servers = _servers.value;
    final followed = _entry;

    if (followed != null && !servers.containsKey(followed.serverId)) {
      _follow(null);
      _onRemoved();
    }

    final id = _selection.value;
    if (id == null || id == _entry?.serverId) return;

    // A selection the server list doesn't know yet is left alone: the
    // list catches up, and this runs again when it does.
    final entry = servers[id];
    if (entry == null) return;

    _follow(entry);
    _onServer(entry);
  }

  void _follow(ServerEntry? entry) {
    _unsubscribeSession?.call();
    _unsubscribeSession = null;
    _entry = entry;
    if (entry == null) return;

    // Seeded before subscribing: the subscription fires at once with the
    // current session, which must read as no change.
    _connected = entry.isConnected;
    _unsubscribeSession = entry.auth.session.subscribe((session) {
      final connected = entry.isConnected;
      if (connected == _connected) return;
      _connected = connected;
      if (connected) {
        _onConnected();
      } else {
        _onDisconnected(expired: session is ExpiredSession);
      }
    });
  }

  void dispose() {
    _unsubscribeSelection();
    _unsubscribeServers();
    _unsubscribeSession?.call();
    _unsubscribeSession = null;
  }
}
