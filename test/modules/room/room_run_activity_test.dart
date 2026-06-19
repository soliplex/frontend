import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/room_run_activity.dart';

ThreadKey _key(String server, String room, String thread) =>
    (serverId: server, roomId: room, threadId: thread);

void main() {
  const s = 'srv';
  const r = 'room-1';

  test('returns a key that left the active set for this room', () {
    final previous = {_key(s, r, 't1')};
    final current = <ThreadKey>{};
    expect(
      completedRoomThreadKeys(previous, current, serverId: s, roomId: r),
      {_key(s, r, 't1')},
    );
  });

  test('excludes keys that left but belong to another room', () {
    final previous = {_key(s, 'other', 't1')};
    expect(
      completedRoomThreadKeys(previous, <ThreadKey>{}, serverId: s, roomId: r),
      isEmpty,
    );
  });

  test('excludes keys that left but belong to another server', () {
    final previous = {_key('other', r, 't1')};
    expect(
      completedRoomThreadKeys(previous, <ThreadKey>{}, serverId: s, roomId: r),
      isEmpty,
    );
  });

  test('excludes keys still active (not completed)', () {
    final previous = {_key(s, r, 't1')};
    final current = {_key(s, r, 't1')};
    expect(
      completedRoomThreadKeys(previous, current, serverId: s, roomId: r),
      isEmpty,
    );
  });

  test('excludes a newly-activated key (entered, did not complete)', () {
    final previous = <ThreadKey>{};
    final current = {_key(s, r, 't1')};
    expect(
      completedRoomThreadKeys(previous, current, serverId: s, roomId: r),
      isEmpty,
    );
  });

  test('excludes the currently-viewed thread', () {
    final previous = {_key(s, r, 't1'), _key(s, r, 't2')};
    final current = <ThreadKey>{};
    expect(
      completedRoomThreadKeys(
        previous,
        current,
        serverId: s,
        roomId: r,
        excludeThreadId: 't1',
      ),
      {_key(s, r, 't2')},
    );
  });

  group('serverRunCompleted', () {
    test('true when a run on this server (any room) reached a terminal state',
        () {
      final previous = {_key(s, 'other-room', 't1')};
      expect(
        serverRunCompleted(previous, <ThreadKey>{}, serverId: s),
        isTrue,
      );
    });

    test('false when the completed run is on another server', () {
      final previous = {_key('other-server', r, 't1')};
      expect(
        serverRunCompleted(previous, <ThreadKey>{}, serverId: s),
        isFalse,
      );
    });

    test('false when the run is still active (not completed)', () {
      final previous = {_key(s, r, 't1')};
      final current = {_key(s, r, 't1')};
      expect(
        serverRunCompleted(previous, current, serverId: s),
        isFalse,
      );
    });

    test('false for a newly-activated run (entered, did not complete)', () {
      expect(
        serverRunCompleted(<ThreadKey>{}, {_key(s, r, 't1')}, serverId: s),
        isFalse,
      );
    });
  });
}
