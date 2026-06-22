import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/anchor_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart'
    show ThreadActivityKey;
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

ThreadActivityKey _key(String t) => (serverId: 's', roomId: 'r', threadId: t);

String? _anchorOf(UnreadBoundary boundary) =>
    (boundary as BoundaryResolved).anchorId;

void main() {
  group('AnchorTracker', () {
    late List<Map<ThreadActivityKey, String>> saves;
    Map<ThreadActivityKey, String> disk = {};

    AnchorTracker make() => AnchorTracker(
          load: () async => Map.of(disk),
          save: (m) async {
            saves.add(Map.of(m));
          },
        );

    setUp(() {
      saves = [];
      disk = {};
    });

    test('cold open, no prior anchor: resolves to null, advance persists',
        () async {
      final t = make();
      t.beginThread(_key('a'));
      expect(t.boundary, isA<BoundaryPending>());

      await t.loadFromDisk();
      expect(_anchorOf(t.boundary), isNull);

      t.advance('m3');
      expect(saves.last[_key('a')], 'm3');
    });

    test('cold load of a caught-up thread does not re-save on first advance',
        () async {
      disk = {_key('a'): 'm3'};
      final t = make();
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      // loadFromDisk flushes once. The thread is caught up: the first advance
      // carries the same id that was just loaded, so it must NOT write again.
      saves.clear();
      t.advance('m3');
      expect(saves, isEmpty);
    });

    test('advance before load does not persist and does not wipe other threads',
        () async {
      disk = {_key('a'): 'm1', _key('b'): 'x'};
      final t = make();
      t.beginThread(_key('a'));

      // Advance fires before the disk load completes (cached messages).
      t.advance('m3');
      expect(saves, isEmpty, reason: 'must not persist before anchors loaded');

      await t.loadFromDisk();
      // Frozen boundary is the previous DISK value, for the divider.
      expect(_anchorOf(t.boundary), 'm1');
      // The flush contains the in-memory advance AND the other thread.
      expect(saves, isNotEmpty);
      expect(saves.last[_key('a')], 'm3');
      expect(saves.last[_key('b')], 'x');
    });

    test('warm re-entry snapshots the in-memory advanced value', () async {
      disk = {_key('a'): 'm1'};
      final t = make();
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      t.advance('m5');

      t.beginThread(_key('a'));
      expect(_anchorOf(t.boundary), 'm5');
    });

    test('frozen boundary does not move when the anchor advances', () async {
      disk = {_key('a'): 'm1'};
      final t = make();
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      final frozen = _anchorOf(t.boundary);
      t.advance('m9');
      expect(_anchorOf(t.boundary), frozen);
    });

    test('advance ignores null and unchanged ids', () async {
      final t = make();
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      saves.clear();
      t.advance(null);
      t.advance(null);
      expect(saves, isEmpty);
      t.advance('m1');
      expect(saves, hasLength(1));
      t.advance('m1'); // unchanged
      expect(saves, hasLength(1));
    });

    test('load failure resolves to no line and never persists (no clobber)',
        () async {
      disk = {_key('a'): 'm1', _key('b'): 'x'};
      final t = AnchorTracker(
        load: () async => throw StateError('disk unavailable'),
        save: (m) async {
          saves.add(Map.of(m));
        },
      );
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      // Degrades to a resolved "no line" so the timeline stops waiting on a
      // load that will never arrive.
      expect(_anchorOf(t.boundary), isNull);
      // A failed load read nothing, so writing our partial in-memory map would
      // clobber the threads we never read. It must stay silent.
      t.advance('m3');
      expect(saves, isEmpty);
    });

    test('a failed persist is retried on the next advance', () async {
      disk = {_key('a'): 'm1'};
      var failSave = false;
      final t = AnchorTracker(
        load: () async => Map.of(disk),
        save: (m) async {
          if (failSave) throw StateError('write failed');
          saves.add(Map.of(m));
        },
      );
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      saves.clear();

      failSave = true;
      t.advance('m5');
      await pumpEventQueue();
      expect(saves, isEmpty, reason: 'the persist threw');

      // The same id must retry: a failed write rolls back the dedup marker, so
      // it is not suppressed as already-persisted.
      failSave = false;
      t.advance('m5');
      await pumpEventQueue();
      expect(saves.last[_key('a')], 'm5');
    });

    test('serializes overlapping writes so the latest advance wins', () async {
      disk = {_key('a'): 'm1'};
      final gates = <Completer<void>>[];
      final t = AnchorTracker(
        load: () async => Map.of(disk),
        save: (m) async {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          saves.add(Map.of(m));
        },
      );
      t.beginThread(_key('a'));
      await t.loadFromDisk();

      t.advance('m2'); // starts a save; held open by its gate.
      t.advance('m3'); // must not open a second concurrent save.
      expect(gates, hasLength(1), reason: 'only one write in flight');

      gates[0].complete(); // first write finishes...
      await pumpEventQueue();
      expect(gates, hasLength(2), reason: 'the pending change re-flushes');

      gates[1].complete();
      await pumpEventQueue();
      expect(saves.last[_key('a')], 'm3');
    });

    test('advancing before a thread is opened asserts', () {
      final t = make();
      expect(() => t.advance('m1'), throwsA(isA<AssertionError>()));
    });

    test('a thread opened after a failed load resolves to no line, no persist',
        () async {
      final t = AnchorTracker(
        load: () async => throw StateError('disk unavailable'),
        save: (m) async {
          saves.add(Map.of(m));
        },
      );
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      saves.clear();

      t.beginThread(_key('b'));
      expect(_anchorOf(t.boundary), isNull);
      t.advance('m9');
      expect(saves, isEmpty);
    });

    test('dispose flushes an advance a failed write left pending', () async {
      disk = {_key('a'): 'm1'};
      var failSave = true;
      final t = AnchorTracker(
        load: () async => Map.of(disk),
        save: (m) async {
          if (failSave) throw StateError('write failed');
          saves.add(Map.of(m));
        },
      );
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      saves.clear();

      // The write fails and arms the retry, but no further advance arrives.
      t.advance('m5');
      await pumpEventQueue();
      expect(saves, isEmpty, reason: 'the persist threw');

      // Teardown must make the stranded change one last attempt to persist.
      failSave = false;
      await t.dispose();
      expect(saves.last[_key('a')], 'm5');
    });

    test('dispose after a failed load never persists (no clobber)', () async {
      disk = {_key('a'): 'm1', _key('b'): 'x'};
      final t = AnchorTracker(
        load: () async => throw StateError('disk unavailable'),
        save: (m) async {
          saves.add(Map.of(m));
        },
      );
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      t.advance('m5');

      // We read nothing, so writing the partial map on the way out would
      // clobber the threads we never loaded.
      await t.dispose();
      expect(saves, isEmpty);
    });
  });
}
