import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/core/keyed_storage.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const s = 'https://foo.com', u1 = 'iss#alice', u2 = 'iss#bob';
  final at = DateTime.utc(2026, 6, 1, 12);

  ServerMarkerKey key(String serverId, String userId) =>
      (serverId: serverId, userId: userId);

  group('ServerReadMarkerStorage', () {
    test('defaults to null when nothing is persisted', () async {
      expect(await ServerReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isNull);
    });

    test('round-trips a marker per user, normalizing to UTC', () async {
      await ServerReadMarkerStorage.saveServer(serverId: s, userId: u1, at: at);
      final loaded =
          await ServerReadMarkerStorage.loadServer(serverId: s, userId: u1);
      expect(loaded, at);
      expect(loaded!.isUtc, isTrue);
    });

    test('a marker saved as one user is invisible to another (isolation)',
        () async {
      await ServerReadMarkerStorage.saveServer(serverId: s, userId: u1, at: at);
      expect(await ServerReadMarkerStorage.loadServer(serverId: s, userId: u2),
          isNull);
    });

    test('a null userId resolves to the shared unauthenticated bucket',
        () async {
      await ServerReadMarkerStorage.saveServer(
          serverId: s, userId: null, at: at);
      expect(
          await ServerReadMarkerStorage.loadServer(
              serverId: s, userId: unauthenticatedStorageUser),
          at);
    });

    test('clearServer removes every user, spares a same-host different port',
        () async {
      const s2 = 'https://foo.com:8443';
      await ServerReadMarkerStorage.saveServer(serverId: s, userId: u1, at: at);
      await ServerReadMarkerStorage.saveServer(serverId: s, userId: u2, at: at);
      await ServerReadMarkerStorage.saveServer(
          serverId: s2, userId: u1, at: at);

      await ServerReadMarkerStorage.clearServer(s);

      expect(await ServerReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isNull);
      expect(await ServerReadMarkerStorage.loadServer(serverId: s, userId: u2),
          isNull);
      expect(await ServerReadMarkerStorage.loadServer(serverId: s2, userId: u1),
          at);
    });

    test('a corrupt value loads as null rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_server_read_marker:${Uri.encodeComponent(s)}:'
            '${Uri.encodeComponent(u1)}': 'not-a-date',
      });
      expect(await ServerReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isNull);
    });
  });

  group('ServerReadMarkers', () {
    test('markRead stamps and exposes the marker synchronously', () {
      final store = ServerReadMarkers();
      store.markRead(serverId: s, userId: u1, at: at);
      expect(store.value[key(s, u1)], at);
      store.dispose();
    });

    test('a stamp by one user is invisible to another (isolation)', () {
      final store = ServerReadMarkers();
      store.markRead(serverId: s, userId: u1, at: at);
      expect(store.value[key(s, u1)], at);
      expect(store.value[key(s, u2)], isNull);
      store.dispose();
    });

    test('ensureLoaded reads a marker persisted by an earlier store', () async {
      ServerReadMarkers().markRead(serverId: s, userId: u1, at: at);
      await Future<void>.delayed(Duration.zero);

      final store = ServerReadMarkers();
      await store.ensureLoaded(serverId: s, userId: u1);
      expect(store.value[key(s, u1)], at);
      store.dispose();
    });

    test('markRead normalizes a non-UTC timestamp to UTC', () {
      final store = ServerReadMarkers();
      final local = DateTime(2026, 6, 1, 12); // device-local
      store.markRead(serverId: s, userId: u1, at: local);
      final stored = store.value[key(s, u1)]!;
      expect(stored.isUtc, isTrue);
      expect(stored, local.toUtc());
      store.dispose();
    });

    test('ensureLoaded does not clobber a fresher in-memory stamp', () async {
      // A slow disk load must not overwrite a floor stamped after the load
      // began, which would re-floor the server's rooms to a stale time.
      final older = DateTime.utc(2026, 1, 1);
      await ServerReadMarkerStorage.saveServer(
          serverId: s, userId: u1, at: older);

      final store = ServerReadMarkers();
      store.markRead(serverId: s, userId: u1, at: at); // fresher, in-memory
      await store.ensureLoaded(serverId: s, userId: u1);

      expect(store.value[key(s, u1)], at);
      store.dispose();
    });

    test('a concurrent ensureLoaded awaits the same in-flight load', () async {
      await ServerReadMarkerStorage.saveServer(serverId: s, userId: u1, at: at);
      // Drop the warmed singleton so the load below actually re-reads disk.
      SharedPreferences.resetStatic();

      final store = ServerReadMarkers();
      // Two overlapping loads: awaiting the second must still see the marker,
      // i.e. it awaits the first's disk read rather than returning early.
      final first = store.ensureLoaded(serverId: s, userId: u1);
      final second = store.ensureLoaded(serverId: s, userId: u1);
      await second;
      expect(store.value[key(s, u1)], at,
          reason: 'a concurrent load must not resolve before the disk read');
      await first;
      store.dispose();
    });

    test('clearServer sweeps disk for a user the in-memory view never loaded',
        () async {
      await ServerReadMarkerStorage.saveServer(
          serverId: 's1', userId: 'iss#alice', at: at);
      final store = ServerReadMarkers();

      store.clearServer('s1');
      await Future<void>.delayed(Duration.zero);

      expect(
        await ServerReadMarkerStorage.loadServer(
            serverId: 's1', userId: 'iss#alice'),
        isNull,
      );
      store.dispose();
    });

    test('clearServer drops every user for the server and persists', () async {
      final store = ServerReadMarkers();
      store.markRead(serverId: 's1', userId: u1, at: at);
      store.markRead(serverId: 's1', userId: u2, at: at);
      store.markRead(serverId: 's2', userId: u1, at: at);
      await Future<void>.delayed(Duration.zero);

      store.clearServer('s1');

      expect(store.value.keys, {key('s2', u1)});
      await Future<void>.delayed(Duration.zero);
      final reloaded = ServerReadMarkers();
      await reloaded.ensureLoaded(serverId: 's1', userId: u1);
      await reloaded.ensureLoaded(serverId: 's1', userId: u2);
      await reloaded.ensureLoaded(serverId: 's2', userId: u1);
      expect(reloaded.value.keys, {key('s2', u1)});
      store.dispose();
      reloaded.dispose();
    });
  });
}
