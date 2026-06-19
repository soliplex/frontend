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

    test('rolls a mixed list up to only the unread threads', () {
      final tie = DateTime.utc(2026, 6, 1);
      final threads = [
        _thread('unread', lastActivity: DateTime.utc(2026, 6, 2)),
        _thread('read', lastActivity: tie),
        _thread('quiet'),
        _thread('selected', lastActivity: DateTime.utc(2026, 6, 3)),
      ];
      final markers = {
        (serverId: 's1', roomId: 'r1', threadId: 'unread'):
            DateTime.utc(2026, 6, 1),
        (serverId: 's1', roomId: 'r1', threadId: 'read'): tie,
      };
      expect(call(threads, markers, selectedThreadId: 'selected'), {'unread'});
    });
  });

  group('shouldMarkRoomRead', () {
    bool call(
      List<ThreadInfo> threads,
      Map<ThreadActivityKey, DateTime> markers,
      DateTime? roomSeen, {
      String? selectedThreadId,
    }) =>
        shouldMarkRoomRead(
          threads,
          markers,
          roomSeen,
          serverId: 's1',
          roomId: 'r1',
          selectedThreadId: selectedThreadId,
        );

    test(
        'marks read when all threads are read and a thread is newer than '
        'the room marker', () {
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 2))];
      final markers = {
        (serverId: 's1', roomId: 'r1', threadId: 't1'):
            DateTime.utc(2026, 6, 2),
      };
      expect(call(threads, markers, DateTime.utc(2026, 6, 1)), isTrue);
    });

    test(
        'does NOT mark read while any thread is unread, even if room '
        'activity is newer than the room marker', () {
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 2))];
      // t1 unread (no thread marker) yet its activity is newer than roomSeen.
      expect(call(threads, const {}, DateTime.utc(2026, 6, 1)), isFalse);
    });

    test(
        'does NOT mark read when the latest thread activity is not newer '
        'than the room marker (already caught up)', () {
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 1))];
      final markers = {
        (serverId: 's1', roomId: 'r1', threadId: 't1'):
            DateTime.utc(2026, 6, 1),
      };
      expect(call(threads, markers, DateTime.utc(2026, 6, 2)), isFalse);
    });

    test('does NOT mark read when no thread has known activity', () {
      final threads = [_thread('t1'), _thread('t2')];
      expect(call(threads, const {}, null), isFalse);
    });

    test(
        'judges activity from the thread list it is given — a stale list '
        'whose latest activity is older than the marker stays unmarked', () {
      // Mirrors the race: the room-activity batch may be fresh, but this
      // function only sees the (stale) thread list, so it cannot mark the room
      // read over activity the list has not surfaced yet.
      final threads = [_thread('t1', lastActivity: DateTime.utc(2026, 6, 1))];
      final markers = {
        (serverId: 's1', roomId: 'r1', threadId: 't1'):
            DateTime.utc(2026, 6, 1),
      };
      expect(call(threads, markers, DateTime.utc(2026, 6, 2)), isFalse);
    });
  });
}
