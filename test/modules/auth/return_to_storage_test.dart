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

    test('clearServer does not sweep a server whose id is a prefix match',
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
  });
}
