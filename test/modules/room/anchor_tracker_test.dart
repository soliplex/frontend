import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/anchor_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart'
    show ThreadActivityKey;

ThreadActivityKey _key(String t) => (serverId: 's', roomId: 'r', threadId: t);

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
      expect(t.boundaryResolved, isFalse);
      expect(t.frozenBoundaryId, isNull);

      await t.loadFromDisk();
      expect(t.boundaryResolved, isTrue);
      expect(t.frozenBoundaryId, isNull);

      t.advance('m3');
      expect(saves.last[_key('a')], 'm3');
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
      expect(t.frozenBoundaryId, 'm1');
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
      expect(t.boundaryResolved, isTrue);
      expect(t.frozenBoundaryId, 'm5');
    });

    test('frozen boundary does not move when the anchor advances', () async {
      disk = {_key('a'): 'm1'};
      final t = make();
      t.beginThread(_key('a'));
      await t.loadFromDisk();
      final frozen = t.frozenBoundaryId;
      t.advance('m9');
      expect(t.frozenBoundaryId, frozen);
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
  });
}
