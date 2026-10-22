import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' show batch, effect;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';

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

  /// What each server offers this setting, by server id, as last answered.
  /// A re-check leaves the answer in place until its own arrives.
  ReadonlySignal<Map<String, ProfileLookup>> get profileLookups =>
      _profileLookups;
  final Signal<Map<String, ProfileLookup>> _profileLookups = Signal(const {});

  /// The servers with a lookup in flight.
  ReadonlySignal<Set<String>> get checkingServers => _checkingServers;
  final Signal<Set<String>> _checkingServers = Signal(const {});

  /// The lookup each server last started, so an older one answering late
  /// cannot overwrite a newer one.
  final Map<String, Future<ProfileLookup>> _lookups = {};

  /// The `forwardedProps` this setting asks of [connection]'s server.
  ///
  /// Off asks nothing. On names the server's `message` profile once an answer
  /// has offered one, never waiting for it: with no such profile, or no
  /// answer yet, the turn sends nothing, and a turn that finds no answer, or
  /// one that could not check, looks the server up for the next turn unless
  /// a lookup is already in flight.
  ForwardedPropsResolver forwardedPropsFor(ServerConnection connection) => () {
        if (!_lowBandwidth.value) return const {};
        final serverId = connection.serverId;
        final lookup = _profileLookups.value[serverId];
        if (lookup is ProfileOffered) return {'agui_sse_delivery': lookup.name};
        final unanswered = lookup == null || lookup is ProfileCouldNotCheck;
        if (unanswered && !_checkingServers.value.contains(serverId)) {
          unawaited(_lookUp(connection));
        }
        return const {};
      };

  /// While the mode is on, looks [servers] up so a first message seldom goes
  /// out before its server's profile is known: every one of them when the
  /// mode turns on, and, whenever the servers change, each with no answer or
  /// one that could not check. A failed lookup is asked again then or by the
  /// next turn, never on a timer, so an unreachable server is not polled.
  ///
  /// Returns the disposer of the effect that does so.
  void Function() trackServers(
    ReadonlySignal<Map<String, ServerEntry>> servers,
  ) {
    var wasOn = false;
    return effect(() {
      final on = _lowBandwidth.value;
      final entries = servers.value.values;
      final turnedOn = on && !wasOn;
      wasOn = on;
      if (!on) return;
      final answers = _profileLookups.peek();
      final checking = _checkingServers.peek();
      for (final entry in entries) {
        final answer = answers[entry.serverId];
        final unanswered = answer == null || answer is ProfileCouldNotCheck;
        if (turnedOn || (unanswered && !checking.contains(entry.serverId))) {
          unawaited(_lookUp(entry.connection));
        }
      }
    });
  }

  /// Looks up each of [connections] again, replacing what is known of it.
  Future<void> checkServers(Iterable<ServerConnection> connections) =>
      Future.wait([for (final connection in connections) _lookUp(connection)]);

  /// Starts a lookup of [connection]'s server. Its state is read with `peek`
  /// so an effect that starts one does not subscribe to what it writes.
  Future<ProfileLookup> _lookUp(ServerConnection connection) {
    final serverId = connection.serverId;
    final lookup = _fetch(connection);
    _lookups[serverId] = lookup;
    _checkingServers.value = {..._checkingServers.peek(), serverId};
    return lookup.then((result) {
      // A lookup started since supersedes this one, answered or not.
      if (identical(_lookups[serverId], lookup)) {
        batch(() {
          _profileLookups.value = {..._profileLookups.peek(), serverId: result};
          _checkingServers.value = {..._checkingServers.peek()}
            ..remove(serverId);
        });
      }
      return result;
    });
  }

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
  /// `warning` because the release log floor drops anything lower, and the
  /// log is then the only record of why the setting had no effect there.
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

/// What a server offers low bandwidth mode, as last answered.
sealed class ProfileLookup {
  const ProfileLookup();
}

/// The server's profile whose strategy is `message`, by [name].
final class ProfileOffered extends ProfileLookup {
  const ProfileOffered(this.name);

  final String name;
}

/// The server declares no `message` profile, no profiles at all, or has no
/// endpoint that declares them.
final class ProfileNotOffered extends ProfileLookup {
  const ProfileNotOffered();
}

/// The lookup failed, so what the server offers is unknown.
final class ProfileCouldNotCheck extends ProfileLookup {
  const ProfileCouldNotCheck();
}
