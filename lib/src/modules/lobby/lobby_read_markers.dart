import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ReadonlySignal, Signal;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/activity_read.dart' show RoomActivityKey;

final Logger _logger =
    LogManager.instance.getLogger('soliplex.lobby_read_markers');

/// Persists per-room "last seen" timestamps so the lobby can mark rooms with
/// newer activity as unread.
///
/// This is a deliberately simple, *client-side* read model: a room is unread
/// when its last-message time is newer than the moment the user last opened
/// it on this device. There is no server-side read state and no count — just
/// a boolean affordance. Read markers are therefore per-device.
///
/// Backed by `shared_preferences` (non-sensitive UI state). Stored as a JSON
/// array of `{s, r, t}` objects (server id, room id, ISO-8601 UTC instant) so
/// ids needn't be escaped into a composite key.
abstract final class LobbyReadMarkerStorage {
  static const _key = 'soliplex_lobby_read_markers';

  // Row field names, shared by load and save so the read/write contract can't
  // drift: a typo in one half alone would silently drop every row.
  static const _fieldServer = 's';
  static const _fieldRoom = 'r';
  static const _fieldTime = 't';

  static Future<Map<RoomActivityKey, DateTime>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};

    final result = <RoomActivityKey, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _logger.warning(
            'Discarding corrupt lobby read markers (not a JSON array)');
        return {};
      }
      var skipped = 0;
      for (final entry in decoded) {
        if (entry is! Map) {
          skipped++;
          continue;
        }
        final s = entry[_fieldServer];
        final r = entry[_fieldRoom];
        final t = entry[_fieldTime];
        if (s is! String || r is! String || t is! String) {
          skipped++;
          continue;
        }
        final at = DateTime.tryParse(t);
        if (at == null) {
          skipped++;
          continue;
        }
        result[(serverId: s, roomId: r)] = at.toUtc();
      }
      // Every row dropped on a non-empty payload is a systemic serialization
      // break, not one stale row, and it silently resets the read model (every
      // room flips to unread). Surface it loudly.
      if (skipped > 0 && result.isEmpty) {
        _logger
            .error('Discarding all $skipped lobby read markers; none parsed');
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed lobby read marker(s)');
      }
    } on FormatException catch (e, st) {
      // Corrupt payload: start fresh rather than wedging the lobby.
      _logger.warning(
        'Discarding corrupt lobby read markers',
        error: e,
        stackTrace: st,
      );
      return {};
    }
    return result;
  }

  static Future<void> save(Map<RoomActivityKey, DateTime> markers) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final entry in markers.entries)
        {
          _fieldServer: entry.key.serverId,
          _fieldRoom: entry.key.roomId,
          _fieldTime: entry.value.toUtc().toIso8601String(),
        },
    ];
    await prefs.setString(_key, jsonEncode(list));
  }
}

/// In-memory, reactive source of truth for per-room read markers, shared by the
/// lobby and the room screen. A marker stamped in one screen is visible to the
/// other immediately, because both watch the same [markers] signal — there is
/// no [LobbyReadMarkerStorage] round-trip to race the screens' mount/dispose
/// ordering (which is what let a just-read room show a stale unread dot in the
/// lobby). Backed by [LobbyReadMarkerStorage] for persistence across launches.
class RoomReadMarkers {
  final Signal<Map<RoomActivityKey, DateTime>> _markers = Signal(const {});
  ReadonlySignal<Map<RoomActivityKey, DateTime>> get markers => _markers;

  bool _loaded = false;

  /// The current markers, for a non-reactive read.
  Map<RoomActivityKey, DateTime> get value => _markers.value;

  /// Loads persisted markers once, merging them under any already stamped
  /// in-memory (an early [markRead] before the disk read returned) so a
  /// just-read room isn't clobbered back to unread by the slower load.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final loaded = await LobbyReadMarkerStorage.load();
      _markers.value = {...loaded, ..._markers.value};
    } catch (error, st) {
      _logger.warning(
        'Failed to load room read markers',
        error: error,
        stackTrace: st,
      );
    }
  }

  /// Stamps [key] read as of [at] and persists. The [markers] update is
  /// synchronous, so a screen watching it reacts with no storage round-trip.
  void markRead(RoomActivityKey key, DateTime at) {
    _markers.value = {..._markers.value, key: at};
    unawaited(
      LobbyReadMarkerStorage.save(_markers.value)
          .catchError((Object error, StackTrace st) {
        _logger.warning(
          'Failed to persist room read markers',
          error: error,
          stackTrace: st,
        );
      }),
    );
  }

  void dispose() => _markers.dispose();
}
