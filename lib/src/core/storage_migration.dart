import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.storage_migration');

const _schemaVersionKey = 'soliplex_storage_schema_version';
const _currentSchemaVersion = 1;

/// Device-local keys from the pre-keyed storage format that no code reads any
/// more, plus a defunct hidden-servers key. Removed by exact match, not a prefix
/// sweep: some share a stem with a live keyed key (e.g.
/// `soliplex_server_read_markers` vs `soliplex_server_read_marker:…`), where a
/// prefix sweep would take the live data with it. Exact match is used uniformly
/// so the list stays trivially safe to extend.
const _orphanedExactKeys = <String>[
  'soliplex_thread_read_markers',
  'soliplex_thread_unread_anchors',
  'soliplex_lobby_read_markers',
  'soliplex_server_read_markers',
  'soliplex_lobby_hidden_servers',
];

/// Runs device-local storage migrations in order, once per version bump.
///
/// Each step is gated on the stored schema version, and the target version is
/// written only after the steps complete, so a failure retries on the next
/// launch. Best-effort: the whole run is guarded and never rethrows — a corrupt
/// `SharedPreferences` file must not white-screen the app at bootstrap. Safe to
/// re-run. The stored version is a monotonic integer, not a per-migration flag,
/// so each step gates on `from < N` and shares this one gate.
Future<void> migrateStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getInt(_schemaVersionKey) ?? 0;
    if (from >= _currentSchemaVersion) return;

    // Each step's literal is the version it brings storage up to (not
    // [_currentSchemaVersion], which is the latest — they diverge once a v2 step
    // exists, and a step must never re-run for an install already past it).
    if (from < 1) await _sweepOrphanedKeys(prefs);

    await prefs.setInt(_schemaVersionKey, _currentSchemaVersion);
  } catch (error, stackTrace) {
    // Do not rethrow: the version isn't advanced, so the next launch retries.
    _logger.warning(
      'Storage migration failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// v1: removes the orphaned pre-keyed-format keys. The keyed stores no longer
/// read these, so this clears the leftover data from disk.
Future<void> _sweepOrphanedKeys(SharedPreferences prefs) async {
  for (final key in _orphanedExactKeys) {
    await prefs.remove(key);
  }
  // Pre-keyed composer drafts share the current prefix head but carry a raw
  // '://' (the un-encoded server origin); a percent-encoded key never does,
  // because Uri.encodeComponent escapes it to %3A%2F%2F.
  final orphanedDrafts = prefs
      .getKeys()
      .where((k) =>
          k.startsWith('soliplex_return_to:composer:') && k.contains('://'))
      .toList();
  for (final key in orphanedDrafts) {
    await prefs.remove(key);
  }
}
