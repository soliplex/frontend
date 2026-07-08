import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/core/keyed_storage.dart';
import 'package:soliplex_frontend/src/core/storage_migration.dart';

const _schemaVersionKey = 'soliplex_storage_schema_version';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const legacyExactKeys = [
    'soliplex_thread_read_markers',
    'soliplex_thread_unread_anchors',
    'soliplex_lobby_read_markers',
    'soliplex_server_read_markers',
    'soliplex_lobby_hidden_servers',
  ];

  group('migrateStorage', () {
    test('removes the legacy exact-match keys', () async {
      SharedPreferences.setMockInitialValues({
        for (final k in legacyExactKeys) k: 'legacy-value',
      });

      await migrateStorage();

      final prefs = await SharedPreferences.getInstance();
      for (final k in legacyExactKeys) {
        expect(prefs.containsKey(k), isFalse, reason: '$k should be removed');
      }
    });

    test('removes legacy raw-format drafts but keeps new keyed drafts',
        () async {
      const legacyDraft =
          'soliplex_return_to:composer:https://host.example:general';
      final newDraft = encodeKey('soliplex_return_to:composer',
          ['https://host.example', 'iss#user', 'room-1']);

      SharedPreferences.setMockInitialValues({
        legacyDraft: 'draft-a',
        newDraft: 'draft-b',
      });

      await migrateStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(legacyDraft), isFalse,
          reason: 'raw :// legacy draft should be removed');
      expect(prefs.containsKey(newDraft), isTrue,
          reason: 'percent-encoded new draft should survive');
    });

    test('preserves live keyed data and current keys', () async {
      const server = 'https://host.example', user = 'iss#user';
      final serverMarker =
          encodeKey('soliplex_server_read_marker', [server, user]);
      final threadMarker =
          encodeKey('soliplex_thread_read_marker', [server, user, 'room-1']);
      final roomMarker = encodeKey('soliplex_room_read_marker', [server, user]);
      final threadAnchor =
          encodeKey('soliplex_thread_anchor', [server, user, 'room-1']);
      final preserved = <String, Object>{
        serverMarker: 'v',
        threadMarker: 'v',
        roomMarker: 'v',
        threadAnchor: 'v',
        'soliplex_has_launched': true,
        'soliplex_lobby_view_mode': 'grid',
      };

      SharedPreferences.setMockInitialValues({
        // Same-stem legacy plural — must go without taking the new key with it.
        'soliplex_server_read_markers': 'legacy',
        ...preserved,
      });

      await migrateStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('soliplex_server_read_markers'), isFalse);
      for (final k in preserved.keys) {
        expect(prefs.containsKey(k), isTrue, reason: '$k should survive');
      }
    });

    test('no sweep when already at the current schema version', () async {
      SharedPreferences.setMockInitialValues({
        _schemaVersionKey: 1,
        'soliplex_thread_read_markers': 'legacy',
      });

      await migrateStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('soliplex_thread_read_markers'), isTrue,
          reason: 'an already-migrated install must not re-sweep');
    });

    test('sweeps once, then latches at the current version', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_read_markers': 'legacy',
      });

      await migrateStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('soliplex_thread_read_markers'), isFalse);
      expect(prefs.getInt(_schemaVersionKey), 1);

      // A legacy key that reappears after the migration is not swept again.
      await prefs.setString('soliplex_thread_read_markers', 'reappeared');
      await migrateStorage();
      expect(prefs.containsKey('soliplex_thread_read_markers'), isTrue);
    });
  });
}
