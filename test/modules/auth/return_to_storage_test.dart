import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/return_to_storage.dart';

final _baseTime = DateTime.utc(2026, 5, 20, 12);

void main() {
  group('ReturnToStorage composer', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load round-trip', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'server-a',
        roomId: 'room-1',
        unsentText: 'half-written message',
        now: _baseTime,
      );

      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'server-a',
        roomId: 'room-1',
        now: _baseTime,
      );

      expect(loaded, 'half-written message');
    });

    test('load returns null when nothing saved', () async {
      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'server-a',
        roomId: 'room-1',
      );
      expect(loaded, isNull);
    });

    test('saving empty / whitespace-only text clears any existing entry',
        () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r',
        unsentText: 'previous draft',
      );

      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r',
        unsentText: '   ',
      );

      expect(
        await ReturnToStorage.loadComposer(serverId: 'a', roomId: 'r'),
        isNull,
      );
    });

    test('per-(serverId, roomId) isolation', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r1',
        unsentText: 'A/r1 draft',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'b',
        roomId: 'r1',
        unsentText: 'B/r1 draft',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r2',
        unsentText: 'A/r2 draft',
        now: _baseTime,
      );

      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          roomId: 'r1',
          now: _baseTime,
        ),
        'A/r1 draft',
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'b',
          roomId: 'r1',
          now: _baseTime,
        ),
        'B/r1 draft',
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          roomId: 'r2',
          now: _baseTime,
        ),
        'A/r2 draft',
      );
    });

    test('load returns null and clears entry past the 24h TTL', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r',
        unsentText: 'old draft',
        now: _baseTime,
      );

      // One second past 24h.
      final later = _baseTime.add(const Duration(hours: 24, seconds: 1));
      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'a',
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
        'soliplex_return_to:composer:a:r',
        '{not valid json',
      );

      final loaded = await ReturnToStorage.loadComposer(
        serverId: 'a',
        roomId: 'r',
      );
      expect(loaded, isNull);
      expect(prefs.getKeys(), isEmpty);
    });

    test('clearComposer removes a stored entry', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r',
        unsentText: 'draft',
      );
      await ReturnToStorage.clearComposer(serverId: 'a', roomId: 'r');

      expect(
        await ReturnToStorage.loadComposer(serverId: 'a', roomId: 'r'),
        isNull,
      );
    });

    test('clearServer removes every room draft for that server only', () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r1',
        unsentText: 'A/r1',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r2',
        unsentText: 'A/r2',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'b',
        roomId: 'r1',
        unsentText: 'B/r1',
        now: _baseTime,
      );

      await ReturnToStorage.clearServer('a');

      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          roomId: 'r1',
          now: _baseTime,
        ),
        isNull,
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'a',
          roomId: 'r2',
          now: _baseTime,
        ),
        isNull,
      );
      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'b',
          roomId: 'r1',
          now: _baseTime,
        ),
        'B/r1',
      );
    });

    // The key joins ids with a `:`, so the trailing `:` on the prefix keeps a
    // clear from reaching an id that merely shares a leading substring but not a
    // whole `:`-delimited segment (`a` vs `ab`).
    test('clearServer keeps drafts of an id sharing only a non-boundary prefix',
        () async {
      await ReturnToStorage.saveComposer(
        serverId: 'a',
        roomId: 'r',
        unsentText: 'A/r',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'ab',
        roomId: 'r',
        unsentText: 'AB/r',
        now: _baseTime,
      );

      await ReturnToStorage.clearServer('a');

      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'ab',
          roomId: 'r',
          now: _baseTime,
        ),
        'AB/r',
      );
    });

    // Characterizes a known, accepted over-sweep (issue #393): a server id is a
    // `Uri.origin`, which omits the default port, so a portless origin is a full
    // prefix of the same host with an explicit port. Clearing the portless
    // origin therefore also sweeps the explicit-port sibling's drafts. This
    // pins the current behavior so the keyed-store fix is a deliberate,
    // test-breaking change rather than a silent one.
    test('clearServer over-sweeps a portless origin onto its port sibling',
        () async {
      await ReturnToStorage.saveComposer(
        serverId: 'https://foo.com',
        roomId: 'r',
        unsentText: 'default port',
        now: _baseTime,
      );
      await ReturnToStorage.saveComposer(
        serverId: 'https://foo.com:8443',
        roomId: 'r',
        unsentText: 'explicit port',
        now: _baseTime,
      );

      await ReturnToStorage.clearServer('https://foo.com');

      expect(
        await ReturnToStorage.loadComposer(
          serverId: 'https://foo.com:8443',
          roomId: 'r',
          now: _baseTime,
        ),
        isNull,
      );
    });
  });
}
