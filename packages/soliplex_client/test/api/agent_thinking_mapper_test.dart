import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/domain/room_agent.dart';
import 'package:test/test.dart';

void main() {
  group('agentThinkingFromJson', () {
    test('reads the levels and the default the room reports', () {
      final thinking = agentThinkingFromJson({
        'levels': ['low', 'medium', 'xhigh'],
        'default': 'medium',
      });

      expect(thinking!.levels, equals(['low', 'medium', 'xhigh']));
      expect(thinking.defaultLevel, equals('medium'));
    });

    test('reads a room with no default', () {
      final thinking = agentThinkingFromJson({
        'levels': ['low'],
      });

      expect(thinking!.defaultLevel, isNull);
    });

    for (final (name, raw) in <(String, Object?)>[
      ('an absent block', null),
      ('a block that is not a map', 'nope'),
      ('an empty level list', <String, dynamic>{'levels': <dynamic>[]}),
      ('a block carrying no levels', <String, dynamic>{'default': 'low'}),
    ]) {
      test('reads $name as no control', () {
        // A backend too old to send the field and a model that offers no
        // control are alike here: there is nothing to offer either way. An
        // empty list is the same — a control with no levels cannot be used.
        expect(agentThinkingFromJson(raw), isNull);
      });
    }

    test('carries onto the agent the room reports', () {
      final agent = roomAgentFromJson({
        'id': 'room-x',
        'model_name': 'Qwen/Qwen3-32B',
        'provider_type': 'vllm',
        'thinking': {
          'levels': ['off', 'low'],
          'default': null,
        },
      });

      expect(agent, isA<DefaultRoomAgent>());
      final thinking = (agent as DefaultRoomAgent).thinking!;
      expect(thinking.levels, equals(['off', 'low']));
    });

    test('an agent whose model does not reason carries none', () {
      final agent = roomAgentFromJson({
        'id': 'room-x',
        'model_name': 'meta-llama/Llama-3.3-70B-Instruct',
        'provider_type': 'vllm',
      });

      expect((agent as DefaultRoomAgent).thinking, isNull);
    });
  });
}
