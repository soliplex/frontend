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
          roomSeen: null,
          serverSeen: null,
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
          serverId: 's1',
          roomId: 'r1',
          roomSeen: roomSeen,
          serverSeen: null,
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

  group('unreadRoomIds', () {
    test('includes a room with activity newer than its marker', () {
      final activity = {'r1': DateTime.utc(2026, 6, 2)};
      final markers = {
        (serverId: 's1', roomId: 'r1'): DateTime.utc(2026, 6, 1),
      };
      expect(
        unreadRoomIds(activity, markers, serverId: 's1', serverSeen: null),
        {'r1'},
      );
    });

    test('excludes the current room even when its activity is newer', () {
      // The open room reads as read: activity arriving while you view it (e.g.
      // your own reply) must not light its own rail dot.
      final activity = {'r1': DateTime.utc(2026, 6, 2)};
      final markers = {
        (serverId: 's1', roomId: 'r1'): DateTime.utc(2026, 6, 1),
      };
      expect(
        unreadRoomIds(activity, markers,
            serverId: 's1', currentRoomId: 'r1', serverSeen: null),
        isEmpty,
      );
    });

    test('still flags other rooms while one is open', () {
      final activity = {
        'r1': DateTime.utc(2026, 6, 2),
        'r2': DateTime.utc(2026, 6, 2),
      };
      final markers = {
        (serverId: 's1', roomId: 'r1'): DateTime.utc(2026, 6, 1),
        (serverId: 's1', roomId: 'r2'): DateTime.utc(2026, 6, 1),
      };
      expect(
        unreadRoomIds(activity, markers,
            serverId: 's1', currentRoomId: 'r1', serverSeen: null),
        {'r2'},
      );
    });
  });

  group('read-up cascade', () {
    final t1 = DateTime.utc(2026, 1, 1);
    final t5 = DateTime.utc(2026, 1, 5);
    final t9 = DateTime.utc(2026, 1, 9);

    test('server floor marks every room read without a room marker', () {
      // Rooms "a"/"b" have activity but no room marker; the server marker t9
      // floors them so neither reads unread.
      final unread = unreadRoomIds(
        {'a': t5, 'b': t1},
        const {},
        serverId: 's',
        serverSeen: t9,
      );
      expect(unread, isEmpty);
    });

    test('activity newer than the server floor still reads unread', () {
      final unread = unreadRoomIds(
        {'a': t9},
        const {},
        serverId: 's',
        serverSeen: t5,
      );
      expect(unread, {'a'});
    });

    test('a room marker newer than the server floor still floors its activity',
        () {
      // The room's own marker t9 beats the older server floor t5, so activity
      // at t5 reads as read.
      final unread = unreadRoomIds(
        {'a': t5},
        {(serverId: 's', roomId: 'a'): t9},
        serverId: 's',
        serverSeen: t5,
      );
      expect(unread, isEmpty);
    });

    test('a newer server floor supersedes an older existing room marker', () {
      // Room "a" already has a stale room marker t1; the newer server floor t9
      // must win (the floor is the max of the two, not "prefer the room marker
      // when present"), so activity at t5 reads as read. This is the mark-server-
      // read-over-a-partially-read-room case.
      final unread = unreadRoomIds(
        {'a': t5},
        {(serverId: 's', roomId: 'a'): t1},
        serverId: 's',
        serverSeen: t9,
      );
      expect(unread, isEmpty);
    });

    test('room floor marks every thread read without a thread marker', () {
      final unread = unreadThreadIds(
        [_thread('x', lastActivity: t5), _thread('y', lastActivity: t1)],
        const {},
        serverId: 's',
        roomId: 'r1',
        roomSeen: t9,
        serverSeen: null,
      );
      expect(unread, isEmpty);
    });

    test('thread newer than its room/server floor reads unread', () {
      final unread = unreadThreadIds(
        [_thread('x', lastActivity: t9)],
        const {},
        serverId: 's',
        roomId: 'r1',
        roomSeen: t1,
        serverSeen: t5,
      );
      expect(unread, {'x'});
    });

    test('a thread with its own newer marker beats the ancestor floor', () {
      final unread = unreadThreadIds(
        [_thread('x', lastActivity: t5)],
        {(serverId: 's', roomId: 'r1', threadId: 'x'): t9},
        serverId: 's',
        roomId: 'r1',
        roomSeen: t1,
        serverSeen: null,
      );
      expect(unread, isEmpty);
    });

    test('a newer server floor supersedes an older existing thread marker', () {
      // Thread "x" already has a stale thread marker t1 and there is no room
      // marker; the newer server floor t9 must supersede the thread marker
      // (max, not "prefer own marker") AND participate in the ancestor floor
      // even when roomSeen is null, so activity at t5 reads as read.
      final unread = unreadThreadIds(
        [_thread('x', lastActivity: t5)],
        {(serverId: 's', roomId: 'r1', threadId: 'x'): t1},
        serverId: 's',
        roomId: 'r1',
        roomSeen: null,
        serverSeen: t9,
      );
      expect(unread, isEmpty);
    });

    test('shouldMarkRoomRead floors its thread check by the server floor', () {
      // Thread "b" has old activity (t5) and no thread marker, so without the
      // floor it would read unread and block the stamp. The server floor
      // (t7, supplied via serverSeen with no room marker) covers it, leaving no
      // unread thread; thread "a" (read on its own marker) carries the room's
      // latest activity (t9) past the floor, so the room genuinely transitions
      // unread→read and should be stamped. Passing the floor through serverSeen
      // guards that shouldMarkRoomRead folds it into the per-thread check.
      final marked = shouldMarkRoomRead(
        [_thread('a', lastActivity: t9), _thread('b', lastActivity: t5)],
        {(serverId: 's', roomId: 'r1', threadId: 'a'): t9},
        serverId: 's',
        roomId: 'r1',
        roomSeen: null,
        serverSeen: DateTime.utc(2026, 1, 7),
      );
      expect(marked, isTrue);
    });
  });
}
