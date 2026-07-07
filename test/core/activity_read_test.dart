import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/activity_read.dart';

void main() {
  group('latestSeen', () {
    final early = DateTime.utc(2026, 1, 1);
    final later = DateTime.utc(2026, 6, 1);

    test('returns the later of two markers', () {
      expect(latestSeen(early, later), later);
      expect(latestSeen(later, early), later);
    });

    test('null never wins (treated as never-seen)', () {
      expect(latestSeen(null, later), later);
      expect(latestSeen(later, null), later);
      expect(latestSeen(null, null), isNull);
    });
  });

  group('currentUserRoomMarkers', () {
    final t1 = DateTime.utc(2026, 1, 1);
    final t2 = DateTime.utc(2026, 2, 2);

    test('keeps only entries whose userId matches userFor for that server', () {
      final markers = {
        (serverId: 'A', userId: 'alice', roomId: 'r1'): t1,
        (serverId: 'A', userId: 'bob', roomId: 'r2'): t2,
      };
      final view = currentUserRoomMarkers(markers, (_) => 'alice');
      expect(view, {(serverId: 'A', roomId: 'r1'): t1});
    });

    test('resolves a different current user per server', () {
      final markers = {
        (serverId: 'A', userId: 'alice', roomId: 'r1'): t1,
        (serverId: 'B', userId: 'bob', roomId: 'r2'): t2,
      };
      final userFor = {'A': 'alice', 'B': 'bob'};
      final view = currentUserRoomMarkers(markers, (s) => userFor[s]!);
      expect(view, {
        (serverId: 'A', roomId: 'r1'): t1,
        (serverId: 'B', roomId: 'r2'): t2,
      });
    });
  });

  group('currentUserServerMarkers', () {
    final t1 = DateTime.utc(2026, 1, 1);
    final t2 = DateTime.utc(2026, 2, 2);

    test('keeps only the current user per server', () {
      final markers = {
        (serverId: 'A', userId: 'alice'): t1,
        (serverId: 'A', userId: 'bob'): t2,
        (serverId: 'B', userId: 'bob'): t2,
      };
      final userFor = {'A': 'alice', 'B': 'bob'};
      final view = currentUserServerMarkers(markers, (s) => userFor[s]!);
      expect(view, {'A': t1, 'B': t2});
    });
  });
}
