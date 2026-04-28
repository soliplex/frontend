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
