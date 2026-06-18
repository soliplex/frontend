import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/room_unread.dart';

ThreadInfo _thread(String id, {DateTime? lastActivity}) => ThreadInfo(
      id: id,
      roomId: 'r1',
      createdAt: DateTime.utc(2026),
      lastActivity: lastActivity,
    );

void main() {
  group('unreadThreadIds', () {
    Set<String> call(
      List<ThreadInfo> threads,
      Map<ThreadActivityKey, DateTime> markers, {
      String? selectedThreadId,
    }) =>
        unreadThreadIds(
          threads,
          markers,
          serverId: 's1',
          roomId: 'r1',
          selectedThreadId: selectedThreadId,
        );

    test('includes a thread with activity newer than its marker', () {
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 2))];
      final markers = {
        (serverId: 's1', roomId: 'r1', threadId: 't1'):
            DateTime.utc(2026, 6, 1),
      };
      expect(call(threads, markers), {'t1'});
    });

    test('excludes a thread whose activity equals its marker (tie = read)', () {
      final t = DateTime.utc(2026, 6, 1);
      final threads = [_thread('t1', lastActivity: t)];
      final markers = {(serverId: 's1', roomId: 'r1', threadId: 't1'): t};
      expect(call(threads, markers), isEmpty);
    });

    test('includes a thread with activity but no marker', () {
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 2))];
      expect(call(threads, const {}), {'t1'});
    });

    test('excludes a thread with no known activity', () {
      final threads = [_thread('t1')];
      expect(call(threads, const {}), isEmpty);
    });

    test('excludes the selected thread', () {
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 2))];
      expect(call(threads, const {}, selectedThreadId: 't1'), isEmpty);
    });

    test('empty for an empty thread list', () {
      expect(call(const [], const {}), isEmpty);
    });
  });
}
