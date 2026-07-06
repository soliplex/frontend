import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room;
import 'package:soliplex_frontend/src/modules/lobby/room_grouping.dart';

void main() {
  const alpha = Room(id: 'r1', name: 'Alpha');
  const bravo = Room(id: 'r2', name: 'Bravo');
  const charlie = Room(id: 'r3', name: 'Charlie');
  const delta = Room(id: 'r4', name: 'Delta');

  final activity = <String, DateTime?>{
    'r1': null,
    'r2': DateTime.utc(2026, 6, 1),
    'r3': null,
    'r4': DateTime.utc(2026, 1, 1),
  };
  DateTime? activityFor(Room r) => activity[r.id];

  group('sortRoomsByRecency', () {
    test('orders dated rooms newest-first, undated last in input order', () {
      final ordered =
          sortRoomsByRecency([alpha, bravo, charlie, delta], activityFor);
      expect(
          ordered.map((r) => r.name), ['Bravo', 'Delta', 'Alpha', 'Charlie']);
    });

    test('does not mutate the input list', () {
      final input = [alpha, bravo, charlie, delta];
      sortRoomsByRecency(input, activityFor);
      expect(input, [alpha, bravo, charlie, delta]);
    });

    test('breaks equal timestamps by original order (stable)', () {
      final same = DateTime.utc(2026, 3, 1);
      final ordered = sortRoomsByRecency(
        [alpha, bravo],
        (r) => same,
      );
      expect(ordered.map((r) => r.name), ['Alpha', 'Bravo']);
    });
  });

  group('partitionByUnread', () {
    bool isUnread(Room r) => r.id == 'r2' || r.id == 'r4';

    test('splits unread from read, each recency-ordered', () {
      final parts = partitionByUnread(
          [alpha, bravo, charlie, delta], isUnread, activityFor);
      // Unread: Bravo (Jun) before Delta (Jan).
      expect(parts.unread.map((r) => r.name), ['Bravo', 'Delta']);
      // Read: both undated, original order.
      expect(parts.read.map((r) => r.name), ['Alpha', 'Charlie']);
    });

    test('all-read input yields an empty unread side', () {
      final parts = partitionByUnread(
        [alpha, charlie],
        (_) => false,
        activityFor,
      );
      expect(parts.unread, isEmpty);
      expect(parts.read.map((r) => r.name), ['Alpha', 'Charlie']);
    });

    test('all-unread input yields an empty read side', () {
      final parts = partitionByUnread(
        [bravo, delta],
        (_) => true,
        activityFor,
      );
      expect(parts.unread.map((r) => r.name), ['Bravo', 'Delta']);
      expect(parts.read, isEmpty);
    });
  });
}
