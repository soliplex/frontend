import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/room/thread_anchor_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const s = 'https://foo.com', u1 = 'iss#alice', u2 = 'iss#bob', r = 'r1';

  group('ThreadAnchorStorage', () {
    test('round-trips a room\'s anchors per user', () async {
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, anchors: {'th1': 'm1'});
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          {'th1': 'm1'});
    });

    test('preserves ids that would collide under a naive composite key',
        () async {
      const server = 'a:b', user = 'iss#u/1', room = 'r|2';
      await ThreadAnchorStorage.saveRoom(
          serverId: server, userId: user, roomId: room, anchors: {'t|3': 'm'});
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: server, userId: user, roomId: room),
          {'t|3': 'm'});
    });

    test('anchors saved as one user are invisible to another (isolation)',
        () async {
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, anchors: {'th1': 'm1'});
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
    });

    test(
        'null userId persists to the shared unauthenticated bucket, isolated '
        'from real users', () async {
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: null, roomId: r, anchors: {'th1': 'm1'});
      // Persisted and re-readable under the unauthenticated (null) bucket.
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: null, roomId: r),
          {'th1': 'm1'});
      // A signed-in user does not see the unauthenticated bucket.
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
    });

    test('clearServer removes every user, spares a different-port peer',
        () async {
      const s2 = 'https://foo.com:8443';
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, anchors: {'th1': 'm1'});
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u2, roomId: r, anchors: {'th1': 'm1'});
      await ThreadAnchorStorage.saveRoom(
          serverId: s2, userId: u1, roomId: r, anchors: {'th1': 'm1'});
      await ThreadAnchorStorage.clearServer(s);
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s2, userId: u1, roomId: r),
          {'th1': 'm1'});
    });

    test('clearRoom removes every user for the room, keeps sibling rooms',
        () async {
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u1, roomId: r, anchors: {'th1': 'm1'});
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u2, roomId: r, anchors: {'th1': 'm1'});
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u1, roomId: 'r2', anchors: {'th9': 'm9'});
      await ThreadAnchorStorage.clearRoom(s, r);
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: 'r2'),
          {'th9': 'm9'});
    });

    test('clearThread removes one thread across users, keeps siblings',
        () async {
      await ThreadAnchorStorage.saveRoom(
          serverId: s,
          userId: u1,
          roomId: r,
          anchors: {'th1': 'm1', 'th2': 'm2'});
      await ThreadAnchorStorage.saveRoom(
          serverId: s, userId: u2, roomId: r, anchors: {'th1': 'm1'});
      await ThreadAnchorStorage.clearThread(s, r, 'th1');
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          {'th2': 'm2'});
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u2, roomId: r),
          isEmpty);
    });

    test('discards a corrupt blob and returns empty', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_anchor:${Uri.encodeComponent(s)}:'
            '${Uri.encodeComponent(u1)}:${Uri.encodeComponent(r)}': 'not json',
      });
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          isEmpty);
    });

    test('skips malformed entries but keeps valid ones', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_anchor:${Uri.encodeComponent(s)}:'
                '${Uri.encodeComponent(u1)}:${Uri.encodeComponent(r)}':
            '{"th1":"m1","th2":123}',
      });
      expect(
          await ThreadAnchorStorage.loadRoom(
              serverId: s, userId: u1, roomId: r),
          {'th1': 'm1'});
    });
  });
}
