import 'server_entry.dart';

/// The aliases servers go by in routes, kept unique across the server list.
class ServerAliases {
  final Set<String> _inUse = {};

  /// Claims [preferred] when it is free, and otherwise the first free alias
  /// derived from [serverUrl]: its base alias, then `base-2`, `base-3`, ….
  ///
  /// The caller compares the result with [preferred] to tell a collision.
  String claim(Uri serverUrl, {String? preferred}) {
    if (preferred != null && _inUse.add(preferred)) return preferred;
    final base = aliasFromUrl(serverUrl);
    if (_inUse.add(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base-$i';
      if (_inUse.add(candidate)) return candidate;
    }
  }

  /// Frees [alias] for the next server to claim.
  void release(String alias) => _inUse.remove(alias);

  /// Frees every alias.
  void clear() => _inUse.clear();
}
