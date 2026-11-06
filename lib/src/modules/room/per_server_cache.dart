import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.per_server_cache');

/// Values kept per server entry and [K], for as long as `servers` lists the
/// entry and no different user signs in on its server.
///
/// A value belongs to the [ServerEntry] it was made for, and is served to
/// that entry alone: an entry's connection is not another's, even for one
/// server. It is disposed when `servers` changes and stops listing its entry
/// (the user removed the server, or removed and re-added it), when
/// [evictServer] drops its server (a different user signed in), or when the
/// cache is disposed. So a value made for an entry already gone lasts until
/// one of those happens.
class PerServerCache<K, V> {
  PerServerCache({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    required void Function(V value) disposeValue,
  }) : _disposeValue = disposeValue {
    _unsubscribe = servers.subscribe((listed) {
      _evictWhere((entry) => !identical(listed[entry.serverId], entry));
    });
  }

  final void Function(V value) _disposeValue;

  /// By entry identity: two entries of one server are two keys.
  final _values = Map<ServerEntry, Map<K, V>>.identity();
  late final void Function() _unsubscribe;
  bool _isDisposed = false;

  /// The value for [entry] and [key], created by [create] if there is none.
  /// Throws [StateError] once the cache is disposed.
  V putIfAbsent(ServerEntry entry, K key, V Function() create) {
    if (_isDisposed) throw StateError('PerServerCache has been disposed');
    return _values.putIfAbsent(entry, () => {}).putIfAbsent(key, create);
  }

  /// Disposes and drops every value of [serverId].
  void evictServer(String serverId) =>
      _evictWhere((entry) => entry.serverId == serverId);

  /// Drops each matching entry's values from the map before disposing them,
  /// so a disposed value is never served again.
  void _evictWhere(bool Function(ServerEntry entry) evict) {
    if (_isDisposed) return;
    final dead = _values.keys.where(evict).toList();
    for (final entry in dead) {
      _disposeAll(entry, _values.remove(entry)!);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
    for (final MapEntry(key: entry, value: values) in _values.entries) {
      _disposeAll(entry, values);
    }
    _values.clear();
  }

  /// Disposes each of [values], logging any throw: eviction runs
  /// synchronously inside a signal write (server removal, or a user switch
  /// mid-login), where an escape would unwind the caller and leave the
  /// remaining values undisposed.
  void _disposeAll(ServerEntry entry, Map<K, V> values) {
    for (final MapEntry(:key, :value) in values.entries) {
      try {
        _disposeValue(value);
      } on Object catch (error, stackTrace) {
        // Any value's teardown, so nothing vouches for what its error
        // carries.
        _logger.error(
          'Failed to dispose $V',
          stackTrace: stackTrace,
          attributes: {
            'serverId': entry.serverId,
            'key': '$key',
            'failure': describeFailure(error),
          },
        );
      }
    }
  }
}
