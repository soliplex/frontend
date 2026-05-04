import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/application/state_bus.dart';
import 'package:soliplex_client/src/domain/surface.dart';
import 'package:test/test.dart';

class _NarrationsProjection extends StateProjection<List<String>> {
  const _NarrationsProjection();

  @override
  List<String> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map<String, dynamic>) return const [];
    final raw = ui['narrations'];
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && entry['text'] is String) entry['text'] as String,
    ];
  }
}

void main() {
  group('StateBus', () {
    test('starts with frozen empty agent state', () {
      final bus = StateBus();
      expect(bus.agentState.value, isEmpty);
      // Frozen — direct mutation must throw.
      expect(
        () => bus.agentState.value['x'] = 1,
        throwsA(isA<UnsupportedError>()),
      );
      bus.dispose();
    });

    test('setAgentState replaces and exposes a frozen view', () {
      final bus = StateBus()
        ..setAgentState(<String, dynamic>{
          'ui': <String, dynamic>{
            'narrations': <Object>[],
            'hud': <String, dynamic>{},
          },
        });
      expect(bus.agentState.value['ui'], isA<Map<String, dynamic>>());
      // The top-level map is unmodifiable.
      expect(
        () => bus.agentState.value['ui'] = <String, dynamic>{},
        throwsA(isA<UnsupportedError>()),
      );
      bus.dispose();
    });

    test('projection signal updates on each setAgentState', () {
      final bus = StateBus();
      final narrations =
          bus.project<List<String>>(const _NarrationsProjection());
      expect(narrations.value, isEmpty);

      bus.setAgentState({
        'ui': {
          'narrations': [
            {'actor': 'coordinator', 'text': 'first line'},
          ],
        },
      });
      expect(narrations.value, ['first line']);

      bus.setAgentState({
        'ui': {
          'narrations': [
            {'actor': 'coordinator', 'text': 'first line'},
            {'actor': 'primary', 'text': 'second line'},
          ],
        },
      });
      expect(narrations.value, ['first line', 'second line']);

      bus.dispose();
    });

    test('update() runs a transform over the current map', () {
      final bus = StateBus(initialAgentState: {'count': 1})
        ..update((current) => {'count': (current['count'] as int) + 1});
      expect(bus.agentState.value['count'], 2);
      bus.dispose();
    });

    test('dispose is idempotent and stops further updates', () {
      final bus = StateBus()
        ..setAgentState({'a': 1})
        ..dispose();
      expect(bus.isDisposed, isTrue);
      // A second dispose is a no-op (no throw).
      bus.dispose();
    });

    test('addObserver fires after each commit with tag and snapshot', () {
      final bus = StateBus();
      final received = <(String?, Map<String, dynamic>)>[];
      bus
        ..addObserver((tag, snapshot) => received.add((tag, snapshot)))
        ..setAgentState({'a': 1}, tag: 'agui.snapshot')
        ..update((current) => {'a': (current['a'] as int) + 1}, tag: 'delta')
        ..setAgentState({'a': 99}); // untagged

      expect(received, hasLength(3));
      expect(received[0].$1, 'agui.snapshot');
      expect(received[0].$2['a'], 1);
      expect(received[1].$1, 'delta');
      expect(received[1].$2['a'], 2);
      expect(received[2].$1, isNull);
      expect(received[2].$2['a'], 99);
      bus.dispose();
    });

    test('addObserver disposer detaches a single observer', () {
      final bus = StateBus();
      final a = <String?>[];
      final b = <String?>[];
      final disposeA = bus.addObserver((tag, _) => a.add(tag));
      bus
        ..addObserver((tag, _) => b.add(tag))
        ..setAgentState({}, tag: 'first');
      disposeA();
      bus.setAgentState({}, tag: 'second');

      expect(a, ['first']);
      expect(b, ['first', 'second']);
      bus.dispose();
    });

    test(
      'observer detaching itself during dispatch does not skip siblings',
      () {
        final bus = StateBus();
        final calls = <String>[];
        late final void Function() disposeMid;
        bus.addObserver((_, __) => calls.add('first'));
        disposeMid = bus.addObserver((_, __) {
          calls.add('mid');
          disposeMid();
        });
        bus
          ..addObserver((_, __) => calls.add('last'))
          ..setAgentState({});
        expect(calls, ['first', 'mid', 'last']);
        bus.dispose();
      },
    );

    test('dispose clears observers and stops further notifications', () {
      final bus = StateBus();
      final received = <String?>[];
      bus
        ..addObserver((tag, _) => received.add(tag))
        ..setAgentState({}, tag: 'before')
        ..dispose()
        ..setAgentState({}, tag: 'after');

      expect(received, ['before']);
    });

    test('addObserver on disposed bus returns a no-op disposer', () {
      final bus = StateBus()..dispose();
      // Must not throw.
      final disposer = bus.addObserver((_, __) {});
      disposer();
    });

    test(
      'RagSnapshotProjection conforms to StateProjection and produces '
      'a typed snapshot from the rag namespace',
      () {
        final bus = StateBus();
        final ragSignal =
            bus.project<RagSnapshot?>(const RagSnapshotProjection());
        expect(ragSignal.value, isNull);

        bus.setAgentState({
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': <String>[],
          },
        });
        expect(ragSignal.value, isA<RagV042Snapshot>());
        bus.dispose();
      },
    );
  });
}
