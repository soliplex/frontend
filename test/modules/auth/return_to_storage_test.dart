import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/core/keyed_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/return_to_storage.dart';

final _baseTime = DateTime.utc(2026, 5, 20, 12);

void main() {
  group('ReturnToStorage composer', () {
    const u = 'iss#user';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load round-trip', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'server-a',
        userId: u,
        roomId: 'room-1',
        unsentText: 'half-written message',
        now: _baseTime,
      );

      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'server-a',
        userId: u,
        roomId: 'room-1',
        now: _baseTime,
      );

      expect(loaded, 'half-written message');
    });

    test('load returns null when nothing saved', () async {
      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'server-a',
        userId: u,
        roomId: 'room-1',
      );
      expect(loaded, isNull);
    });

    test('saving empty / whitespace-only text clears any existing entry',
        () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r',
        unsentText: 'previous draft',
      );

      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r',
        unsentText: '   ',
      );

      expect(
        await ReturnToStorage.loadComposer(
            serverId: 'a', userId: u, roomId: 'r'),
        isNull,
      );
    });

    test('per-(serverId, roomId) isolation', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r1',
        unsentText: 'A/r1 draft',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'b',
        userId: u,
        roomId: 'r1',
        unsentText: 'B/r1 draft',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r2',
        unsentText: 'A/r2 draft',
        now: _baseTime,
      );

      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          userId: u,
          roomId: 'r1',
          now: _baseTime,
        ),
        'A/r1 draft',
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'b',
          userId: u,
          roomId: 'r1',
          now: _baseTime,
        ),
        'B/r1 draft',
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          userId: u,
          roomId: 'r2',
          now: _baseTime,
        ),
        'A/r2 draft',
      );
    });

    test('load returns null and clears entry past the 24h TTL', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r',
        unsentText: 'old draft',
        now: _baseTime,
      );

      // One second past 24h.
      final later = _baseTime.add(const Duration(hours: 24, seconds: 1));
      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r',
        now: later,
      );
      expect(loaded, isNull);

      // Verify the expired entry was actually cleared.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('load returns null and clears corrupted entry', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        encodeKey('soliplex_return_to:composer', ['a', u, 'r']),
        '{not valid json',
      );

      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r',
      );
      expect(loaded, isNull);
      expect(prefs.getKeys(), isEmpty);
    });

    test('clearComposer removes a stored entry', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r',
        unsentText: 'draft',
      );
      await ReturnToStorage.clearComposer(
          serverId: 'a', userId: u, roomId: 'r');

      expect(
        await ReturnToStorage.loadComposer(
            serverId: 'a', userId: u, roomId: 'r'),
        isNull,
      );
    });

    test('clearServer removes every room draft for that server only', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r1',
        unsentText: 'A/r1',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        userId: u,
        roomId: 'r2',
        unsentText: 'A/r2',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'b',
        userId: u,
        roomId: 'r1',
        unsentText: 'B/r1',
        now: _baseTime,
      );

      await ReturnToStorage.clearServer('a');

      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          userId: u,
          roomId: 'r1',
          now: _baseTime,
        ),
        isNull,
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          userId: u,
          roomId: 'r2',
          now: _baseTime,
        ),
        isNull,
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'b',
          userId: u,
          roomId: 'r1',
          now: _baseTime,
        ),
        'B/r1',
      );
    });

    const s = 'https://foo.com', u1 = 'iss#alice', u2 = 'iss#bob', r = 'r1';

    test('a draft saved as one user is not visible to another (isolation)',
        () async {
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u1, roomId: r, unsentText: 'hi from alice');
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u2, roomId: r),
          isNull);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: r),
          'hi from alice');
    });

    test('null userId no-ops save and returns null on load', () async {
      await ReturnToStorage.saveComposer(
          serverId: s, userId: null, roomId: r, unsentText: 'x');
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: r),
          isNull);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: null, roomId: r),
          isNull);
    });

    test('clearServer removes every user\'s draft for the server', () async {
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u1, roomId: r, unsentText: 'a');
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u2, roomId: r, unsentText: 'b');
      await ReturnToStorage.clearServer(s);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: r),
          isNull);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u2, roomId: r),
          isNull);
    });

    test('clearServer does not touch a same-host different-port server',
        () async {
      const s2 = 'https://foo.com:8443';
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u1, roomId: r, unsentText: 'a');
      await ReturnToStorage.saveComposer(
          serverId: s2, userId: u1, roomId: r, unsentText: 'b');
      await ReturnToStorage.clearServer(s);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: r),
          isNull);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s2, userId: u1, roomId: r),
          'b');
    });

    test('clearRoom removes every user\'s draft for that room, keeps siblings',
        () async {
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u1, roomId: r, unsentText: 'a');
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u2, roomId: r, unsentText: 'b');
      await ReturnToStorage.saveComposer(
          serverId: s, userId: u1, roomId: 'r2', unsentText: 'c');
      await ReturnToStorage.clearRoom(s, r);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: r),
          isNull);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u2, roomId: r),
          isNull);
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: 'r2'),
          'c');
    });

    test(
        'ignores a pre-userId (legacy) raw-key draft — abandoned, not migrated',
        () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_return_to:composer:$s:$r':
            '{"unsentText":"legacy draft","createdAt":"2999-01-01T00:00:00Z"}',
      });
      // The legacy key is not read; a load under the user-scoped key misses.
      expect(
          await ReturnToStorage.loadComposer(
              serverId: s, userId: u1, roomId: r),
          isNull);
    });
  });
}
