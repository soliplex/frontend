import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RoomReadMarkers', () {
    const key = (serverId: 's', roomId: 'r');
    final at = DateTime.utc(2026, 6, 19);

    test('markRead notifies a subscriber synchronously', () {
      final store = RoomReadMarkers();
      final seen = <DateTime?>[];
      final unsub = store.markers.subscribe((m) => seen.add(m[key]));

      store.markRead(key, at);

      // A watcher (the lobby) sees the stamp immediately, with no storage
      // round-trip — this is what removes the lobby/room handoff race.
      expect(seen.last, at);
      unsub();
      store.dispose();
    });

    test('ensureLoaded reads markers persisted by an earlier store', () async {
      final seed = RoomReadMarkers()..markRead(key, at);
      // Let the write-through persist before the next store loads.
      await Future<void>.delayed(Duration.zero);
      seed.dispose();

      final store = RoomReadMarkers();
      await store.ensureLoaded();

      expect(store.markers.value[key], at);
      store.dispose();
    });

    test('ensureLoaded is a no-op after the first load', () async {
      final store = RoomReadMarkers();
      await store.ensureLoaded();
      store.markRead(key, at);
      // A second ensureLoaded must not reload and clobber the in-memory stamp.
      await store.ensureLoaded();
      expect(store.markers.value[key], at);
      store.dispose();
    });

    test('clearServer drops only that server\'s markers and persists',
        () async {
      final store = RoomReadMarkers();
      store.markRead((serverId: 's1', roomId: 'a'), at);
      store.markRead((serverId: 's1', roomId: 'b'), at);
      store.markRead((serverId: 's2', roomId: 'c'), at);
      // Let the mark write-throughs settle before clearing, so the reload
      // below observes clearServer's write rather than a racing stamp save.
      await Future<void>.delayed(Duration.zero);

      store.clearServer('s1');

      expect(store.value.keys, {(serverId: 's2', roomId: 'c')});
      // Persisted: a fresh store loads only the surviving server's marker.
      await Future<void>.delayed(Duration.zero);
      final reloaded = RoomReadMarkers();
      await reloaded.ensureLoaded();
      expect(reloaded.value.keys, {(serverId: 's2', roomId: 'c')});
      store.dispose();
      reloaded.dispose();
    });
  });
}
