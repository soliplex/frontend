import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/routes.dart';
import '../../core/uri_decoding.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.pre_auth_state');

/// Whether [value] is an in-app path a sign-in may return to (open-redirect
/// defense): it starts with one `/`, its path and query decode, and it is not
/// the sign-in callback. One that doesn't decode would throw when the callback
/// navigates to it; returning to the callback would run it again on the same
/// link. The callback check ignores any trailing slashes: go_router strips
/// one before matching, so `/auth/callback/` reaches the callback too.
bool isSafeReturnTo(String value) {
  if (!value.startsWith('/') || value.startsWith('//')) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      isDecodable(uri) &&
      uri.path.replaceFirst(_trailingSlashes, '') != AppRoutes.authCallback;
}

final _trailingSlashes = RegExp(r'/+$');

/// State saved before OAuth redirect.
///
/// On web, the callback URL only includes tokens, not provider metadata.
/// We save this before redirect and retrieve it after callback to know
/// which server and provider the tokens belong to.
///
/// On Android, the OS may kill the app while the user is in the system
/// browser. This state enables recovery when the app restarts via deep link.
///
/// Includes [createdAt] for expiry — states older than [maxAge] are rejected.
@immutable
class PreAuthState {
  PreAuthState({
    required this.serverUrl,
    required this.providerId,
    required this.discoveryUrl,
    required this.clientId,
    required this.createdAt,
    this.frontendReturnTo,
    this.serverName,
    this.serverDescription,
  }) {
    if (frontendReturnTo != null && !isSafeReturnTo(frontendReturnTo!)) {
      throw ArgumentError.value(
        frontendReturnTo,
        'frontendReturnTo',
        'must be an in-app path starting with "/", not "//", that decodes '
            'and is not the sign-in callback',
      );
    }
  }

  factory PreAuthState.fromJson(Map<String, dynamic> json) {
    return PreAuthState(
      serverUrl: Uri.parse(json['serverUrl'] as String),
      providerId: json['providerId'] as String,
      discoveryUrl: json['discoveryUrl'] as String,
      clientId: json['clientId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      frontendReturnTo: json['frontendReturnTo'] as String?,
      serverName: json['serverName'] as String?,
      serverDescription: json['serverDescription'] as String?,
    );
  }

  final Uri serverUrl;
  final String providerId;
  final String discoveryUrl;
  final String clientId;
  final DateTime createdAt;

  /// In-app route the user should be returned to after a successful
  /// re-auth (e.g. `/room/<alias>/<roomId>`). Null when there's no
  /// specific return target; the callback falls back to the lobby.
  ///
  /// The constructor throws [ArgumentError] for a value [isSafeReturnTo]
  /// rejects, before it can be persisted, so a stored one that no longer
  /// passes makes [PreAuthStateStorage.load] clear the state.
  final String? frontendReturnTo;

  /// Cached human-readable server name probed before redirect, carried across
  /// the OAuth roundtrip so the web callback can persist it. Null when the
  /// server provides none.
  final String? serverName;

  /// Cached brief server description, carried across the OAuth roundtrip.
  /// Null when the server provides none.
  final String? serverDescription;

  /// Covers typical OIDC roundtrips: password reset, MFA prompts,
  /// email magic links.
  static const maxAge = Duration(minutes: 30);

  bool isExpired({DateTime? now}) {
    final currentTime = now ?? DateTime.timestamp();
    return currentTime.difference(createdAt) > maxAge;
  }

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl.toString(),
        'providerId': providerId,
        'discoveryUrl': discoveryUrl,
        'clientId': clientId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (frontendReturnTo != null) 'frontendReturnTo': frontendReturnTo,
        if (serverName != null) 'serverName': serverName,
        if (serverDescription != null) 'serverDescription': serverDescription,
      };

  @override
  bool operator ==(Object other) =>
      other is PreAuthState &&
      other.serverUrl == serverUrl &&
      other.providerId == providerId &&
      other.discoveryUrl == discoveryUrl &&
      other.clientId == clientId &&
      other.createdAt == createdAt &&
      other.frontendReturnTo == frontendReturnTo &&
      other.serverName == serverName &&
      other.serverDescription == serverDescription;

  @override
  int get hashCode => Object.hash(
        serverUrl,
        providerId,
        discoveryUrl,
        clientId,
        createdAt,
        frontendReturnTo,
        serverName,
        serverDescription,
      );

  @override
  String toString() =>
      'PreAuthState(serverUrl: $serverUrl, providerId: $providerId)';
}

/// Keeps the [PreAuthState] of the sign-in in flight, so the callback can
/// tell which server and provider its tokens belong to.
abstract interface class PreAuthStateStorage {
  Future<void> save(PreAuthState state);

  /// The saved state, or `null` when there is none, it has expired, or it
  /// can't be read; an expired or unreadable state is cleared.
  Future<PreAuthState?> load();

  Future<void> clear();
}

extension BestEffortClear on PreAuthStateStorage {
  /// Clears the saved [PreAuthState], logging a failure instead of
  /// throwing. It runs inside catch blocks, and after the IdP has returned
  /// tokens, where a throw would leave the spinner up or discard a completed
  /// sign-in.
  Future<void> clearBestEffort() async {
    try {
      await clear();
    } catch (e, st) {
      // `error: e` is safe for [LocalPreAuthStateStorage]: its key is a
      // constant and no stored value reaches it; at most a PlatformException
      // or a web storage SecurityError. Another implementation's exception
      // text is its own to keep free of secrets.
      _logger.warning(
        'Failed to clear the pre-auth state',
        error: e,
        stackTrace: st,
      );
    }
  }
}

/// Stores and retrieves [PreAuthState] via SharedPreferences.
class LocalPreAuthStateStorage implements PreAuthStateStorage {
  const LocalPreAuthStateStorage();

  static const storageKey = 'soliplex_pre_auth_state';

  @override
  Future<void> save(PreAuthState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(state.toJson()));
  }

  @override
  Future<PreAuthState?> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return null;
      final state = PreAuthState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (state.isExpired(now: now)) {
        await clearBestEffort();
        return null;
      }
      return state;
    } catch (e, st) {
      // Warning, not info: the state is cleared right after, so a sign-in
      // already in flight fails at the callback, which finds no state to say
      // which server and provider its tokens belong to.
      _logger.warning(
        'Failed to load pre-auth state',
        attributes: {'failure': describeFailure(e)},
        stackTrace: st,
      );
      await clearBestEffort();
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
