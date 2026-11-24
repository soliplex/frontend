import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show
        ApiException,
        AuthException,
        MalformedResponseException,
        NotFoundException,
        PermissionDeniedException,
        RoomConfigsReloaded;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';
import 'lobby_state.dart' show ApiResolver;

final Logger _logger = LogManager.instance.getLogger('soliplex.room_reloads');

/// How an administrator's request to reload a server's room configs ended.
sealed class RoomReloadOutcome {
  const RoomReloadOutcome();
}

/// The server reloaded its room configs; [delta] names the rooms it touched.
final class RoomsReloaded extends RoomReloadOutcome {
  const RoomsReloaded(this.delta);
  final RoomConfigsReloaded delta;
}

/// The server runs several workers and cannot reload in place (409); it has
/// to be restarted to pick up room changes.
final class RoomReloadNeedsRestart extends RoomReloadOutcome {
  const RoomReloadNeedsRestart();
}

/// The server refused the reload (403), which this endpoint answers when the
/// user is not an administrator.
final class RoomReloadRefused extends RoomReloadOutcome {
  const RoomReloadRefused();
}

/// The server answered 401; the session is marked expired, so the server's
/// row offers to sign in again.
final class RoomReloadSignedOut extends RoomReloadOutcome {
  const RoomReloadSignedOut();
}

/// The reload endpoint answered 404, so the server cannot reload in place;
/// only a restart picks up room changes.
final class RoomReloadUnsupported extends RoomReloadOutcome {
  const RoomReloadUnsupported();
}

/// The server's reply could not be read. The request reached it, so the
/// reload may have happened. The failure is logged.
final class RoomReloadUnreadable extends RoomReloadOutcome {
  const RoomReloadUnreadable();
}

/// The reload could not be confirmed (a network failure, an unexpected
/// status, or a client error). The request may have reached the server, or a
/// proxy may have given up while the server carried on, so the reload may
/// have happened. The failure is logged.
final class RoomReloadFailed extends RoomReloadOutcome {
  const RoomReloadFailed();
}

/// Reloads servers' room configs, one request per server at a time.
///
/// Outlives the lobby screen, which is rebuilt each time the user comes back
/// from a room: a reload started before leaving still reports its outcome,
/// still holds off a second request, and still refreshes the lobby that is
/// showing when it ends.
class RoomReloads {
  RoomReloads({
    required ServerEntry? Function(String serverId) entryResolver,
    ApiResolver? apiResolver,
  })  : _entryResolver = entryResolver,
        _apiResolver = apiResolver ?? ((entry) => entry.connection.api);

  final ServerEntry? Function(String serverId) _entryResolver;
  final ApiResolver _apiResolver;

  final Map<String, Future<RoomReloadOutcome>> _inFlight = {};
  final Set<void Function(String serverId)> _listeners = {};

  final Signal<Set<String>> _reloading = Signal<Set<String>>({});

  /// Servers whose room configs are being reloaded, so the control can show
  /// it is busy.
  ReadonlySignal<Set<String>> get reloading => _reloading;

  /// Calls [onRoomsChanged] with a server's id when a reload may have changed
  /// its rooms: it succeeded, or it ended without saying it did not happen
  /// ([RoomReloadUnreadable], [RoomReloadFailed]). Returns the function that
  /// stops the calls.
  void Function() listen(void Function(String serverId) onRoomsChanged) {
    _listeners.add(onRoomsChanged);
    return () => _listeners.remove(onRoomsChanged);
  }

  /// Asks [serverId] to reload its room configs from disk.
  ///
  /// Administrators only; the server enforces that. While a reload for
  /// [serverId] is in flight, a second call sends nothing and answers the
  /// same outcome as the first.
  Future<RoomReloadOutcome> reload(String serverId) {
    final entry = _entryResolver(serverId);
    if (entry == null) {
      throw StateError('No server entry for "$serverId"');
    }
    return _inFlight[serverId] ??= _reload(serverId, entry);
  }

  Future<RoomReloadOutcome> _reload(String serverId, ServerEntry entry) async {
    _reloading.value = {..._reloading.value, serverId};
    try {
      final outcome = await _request(serverId, entry);
      final mayHaveChangedRooms = switch (outcome) {
        RoomsReloaded() || RoomReloadUnreadable() || RoomReloadFailed() => true,
        RoomReloadNeedsRestart() ||
        RoomReloadRefused() ||
        RoomReloadSignedOut() ||
        RoomReloadUnsupported() =>
          false,
      };
      if (mayHaveChangedRooms) _notify(serverId);
      return outcome;
    } finally {
      _inFlight.remove(serverId);
      _reloading.value = {..._reloading.value}..remove(serverId);
    }
  }

  /// Tells each listener, so one that throws neither hides the reload's
  /// outcome from the user nor keeps the others from hearing of it.
  void _notify(String serverId) {
    for (final listener in [..._listeners]) {
      try {
        listener(serverId);
      } catch (e, st) {
        // A listener's failure can carry whatever its closure reaches, so only
        // its shape is logged.
        _logger.error(
          'A room reload listener failed',
          stackTrace: st,
          attributes: {'serverId': serverId, 'failure': describeFailure(e)},
        );
      }
    }
  }

  Future<RoomReloadOutcome> _request(String serverId, ServerEntry entry) async {
    final RoomConfigsReloaded delta;
    try {
      delta = await _apiResolver(entry).reloadRoomConfigs();
    } on AuthException catch (e) {
      _logger.warning(
        'The room reload was not authenticated',
        attributes: {'serverId': serverId, 'serverMessage': e.serverMessage},
      );
      // Same funnel as a rooms fetch: the lobby turns the expiry into the
      // row's inline "sign in again".
      entry.auth.markSessionExpired();
      return const RoomReloadSignedOut();
    } on PermissionDeniedException catch (e) {
      _logger.warning(
        'The room reload was refused',
        attributes: {'serverId': serverId, 'serverMessage': e.serverMessage},
      );
      return const RoomReloadRefused();
    } on NotFoundException catch (e) {
      _logger.warning(
        'The room reload endpoint answered 404',
        attributes: {
          'serverId': serverId,
          'resource': e.resource,
          'serverMessage': e.serverMessage,
        },
      );
      return const RoomReloadUnsupported();
    } catch (e, st) {
      if (e is ApiException && e.statusCode == 409) {
        _logger.warning(
          'The server cannot reload rooms in place; it runs several workers',
          attributes: {'serverId': serverId, 'serverMessage': e.serverMessage},
        );
        return const RoomReloadNeedsRestart();
      }
      // The request carries no body and no user input, and the response is
      // three lists of room ids. What reaches here is a NetworkException's
      // platform error text, an ApiException's status (any other than 409)
      // and the server's own reason, a MalformedResponseException's
      // description of the reply's shape, a CancelledException's fixed reason
      // (a closed client), or an Error from the client (fixed text, a
      // TypeError's type names); none is a credential.
      _logger.error(
        'Failed to reload room configs',
        error: e,
        stackTrace: st,
        attributes: {'serverId': serverId},
      );
      return e is MalformedResponseException
          ? const RoomReloadUnreadable()
          : const RoomReloadFailed();
    }
    _logger.info(
      'Reloaded room configs',
      attributes: {
        'serverId': serverId,
        'added': delta.added,
        'removed': delta.removed,
        'changed': delta.changed,
      },
    );
    return RoomsReloaded(delta);
  }
}
