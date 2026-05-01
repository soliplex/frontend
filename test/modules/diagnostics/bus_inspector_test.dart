import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/bus_inspector.dart';

void main() {
  group('BusInspector', () {
    const key = (
      serverId: 's',
      roomId: 'r',
      threadId: 't',
    );
    const otherKey = (
      serverId: 's',
      roomId: 'r',
      threadId: 'other',
    );

    test('starts empty', () {
      final inspector = BusInspector();
      addTearDown(inspector.dispose);
      expect(inspector.events, isEmpty);
    });

    test('explicit tag is preserved verbatim', () {
      final inspector = BusInspector()
        ..record(key, 'seed.initial', {'a': 1})
        ..record(key, 'seed.history', {'a': 2});
      addTearDown(inspector.dispose);

      expect(inspector.events.map((e) => e.tag).toList(),
          ['seed.initial', 'seed.history']);
    });

    test('null tag falls back to agui.run-state when no event seen', () {
      final inspector = BusInspector()..record(key, null, {});
      addTearDown(inspector.dispose);
      expect(inspector.events.single.tag, 'agui.run-state');
    });

    test('record after StateSnapshotEvent is tagged agui.snapshot', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateSnapshotEvent(snapshot: {'x': 1}))
        ..record(key, null, {'x': 1});
      addTearDown(inspector.dispose);
      expect(inspector.events.single.tag, 'agui.snapshot');
    });

    test('record after StateDeltaEvent is tagged agui.delta', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateDeltaEvent(delta: []))
        ..record(key, null, {'x': 1});
      addTearDown(inspector.dispose);
      expect(inspector.events.single.tag, 'agui.delta');
    });

    test('inferred tag is consumed: next untagged commit is run-state', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateSnapshotEvent(snapshot: {}))
        ..record(key, null, {})
        ..record(key, null, {});
      addTearDown(inspector.dispose);
      expect(inspector.events.map((e) => e.tag).toList(),
          ['agui.snapshot', 'agui.run-state']);
    });

    test('per-thread inference: events on key A do not affect key B', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateSnapshotEvent(snapshot: {}))
        ..record(otherKey, null, {});
      addTearDown(inspector.dispose);
      // The state event was on `key`, so the otherKey commit must NOT
      // be tagged agui.snapshot.
      expect(inspector.events.single.tag, 'agui.run-state');
    });

    test('non-state events do not influence tagging', () {
      final inspector = BusInspector()
        ..recordEvent(
          key,
          const TextMessageStartEvent(messageId: 'm-1'),
        )
        ..record(key, null, {});
      addTearDown(inspector.dispose);
      expect(inspector.events.single.tag, 'agui.run-state');
    });

    test('most recent state event wins when several arrive in a row', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateSnapshotEvent(snapshot: {}))
        ..recordEvent(key, const StateDeltaEvent(delta: []))
        ..record(key, null, {});
      addTearDown(inspector.dispose);
      expect(inspector.events.single.tag, 'agui.delta');
    });

    test('record notifies listeners', () {
      final inspector = BusInspector();
      addTearDown(inspector.dispose);
      var calls = 0;
      inspector.addListener(() => calls++);

      inspector.record(key, null, {});
      expect(calls, 1);
    });

    test('recordEvent appends to event records and notifies', () {
      final inspector = BusInspector();
      addTearDown(inspector.dispose);
      var calls = 0;
      inspector.addListener(() => calls++);

      inspector.recordEvent(key, const StateSnapshotEvent(snapshot: {}));
      expect(calls, 1);
      expect(inspector.eventRecords, hasLength(1));
      expect(inspector.eventRecords.single.tag, 'agui.statesnapshot');
    });

    test('event tag is derived from runtime type, lowercased', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateDeltaEvent(delta: []))
        ..recordEvent(
          key,
          const TextMessageStartEvent(messageId: 'm-1'),
        )
        ..recordEvent(key, const RunFinishedEvent(threadId: 't', runId: 'r'));
      addTearDown(inspector.dispose);
      expect(
        inspector.eventRecords.map((r) => r.tag).toList(),
        ['agui.statedelta', 'agui.textmessagestart', 'agui.runfinished'],
      );
    });

    test('overflow drops oldest events', () {
      final inspector = BusInspector(maxEvents: 3);
      addTearDown(inspector.dispose);
      for (var i = 0; i < 5; i++) {
        inspector.record(key, 't$i', {'i': i});
      }
      expect(inspector.events.map((e) => e.tag).toList(), ['t2', 't3', 't4']);
    });

    test('clear empties events, resets pending tags, notifies', () {
      final inspector = BusInspector()
        ..recordEvent(key, const StateSnapshotEvent(snapshot: {}))
        ..record(key, null, {});
      addTearDown(inspector.dispose);
      var clearedNotifications = 0;
      inspector.addListener(() => clearedNotifications++);
      inspector
        ..clear()
        ..record(key, null, {});
      expect(inspector.events.single.tag, 'agui.run-state');
      expect(clearedNotifications, 2); // clear + record
    });

    test('record after dispose is a no-op', () {
      final inspector = BusInspector()..dispose();
      inspector.record(key, null, {});
    });

    test('recordEvent after dispose is a no-op', () {
      final inspector = BusInspector()..dispose();
      inspector.recordEvent(key, const StateSnapshotEvent(snapshot: {}));
    });

    test('rejects non-positive maxEvents', () {
      expect(() => BusInspector(maxEvents: 0), throwsArgumentError);
      expect(() => BusInspector(maxEvents: -1), throwsArgumentError);
    });
  });
}
