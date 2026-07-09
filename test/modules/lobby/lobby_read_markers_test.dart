import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/core/keyed_storage.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const s = 'https://foo.com', u1 = 'iss#alice', u2 = 'iss#bob';
  final t = DateTime.utc(2026, 6, 1, 12);

  group('LobbyReadMarkerStorage', () {
    test('defaults to empty when nothing is persisted', () async {
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isEmpty);
    });

    test('round-trips a server\'s room markers per user, normalizing to UTC',
        () async {
      await LobbyReadMarkerStorage.saveServer(
        serverId: s,
        userId: u1,
        markers: {'r1': t, 'r2': DateTime.utc(2026, 1, 2, 3, 4)},
      );
      final loaded =
          await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1);
      expect(loaded, hasLength(2));
      expect(loaded['r1'], t);
      expect(loaded['r2']!.isUtc, isTrue);
    });

    test('markers saved as one user are invisible to another (isolation)',
        () async {
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {'r1': t});
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u2),
          isEmpty);
    });

    test('a null userId resolves to the shared unauthenticated bucket',
        () async {
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: null, markers: {'r1': t});
      expect(
          await LobbyReadMarkerStorage.loadServer(
              serverId: s, userId: unauthenticatedStorageUser),
          {'r1': t});
    });

    test('clearServer removes every user, spares a same-host different port',
        () async {
      const s2 = 'https://foo.com:8443';
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {'r1': t});
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u2, markers: {'r1': t});
      await LobbyReadMarkerStorage.saveServer(
          serverId: s2, userId: u1, markers: {'r1': t});

      await LobbyReadMarkerStorage.clearServer(s);

      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isEmpty);
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u2),
          isEmpty);
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s2, userId: u1),
          {'r1': t});
    });

    test('clearRoom drops one room across users, keeps siblings and peers',
        () async {
      const s2 = 'https://foo.com:8443';
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {'r1': t, 'r2': t});
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u2, markers: {'r1': t});
      await LobbyReadMarkerStorage.saveServer(
          serverId: s2, userId: u1, markers: {'r1': t});

      await LobbyReadMarkerStorage.clearRoom(s, 'r1');

      // r1 gone for every user of s; r2 sibling kept; the different-port peer
      // and its r1 untouched.
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1),
          {'r2': t});
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u2),
          isEmpty);
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s2, userId: u1),
          {'r1': t});
    });

    test('clearRoom skips a corrupt user blob but strips valid siblings',
        () async {
      final corruptKey = 'soliplex_room_read_marker:${Uri.encodeComponent(s)}:'
          '${Uri.encodeComponent(u2)}';
      SharedPreferences.setMockInitialValues({corruptKey: 'not json{'});
      // A valid sibling user carrying the target room plus another.
      await LobbyReadMarkerStorage.saveServer(
          serverId: s, userId: u1, markers: {'r1': t, 'r2': t});

      await LobbyReadMarkerStorage.clearRoom(s, 'r1');

      // The valid user's r1 is stripped and r2 kept; the corrupt blob can't be
      // stripped, so it is left intact on disk rather than dropped.
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1),
          {'r2': t});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(corruptKey), 'not json{');
    });

    test('discards a corrupt blob and returns empty', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_room_read_marker:${Uri.encodeComponent(s)}:'
            '${Uri.encodeComponent(u1)}': 'not json{',
      });
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isEmpty);
    });

    test('a non-object payload loads as empty', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_room_read_marker:${Uri.encodeComponent(s)}:'
            '${Uri.encodeComponent(u1)}': '["r1"]',
      });
      expect(await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1),
          isEmpty);
    });

    test('skips malformed entries but keeps valid ones', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_room_read_marker:${Uri.encodeComponent(s)}:'
                '${Uri.encodeComponent(u1)}':
            '{"r1":"2026-06-01T00:00:00Z","r2":"not-a-date","r3":5}',
      });
      final loaded =
          await LobbyReadMarkerStorage.loadServer(serverId: s, userId: u1);
      expect(loaded, hasLength(1));
      expect(loaded['r1'], DateTime.utc(2026, 6));
    });
  });
}
