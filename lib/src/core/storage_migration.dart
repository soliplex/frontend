import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.storage_migration');

const _schemaVersionKey = 'soliplex_storage_schema_version';
const _currentSchemaVersion = 1;

/// Device-local keys left over from the pre-keyed storage format (and the
/// hidden-servers key orphaned by the single-server lobby rework). Verified
/// against git history as real removed `_key` constants. Removed by exact match,
/// not a prefix sweep: each shares a stem with a new keyed key
/// (e.g. `soliplex_server_read_markers` vs `soliplex_server_read_marker:…`), so a
/// prefix sweep would take the live data with it.
const _legacyExactKeys = <String>[
  'soliplex_thread_read_markers',
  'soliplex_thread_unread_anchors',
  'soliplex_lobby_read_markers',
  'soliplex_server_read_markers',
  'soliplex_lobby_hidden_servers',
];

/// Runs device-local storage migrations in order, once per version bump.
///
/// Each step is gated on the stored schema version, and the new version is
/// written only after the steps complete, so a failure retries on the next
/// launch. Best-effort: the whole run is guarded and never rethrows — a corrupt
/// `SharedPreferences` file must not white-screen the app at bootstrap. Safe to
/// re-run. A future format change adds an `if (from < 2)` step and bumps
/// [_currentSchemaVersion]; it reuses this same gate rather than a fresh flag.
Future<void> migrateStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getInt(_schemaVersionKey) ?? 0;
    if (from >= _currentSchemaVersion) return;

    // Each step's literal is the version it brings storage up to (not
    // [_currentSchemaVersion], which is the latest — they diverge once a v2 step
    // exists, and a step must never re-run for an install already past it).
    if (from < 1) await _sweepLegacyKeys(prefs); // reach v1

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

/// v1: removes the orphaned pre-keyed-format keys. The keyed stores (PRs 3–5) no
/// longer read these, so this clears the leftover plaintext from disk.
Future<void> _sweepLegacyKeys(SharedPreferences prefs) async {
  for (final key in _legacyExactKeys) {
    await prefs.remove(key);
  }
  // Legacy composer drafts share the new prefix head but carry a raw '://' (the
  // un-encoded server origin); a percent-encoded new key never does, because
  // Uri.encodeComponent escapes it to %3A%2F%2F.
  final legacyDrafts = prefs
      .getKeys()
      .where((k) =>
          k.startsWith('soliplex_return_to:composer:') && k.contains('://'))
      .toList();
  for (final key in legacyDrafts) {
    await prefs.remove(key);
  }
}
