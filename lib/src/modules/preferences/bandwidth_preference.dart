import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.bandwidth_preference');

/// The device-wide low bandwidth mode, and the SSE delivery profile it asks
/// each server's runs for.
///
/// On asks each server for its profile whose strategy is `message`, by name,
/// so each reply arrives once complete. Off — the default, and what a failed
/// read leaves — asks for nothing, so the server's own default applies.
///
/// Storage is best-effort: a failure is logged and never thrown, because a
/// missing preference must not stop the app starting or a run being sent.
/// The value is not sensitive, so it lives in shared_preferences.
class BandwidthPreference {
  BandwidthPreference({Future<SharedPreferences> Function()? prefsFactory})
      : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static const _key = 'soliplex_low_bandwidth_mode';

  final Signal<bool> _lowBandwidth = Signal<bool>(false);
  ReadonlySignal<bool> get lowBandwidth => _lowBandwidth;

  Future<void> load() async {
    try {
      final prefs = await _prefsFactory();
      _lowBandwidth.value = prefs.getBool(_key) ?? false;
    } catch (e, st) {
      // A shared_preferences failure carries no user or backend value.
      _logger.error(
        'Failed to read low bandwidth mode; defaulting to off',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Applies [value] at once; returns whether it was saved.
  Future<bool> setLowBandwidth(bool value) async {
    _lowBandwidth.value = value;
    try {
      final prefs = await _prefsFactory();
      // Android reports a failed commit by returning false, not by throwing.
      final saved = await prefs.setBool(_key, value);
      if (!saved) _logger.error('Failed to save low bandwidth mode');
      return saved;
    } catch (e, st) {
      // A shared_preferences failure carries no user or backend value.
      _logger.error(
        'Failed to save low bandwidth mode',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// What each server offers this setting, by server id, as last looked up.
  ReadonlySignal<Map<String, ProfileLookup>> get profileLookups =>
      _profileLookups;
  final Signal<Map<String, ProfileLookup>> _profileLookups = Signal(const {});

  /// The lookup each server's runs reuse; one that could not check is
  /// dropped, so the next turn asks again.
  final Map<String, Future<ProfileLookup>> _lookups = {};

  /// The `forwardedProps` this setting asks of [connection]'s server.
  ///
  /// Off asks nothing. On names the server's `message` profile, looked up on
  /// the first turn that needs it and shared by every runtime built for that
  /// server; with no such profile, or no answer, it sends nothing.
  ForwardedPropsResolver forwardedPropsFor(ServerConnection connection) =>
      () async {
        if (!_lowBandwidth.value) return const {};
        final lookup =
            await (_lookups[connection.serverId] ?? _lookUp(connection));
        return lookup is ProfileOffered
            ? {'agui_sse_delivery': lookup.name}
            : const {};
      };

  /// Looks up each of [connections] again, replacing what is known of it.
  Future<void> checkServers(Iterable<ServerConnection> connections) =>
      Future.wait([for (final connection in connections) _lookUp(connection)]);

  Future<ProfileLookup> _lookUp(ServerConnection connection) {
    final serverId = connection.serverId;
    final lookup = _fetch(connection);
    _lookups[serverId] = lookup;
    _publish(serverId, const ProfileChecking());
    return lookup.then((result) {
      // A lookup started since supersedes this one, answered or not.
      if (!identical(_lookups[serverId], lookup)) return result;
      if (result is ProfileCouldNotCheck) _lookups.remove(serverId);
      _publish(serverId, result);
      return result;
    });
  }

  void _publish(String serverId, ProfileLookup lookup) =>
      _profileLookups.value = {..._profileLookups.value, serverId: lookup};

  Future<ProfileLookup> _fetch(ServerConnection connection) async {
    final serverId = connection.serverId;
    try {
      final name = _messageProfile(
        await connection.api.getSseDeliveryProfiles(),
        serverId,
      );
      if (name == null) {
        _logUnsupported(serverId);
        return const ProfileNotOffered();
      }
      return ProfileOffered(name);
    } on NotFoundException {
      // An installation older than delivery profiles has none to offer, and
      // asking again would cost a request on every message.
      _logUnsupported(serverId);
      return const ProfileNotOffered();
    } catch (e, st) {
      // The request carries no user input — a fixed path, no body — so a
      // [NetworkException]'s host and OS error are forwarded whole; anything
      // else can carry the response it failed on, so only its shape is kept.
      _logger.warning(
        'Could not look up SSE delivery profiles; sending none',
        error: e is NetworkException ? e : null,
        attributes: {
          'serverId': serverId,
          if (e is ApiException) 'statusCode': e.statusCode,
          if (e is! NetworkException) 'failure': describeFailure(e),
        },
        stackTrace: st,
      );
      return const ProfileCouldNotCheck();
    }
  }

  /// Records that a server cannot honour the mode, once per lookup. At
  /// `warning` because the release log floor drops anything lower, and this
  /// is the only trace of why the setting has no effect there.
  void _logUnsupported(String serverId) => _logger.warning(
        'Low bandwidth mode is on, but the server offers no message delivery '
        "profile; it uses the server's default delivery",
        attributes: {'serverId': serverId},
      );

  String? _messageProfile(List<SseDeliveryProfile> profiles, String serverId) {
    final names = [
      for (final p in profiles)
        if (p.strategy == 'message') p.name,
    ];
    if (names.length > 1) {
      _logger.warning(
        'Server declares more than one message delivery profile; '
        'using the first',
        attributes: {'serverId': serverId, 'count': names.length},
      );
    }
    return names.firstOrNull;
  }
}

/// What a server offers low bandwidth mode, as last looked up.
sealed class ProfileLookup {
  const ProfileLookup();
}

/// A lookup is in flight.
final class ProfileChecking extends ProfileLookup {
  const ProfileChecking();
}

/// The server's profile whose strategy is `message`, by [name].
final class ProfileOffered extends ProfileLookup {
  const ProfileOffered(this.name);

  final String name;
}

/// The server declares no `message` profile, or no profiles at all.
final class ProfileNotOffered extends ProfileLookup {
  const ProfileNotOffered();
}

/// The lookup failed, so what the server offers is unknown.
final class ProfileCouldNotCheck extends ProfileLookup {
  const ProfileCouldNotCheck();
}
