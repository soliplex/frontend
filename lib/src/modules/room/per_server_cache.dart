import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.per_server_cache');

/// Values kept per server and [K], for as long as the server stays connected
/// under one user.
///
/// A value is created on first use and disposed when its server leaves
/// [servers] (the user removed it), when [evictServer] drops the server (a
/// different user signed in on it), or when the cache is disposed.
class PerServerCache<K, V> {
  PerServerCache({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    required void Function(V value) disposeValue,
    required String what,
  })  : _disposeValue = disposeValue,
        _what = what {
    _unsubscribe = servers.subscribe((snapshot) {
      _evictWhere((serverId) => !snapshot.containsKey(serverId));
    });
  }

  final void Function(V value) _disposeValue;

  /// What a value is, for the record of a teardown that failed.
  final String _what;

  final Map<(String, K), V> _values = {};
  late final void Function() _unsubscribe;
  bool _isDisposed = false;

  /// The value for [serverId] and [key], created by [create] if there is
  /// none. Throws [StateError] once the cache is disposed.
  ///
  /// A value for a server absent from `servers` is never evicted by its
  /// removal, so callers pass a server that is still connected.
  V putIfAbsent(String serverId, K key, V Function() create) {
    if (_isDisposed) throw StateError('PerServerCache has been disposed');
    return _values.putIfAbsent((serverId, key), create);
  }

  /// Disposes and drops every value of [serverId].
  void evictServer(String serverId) => _evictWhere((id) => id == serverId);

  /// Drops each matching value before disposing it: disposal runs real
  /// teardown that can throw, and eviction runs synchronously inside a signal
  /// write (server removal, or a user switch mid-login), where an escape
  /// would unwind the caller and strand the remaining evictions. Removing
  /// first keeps a throw from leaving a disposed value referenced.
  void _evictWhere(bool Function(String serverId) shouldEvict) {
    if (_isDisposed) return;
    final dead = _values.entries.where((e) => shouldEvict(e.key.$1)).toList();
    for (final entry in dead) {
      _values.remove(entry.key);
      _disposeQuietly(entry.key, entry.value);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
    for (final entry in _values.entries) {
      _disposeQuietly(entry.key, entry.value);
    }
    _values.clear();
  }

  /// Disposes [value], logging any throw so one value's failing teardown
  /// can't strand the rest.
  void _disposeQuietly((String, K) key, V value) {
    try {
      _disposeValue(value);
    } on Object catch (error, stackTrace) {
      // Any value's teardown, so nothing vouches for what its error carries.
      _logger.error(
        'Failed to dispose $_what',
        stackTrace: stackTrace,
        attributes: {
          'serverId': key.$1,
          'key': '${key.$2}',
          'failure': describeFailure(error),
        },
      );
    }
  }
}
