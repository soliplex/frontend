import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show immutable;
import 'package:shared_preferences/shared_preferences.dart';

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
  const PreAuthState({
    required this.serverUrl,
    required this.providerId,
    required this.discoveryUrl,
    required this.clientId,
    required this.createdAt,
  });

  factory PreAuthState.fromJson(Map<String, dynamic> json) {
    return PreAuthState(
      serverUrl: Uri.parse(json['serverUrl'] as String),
      providerId: json['providerId'] as String,
      discoveryUrl: json['discoveryUrl'] as String,
      clientId: json['clientId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  final Uri serverUrl;
  final String providerId;
  final String discoveryUrl;
  final String clientId;
  final DateTime createdAt;

  static const maxAge = Duration(minutes: 5);

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
  };

  @override
  bool operator ==(Object other) =>
      other is PreAuthState &&
      other.serverUrl == serverUrl &&
      other.providerId == providerId &&
      other.discoveryUrl == discoveryUrl &&
      other.clientId == clientId &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(serverUrl, providerId, discoveryUrl, clientId, createdAt);

  @override
  String toString() =>
      'PreAuthState(serverUrl: $serverUrl, providerId: $providerId)';
}

/// Stores and retrieves [PreAuthState] via SharedPreferences.
abstract final class PreAuthStateStorage {
  static const storageKey = 'soliplex_pre_auth_state';

  static Future<void> save(PreAuthState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(state.toJson()));
  }

  static Future<PreAuthState?> load({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;

    try {
      final state = PreAuthState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (state.isExpired(now: now)) {
        await clear();
        return null;
      }
      return state;
    } catch (e, st) {
      dev.log('Failed to load pre-auth state', error: e, stackTrace: st);
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
