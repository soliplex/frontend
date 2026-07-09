import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const s = 'https://foo.com', u1 = 'iss#alice', u2 = 'iss#bob', r = 'r1';
  final t = DateTime.utc(2026, 1, 1);

  group('ThreadReadMarkerStorage', () {
    test('round-trips a room\'s markers per user', () async {
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': t});
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          {'th1': t});
    });

    test('normalizes a local instant to UTC', () async {
      final local = DateTime(2026, 6, 1, 12); // local zone, not .utc
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': local});
      final loaded = (await ThreadReadMarkerStorage.loadRoom(
          serverId: s, userId: u1, roomId: r))['th1']!;
      expect(loaded.isUtc, isTrue);
      expect(loaded, local.toUtc());
    });

    test('preserves ids that would collide under a naive composite key',
        () async {
      const server = 'a:b', user = 'iss#u/1', room = 'r|2';
      await ThreadReadMarkerStorage.saveRoom(
          serverId: server, userId: user, roomId: room, markers: {'t|3': t});
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: server, userId: user, roomId: room),
          {'t|3': t});
    });

    test('markers saved as one user are invisible to another (isolation)',
        () async {
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': t});
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
    });

    test(
        'null userId persists to the shared unauthenticated bucket, isolated '
        'from real users', () async {
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: null, roomId: r, markers: {'th1': t});
      // Persisted and re-readable under the unauthenticated (null) bucket — a
      // server requiring no sign-in has no identity to isolate by, so its read
      // state is device-shared rather than dropped.
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: null, roomId: r),
          {'th1': t});
      // A signed-in user does not see the unauthenticated bucket.
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
    });

    test('clearServer removes every user, spares a different-port peer',
        () async {
      const s2 = 'https://foo.com:8443';
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': t});
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u2, roomId: r, markers: {'th1': t});
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s2, userId: u1, roomId: r, markers: {'th1': t});
      await ThreadReadMarkerStorage.clearServer(s);
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s2, userId: u1, roomId: r),
          {'th1': t});
    });

    test('clearRoom removes every user for the room, keeps sibling rooms',
        () async {
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': t});
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u2, roomId: r, markers: {'th1': t});
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: 'r2', markers: {'th9': t});
      await ThreadReadMarkerStorage.clearRoom(s, r);
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: 'r2'),
          {'th9': t});
    });

    test('clearThread removes one thread across users, keeps siblings',
        () async {
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': t, 'th2': t});
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u2, roomId: r, markers: {'th1': t});
      await ThreadReadMarkerStorage.clearThread(s, r, 'th1');
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          {'th2': t});
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
    });

    test('clearThread skips a corrupt user blob but strips valid siblings',
        () async {
      final corruptKey = 'soliplex_thread_read_marker:${Uri.encodeComponent(s)}'
          ':${Uri.encodeComponent(u2)}:${Uri.encodeComponent(r)}';
      SharedPreferences.setMockInitialValues({corruptKey: 'not json{'});
      // A valid sibling user carrying the target thread plus another.
      await ThreadReadMarkerStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, markers: {'th1': t, 'th2': t});

      await ThreadReadMarkerStorage.clearThread(s, r, 'th1');

      // The valid user's th1 is stripped and th2 kept; the corrupt blob can't be
      // stripped, so it is left intact on disk rather than dropped.
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          {'th2': t});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(corruptKey), 'not json{');
    });

    test('discards a corrupt blob and returns empty', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_read_marker:${Uri.encodeComponent(s)}:'
            '${Uri.encodeComponent(u1)}:${Uri.encodeComponent(r)}': 'not json',
      });
      expect(
          await ThreadReadMarkerStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
    });

    test('skips malformed entries but keeps valid ones', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_read_marker:${Uri.encodeComponent(s)}:'
                '${Uri.encodeComponent(u1)}:${Uri.encodeComponent(r)}':
            '{"th1":"2026-06-01T12:00:00Z","th2":"not-a-date","th3":5}',
      });
      final loaded = await ThreadReadMarkerStorage.loadRoom(
          serverId: s, userId: u1, roomId: r);
      expect(loaded, {'th1': DateTime.utc(2026, 6, 1, 12)});
    });
  });
}
