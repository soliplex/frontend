import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

/// Persists auth tokens using platform secure storage.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'soliplex_server_';

  String _key(String serverId) => '$_prefix$serverId';

  @override
  Future<void> save(String serverId, PersistedServer data) async {
    await _storage.write(
      key: _key(serverId),
      value: jsonEncode(data.toJson()),
    );
  }

  @override
  Future<void> delete(String serverId) async {
    await _storage.delete(key: _key(serverId));
  }

  @override
  Future<Map<String, PersistedServer>> loadAll() async {
    final all = await _storage.readAll();
    final result = <String, PersistedServer>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_prefix)) continue;
      try {
        final serverId = entry.key.substring(_prefix.length);
        final json = jsonDecode(entry.value) as Map<String, dynamic>;
        result[serverId] = PersistedServer.fromJson(json);
      } catch (e, st) {
        debugPrint('Failed to load stored session ${entry.key}: $e\n$st');
      }
    }
    return result;
  }
}
