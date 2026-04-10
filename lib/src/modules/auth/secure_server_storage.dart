import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_storage.dart';

/// Persists server sessions using platform secure storage.
class SecureServerStorage implements ServerStorage {
  SecureServerStorage({
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
    return deserializeStorageEntries(all, prefix: _prefix);
  }
}

/// Deserializes raw storage entries into [PersistedServer] instances.
///
/// Filters to keys matching [prefix], strips the prefix to recover the
/// server ID, and silently skips entries that fail JSON deserialization.
Map<String, PersistedServer> deserializeStorageEntries(
  Map<String, String> raw, {
  required String prefix,
}) {
  final result = <String, PersistedServer>{};
  for (final entry in raw.entries) {
    if (!entry.key.startsWith(prefix)) continue;
    try {
      final serverId = entry.key.substring(prefix.length);
      final json = jsonDecode(entry.value) as Map<String, dynamic>;
      result[serverId] = PersistedServer.fromJson(json);
    } catch (e, st) {
      debugPrint('Failed to load stored session ${entry.key}: $e\n$st');
    }
  }
  return result;
}
