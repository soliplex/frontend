import 'package:soliplex_client/src/application/thinking_state.dart';
import 'package:test/test.dart';

void main() {
  group('buildThinkingStateOverlay', () {
    test('asserts the level under the namespace the backend registers', () {
      expect(
        buildThinkingStateOverlay('low'),
        equals({
          'thinking': {'level': 'low'},
        }),
      );
    });

    test('asserts null rather than omitting the key', () {
      // Null is what clears a level the thread's cached state still carries
      // from an earlier turn. Omitting the key would leave that one standing.
      expect(
        buildThinkingStateOverlay(null),
        equals({
          'thinking': {'level': null},
        }),
      );
    });
  });

  group('thinkingLevelFromState', () {
    test('reads the level a run asserted', () {
      expect(
        thinkingLevelFromState({
          'thinking': {'level': 'xhigh'},
        }),
        equals('xhigh'),
      );
    });

    test('reads a cleared level as none', () {
      expect(
        thinkingLevelFromState({
          'thinking': {'level': null},
        }),
        isNull,
      );
    });

    for (final (name, state) in <(String, Object?)>[
      ('a state that is not a map', 'nope'),
      ('a null state', null),
      (
        'a state carrying no namespace',
        <String, dynamic>{'rag': <String, dynamic>{}}
      ),
      ('a namespace that is not a map', <String, dynamic>{'thinking': 'nope'}),
      (
        'a level that is not a string',
        <String, dynamic>{
          'thinking': {'level': 7},
        },
      ),
    ]) {
      test('reads $name as nothing asserted', () {
        // This reads a payload the client did not build, so a shape it does
        // not recognise means "nothing asserted" rather than an error.
        expect(thinkingLevelFromState(state), isNull);
      });
    }
  });
}
