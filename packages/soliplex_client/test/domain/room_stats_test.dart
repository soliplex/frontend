import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('RoomStats', () {
    test('rejects a non-UTC lastActivity', () {
      // The unread comparison (lobby isRoomUnread) relies on lastActivity
      // being UTC; a local DateTime would mis-order by the offset. The
      // constructor guards against a caller that skips the mapper's
      // normalization.
      expect(
        () => RoomStats(lastActivity: DateTime(2026)),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
