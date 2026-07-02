import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ServerReadMarkerStorage', () {
    test('defaults to empty when nothing is persisted', () async {
      expect(await ServerReadMarkerStorage.load(), isEmpty);
    });

    test('round-trips markers, normalizing to UTC', () async {
      final markers = {
        's1': DateTime.utc(2026, 6, 1, 12),
        's2': DateTime.utc(2026, 1, 2, 3, 4),
      };
      await ServerReadMarkerStorage.save(markers);

      final loaded = await ServerReadMarkerStorage.load();
      expect(loaded, hasLength(2));
      expect(loaded['s1'], DateTime.utc(2026, 6, 1, 12));
      expect(loaded['s2']!.isUtc, isTrue);
    });

    test('a corrupt payload loads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_server_read_markers': 'not json{'},
      );
      expect(await ServerReadMarkerStorage.load(), isEmpty);
    });

    test('skips malformed entries but keeps valid ones', () async {
      // A partially-corrupt payload must drop only the bad rows, not reset the
      // whole read model: a missing field, an unparseable time, and a non-object
      // entry are each skipped while the one valid row survives.
      SharedPreferences.setMockInitialValues({
        'soliplex_server_read_markers': '['
            '{"s":"s1","t":"2026-06-01T00:00:00Z"},'
            '{"s":"s2","t":"not-a-date"},'
            '{"t":"2026-06-01T00:00:00Z"},'
            '"garbage"'
            ']',
      });
      final loaded = await ServerReadMarkerStorage.load();
      expect(loaded, hasLength(1));
      expect(loaded['s1'], DateTime.utc(2026, 6));
    });
  });

  group('ServerReadMarkers', () {
    const serverId = 's';
    final at = DateTime.utc(2026, 6, 1);

    test('markRead stamps and exposes the marker synchronously', () {
      final markers = ServerReadMarkers();
      markers.markRead(serverId, at);
      expect(markers.value[serverId], at);
      markers.dispose();
    });

    test('ensureLoaded reads markers persisted by an earlier store', () async {
      final seed = ServerReadMarkers()..markRead(serverId, at);
      // Let the write-through persist before the next store loads.
      await Future<void>.delayed(Duration.zero);
      seed.dispose();

      final store = ServerReadMarkers();
      await store.ensureLoaded();

      expect(store.markers.value[serverId], at);
      store.dispose();
    });
  });
}
