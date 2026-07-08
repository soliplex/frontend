import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const s = 'server', u1 = 'iss#alice', u2 = 'iss#bob', r = 'r';
  final at = DateTime.utc(2026, 6, 19);

  RoomMarkerKey key(String serverId, String userId, String roomId) =>
      (serverId: serverId, userId: userId, roomId: roomId);

  group('RoomReadMarkers', () {
    test('markRead notifies a subscriber synchronously', () {
      final store = RoomReadMarkers();
      final seen = <DateTime?>[];
      final unsub = store.markers.subscribe((m) => seen.add(m[key(s, u1, r)]));

      store.markRead(serverId: s, userId: u1, roomId: r, at: at);

      // A watcher (the lobby) sees the stamp immediately, with no storage
      // round-trip — this is what removes the lobby/room handoff race.
      expect(seen.last, at);
      unsub();
      store.dispose();
    });

    test('a stamp by one user is invisible to another (isolation)', () {
      final store = RoomReadMarkers();
      store.markRead(serverId: s, userId: u1, roomId: r, at: at);
      expect(store.value[key(s, u1, r)], at);
      expect(store.value[key(s, u2, r)], isNull);
      store.dispose();
    });

    test('ensureLoaded reads markers persisted by an earlier store', () async {
      RoomReadMarkers().markRead(serverId: s, userId: u1, roomId: r, at: at);
      // Let the write-through persist before the next store loads.
      await Future<void>.delayed(Duration.zero);

      final store = RoomReadMarkers();
      await store.ensureLoaded(serverId: s, userId: u1);

      expect(store.value[key(s, u1, r)], at);
      store.dispose();
    });

    test('ensureLoaded merges under an optimistic stamp made before it returns',
        () async {
      SharedPreferences.setMockInitialValues({});
      // Seed disk with a sibling room for the same (server,user).
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {'other': at});

      final store = RoomReadMarkers();
      final now = DateTime.utc(2026, 7, 1);
      store.markRead(serverId: s, userId: u1, roomId: r, at: now);
      await store.ensureLoaded(serverId: s, userId: u1);

      // The optimistic stamp survives; the disk sibling is merged in under it.
      expect(store.value[key(s, u1, r)], now);
      expect(store.value[key(s, u1, 'other')], at);

      // The stamp's persist loaded the blob first, so it rewrote the full
      // (server,user) set — the disk sibling isn't clobbered to just the stamp.
      await Future<void>.delayed(Duration.zero);
      final reloaded = RoomReadMarkers();
      await reloaded.ensureLoaded(serverId: s, userId: u1);
      expect(reloaded.value[key(s, u1, r)], now);
      expect(reloaded.value[key(s, u1, 'other')], at);
      store.dispose();
      reloaded.dispose();
    });

    test('a stamp during an in-flight load does not truncate the on-disk blob',
        () async {
      // A room already persisted for (s, u1). resetStatic() drops the warmed
      // SharedPreferences singleton so the load below actually re-reads disk
      // (a real in-flight window), not a cached hit.
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {'other': at});
      SharedPreferences.resetStatic();

      final store = RoomReadMarkers();
      final now = DateTime.utc(2026, 7, 1);
      // Start the load but DON'T await it — it is now in flight. A stamp landing
      // now must still wait for the load before rewriting the blob, or it drops
      // 'other' off disk (it isn't in memory yet).
      final loading = store.ensureLoaded(serverId: s, userId: u1);
      store.markRead(serverId: s, userId: u1, roomId: r, at: now);
      await loading;
      await Future<void>.delayed(Duration.zero);

      final reloaded = RoomReadMarkers();
      await reloaded.ensureLoaded(serverId: s, userId: u1);
      expect(reloaded.value[key(s, u1, 'other')], at,
          reason: 'the pre-existing room must survive a stamp made mid-load');
      expect(reloaded.value[key(s, u1, r)], now);
      store.dispose();
      reloaded.dispose();
    });

    test('clearServer sweeps disk for a user the in-memory view never loaded',
        () async {
      // Another user's blob left on disk that this store never ensureLoaded —
      // clearServer must still remove it (the cross-user leak on server re-add).
      await LobbyReadMarkerStorage.saveServer(
          serverId: 's1', userId: 'iss#alice', markers: {'a': at});
      final store = RoomReadMarkers();

      store.clearServer('s1');
      await Future<void>.delayed(Duration.zero);

      expect(
        await LobbyReadMarkerStorage.loadServer(
            serverId: 's1', userId: 'iss#alice'),
        isEmpty,
      );
      store.dispose();
    });

    test('two servers with different users coexist in one signal', () async {
      final store = RoomReadMarkers();
      store.markRead(serverId: 's1', userId: u1, roomId: 'a', at: at);
      store.markRead(serverId: 's2', userId: u2, roomId: 'b', at: at);
      expect(store.value[key('s1', u1, 'a')], at);
      expect(store.value[key('s2', u2, 'b')], at);
      store.dispose();
    });

    test('markRead normalizes a non-UTC timestamp to UTC', () {
      final store = RoomReadMarkers();
      final local = DateTime(2026, 6, 1, 12); // device-local
      store.markRead(serverId: s, userId: u1, roomId: r, at: local);
      final stored = store.value[key(s, u1, r)]!;
      expect(stored.isUtc, isTrue);
      expect(stored, local.toUtc());
      store.dispose();
    });

    test('clearServer drops every user for the server and persists', () async {
      final store = RoomReadMarkers();
      store.markRead(serverId: 's1', userId: u1, roomId: 'a', at: at);
      store.markRead(serverId: 's1', userId: u2, roomId: 'b', at: at);
      store.markRead(serverId: 's2', userId: u1, roomId: 'c', at: at);
      // Let the mark write-throughs settle before clearing, so the reload
      // below observes clearServer's write rather than a racing stamp save.
      await Future<void>.delayed(Duration.zero);

      store.clearServer('s1');

      expect(store.value.keys, {key('s2', u1, 'c')});
      // Persisted: a fresh store loads only the surviving server's marker.
      await Future<void>.delayed(Duration.zero);
      final reloaded = RoomReadMarkers();
      await reloaded.ensureLoaded(serverId: 's1', userId: u1);
      await reloaded.ensureLoaded(serverId: 's1', userId: u2);
      await reloaded.ensureLoaded(serverId: 's2', userId: u1);
      expect(reloaded.value.keys, {key('s2', u1, 'c')});
      store.dispose();
      reloaded.dispose();
    });

    test('a clearServer during an in-flight load is not undone on resume',
        () async {
      // A blob on disk for (s, u1). The singleton is warm, so the concurrent
      // load below reads the blob (it wins the shared cache), giving a real
      // in-flight window in which the clear lands — the production timing.
      await SharedPreferences.getInstance();
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {r: at});

      final store = RoomReadMarkers();
      // Start the load but DON'T await it — it is now parked on the disk read.
      final loading = store.ensureLoaded(serverId: s, userId: u1);
      // The server is removed while that load is in flight.
      store.clearServer(s);
      await loading; // the load resumes AFTER the clear, holding the read blob
      await Future<void>.delayed(Duration.zero);

      // The resumed load must not re-insert the swept blob: doing so would hide
      // unread content if the server were re-added under the same id.
      expect(store.value[key(s, u1, r)], isNull,
          reason: 'a load resuming after clearServer must not resurrect it');
      store.dispose();
    });

    test('a load resolving after dispose does not throw', () async {
      await SharedPreferences.getInstance();
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {r: at});

      final store = RoomReadMarkers();
      final loading = store.ensureLoaded(serverId: s, userId: u1);
      store.dispose(); // disposed while the load is in flight
      // The load must not write to the disposed signal; no throw is the assert.
      await loading;
    });
  });
}
