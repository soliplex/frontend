import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart'
    show ThreadActivityKey;
import 'package:soliplex_frontend/src/modules/room/thread_read_tracker.dart';

ThreadActivityKey _key(String t) => (serverId: 's', roomId: 'r', threadId: t);

DateTime _at(int minute) => DateTime.utc(2026, 1, 1, 0, minute);

void main() {
  group('ThreadReadTracker', () {
    late List<Map<ThreadActivityKey, DateTime>> saves;
    Map<ThreadActivityKey, DateTime> disk = {};

    ThreadReadTracker make() => ThreadReadTracker(
          load: () async => Map.of(disk),
          save: (m) async {
            saves.add(Map.of(m));
          },
        );

    setUp(() {
      saves = [];
      disk = {};
    });

    test('stamp after load persists the marker', () async {
      final t = make();
      await t.loadFromDisk();
      t.stamp(_key('a'), _at(3));
      await pumpEventQueue();
      expect(saves.last[_key('a')], _at(3));
      expect(t.markers[_key('a')], _at(3));
    });

    test('clearThread drops the thread from memory and persists without it',
        () async {
      disk = {_key('a'): _at(1), _key('b'): _at(2)};
      final t = make();
      await t.loadFromDisk();

      t.clearThread('a');
      await pumpEventQueue();

      // Gone from memory AND from the persisted snapshot, so a later flush can't
      // resurrect the deleted thread; the sibling survives.
      expect(t.markers.containsKey(_key('a')), isFalse);
      expect(t.markers[_key('b')], _at(2));
      expect(saves.last.containsKey(_key('a')), isFalse);
      expect(saves.last[_key('b')], _at(2));
    });

    test('stamp before load does not persist and does not wipe other threads',
        () async {
      disk = {_key('a'): _at(1), _key('b'): _at(2)};
      final t = make();

      // A stamp fires before the disk load completes.
      t.stamp(_key('a'), _at(3));
      expect(saves, isEmpty, reason: 'must not persist before markers loaded');

      await t.loadFromDisk();
      // The flush contains the in-memory stamp AND the other thread from disk.
      expect(saves, isNotEmpty);
      expect(saves.last[_key('a')], _at(3));
      expect(saves.last[_key('b')], _at(2));
      expect(t.markers[_key('b')], _at(2));
    });

    test('load failure never persists (no clobber)', () async {
      disk = {_key('a'): _at(1), _key('b'): _at(2)};
      final t = ThreadReadTracker(
        load: () async => throw StateError('disk unavailable'),
        save: (m) async {
          saves.add(Map.of(m));
        },
      );
      await t.loadFromDisk();
      // A failed load read nothing, so writing the partial in-memory map would
      // clobber the threads we never read. It must stay silent.
      t.stamp(_key('a'), _at(3));
      await pumpEventQueue();
      expect(saves, isEmpty);
    });

    test('a failed persist is retried on the next stamp', () async {
      disk = {_key('a'): _at(1)};
      var failSave = false;
      final t = ThreadReadTracker(
        load: () async => Map.of(disk),
        save: (m) async {
          if (failSave) throw StateError('write failed');
          saves.add(Map.of(m));
        },
      );
      await t.loadFromDisk();
      saves.clear();

      failSave = true;
      t.stamp(_key('a'), _at(5));
      await pumpEventQueue();
      expect(saves, isEmpty, reason: 'the persist threw');

      failSave = false;
      t.stamp(_key('a'), _at(6));
      await pumpEventQueue();
      expect(saves.last[_key('a')], _at(6));
    });

    test('serializes overlapping writes so the latest stamp wins', () async {
      disk = {_key('a'): _at(1)};
      final gates = <Completer<void>>[];
      final t = ThreadReadTracker(
        load: () async => Map.of(disk),
        save: (m) async {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          saves.add(Map.of(m));
        },
      );
      await t.loadFromDisk();

      t.stamp(_key('a'), _at(2)); // starts a save; held open by its gate.
      t.stamp(_key('a'), _at(3)); // must not open a second concurrent save.
      expect(gates, hasLength(1), reason: 'only one write in flight');

      gates[0].complete();
      await pumpEventQueue();
      expect(gates, hasLength(2), reason: 'the pending change re-flushes');

      gates[1].complete();
      await pumpEventQueue();
      expect(saves.last[_key('a')], _at(3));
    });

    test('dispose flushes a stamp a failed write left pending', () async {
      disk = {_key('a'): _at(1)};
      var failSave = true;
      final t = ThreadReadTracker(
        load: () async => Map.of(disk),
        save: (m) async {
          if (failSave) throw StateError('write failed');
          saves.add(Map.of(m));
        },
      );
      await t.loadFromDisk();
      saves.clear();

      t.stamp(_key('a'), _at(5));
      await pumpEventQueue();
      expect(saves, isEmpty, reason: 'the persist threw');

      failSave = false;
      await t.dispose();
      expect(saves.last[_key('a')], _at(5));
    });

    test('dispose after a failed load never persists (no clobber)', () async {
      disk = {_key('a'): _at(1), _key('b'): _at(2)};
      final t = ThreadReadTracker(
        load: () async => throw StateError('disk unavailable'),
        save: (m) async {
          saves.add(Map.of(m));
        },
      );
      await t.loadFromDisk();
      t.stamp(_key('a'), _at(5));

      await t.dispose();
      expect(saves, isEmpty);
    });

    test('dispose before load completes still flushes via the orphaned load',
        () async {
      // The fast room-switch case: the tracker is disposed while its load is
      // still in flight. The orphaned load must still merge the pending stamp
      // and flush it, so the leaving room's read marker survives.
      disk = {_key('a'): _at(1)};
      final loadGate = Completer<void>();
      final t = ThreadReadTracker(
        load: () async {
          await loadGate.future;
          return Map.of(disk);
        },
        save: (m) async {
          saves.add(Map.of(m));
        },
      );

      final loadFuture = t.loadFromDisk();
      t.stamp(_key('b'), _at(9)); // stamp before load resolves
      await t.dispose(); // dispose before load resolves: skips its own flush
      expect(saves, isEmpty, reason: 'load has not resolved yet');

      loadGate.complete();
      await loadFuture;
      await pumpEventQueue();
      // The orphaned load merged the pending stamp and flushed it.
      expect(saves.last[_key('b')], _at(9));
      expect(saves.last[_key('a')], _at(1));
    });
  });
}
