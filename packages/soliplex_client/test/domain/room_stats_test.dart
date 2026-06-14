import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('RoomStats', () {
    test('creates with required fields and a null timestamp by default', () {
      const stats = RoomStats(roomId: 'room-1');

      expect(stats.roomId, equals('room-1'));
      expect(stats.lastMessageAt, isNull);
    });

    test('creates with a last-message timestamp', () {
      final at = DateTime.utc(2026, 6);
      final stats = RoomStats(roomId: 'room-1', lastMessageAt: at);

      expect(stats.roomId, equals('room-1'));
      expect(stats.lastMessageAt, equals(at));
    });

    test('value equality and hashCode consider both fields', () {
      final at = DateTime.utc(2026, 6);
      final a = RoomStats(roomId: 'room-1', lastMessageAt: at);
      final b = RoomStats(roomId: 'room-1', lastMessageAt: at);
      final differentTime = RoomStats(
        roomId: 'room-1',
        lastMessageAt: DateTime.utc(2026, 6, 2),
      );
      const differentRoom = RoomStats(roomId: 'room-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentTime)));
      expect(a, isNot(equals(differentRoom)));
      expect(a, equals(a));
    });

    test('toString includes both fields', () {
      final stats = RoomStats(
        roomId: 'room-1',
        lastMessageAt: DateTime.utc(2026, 6),
      );

      expect(stats.toString(), contains('room-1'));
      expect(stats.toString(), contains('lastMessageAt'));
    });
  });
}
