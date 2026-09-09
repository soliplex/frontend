import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('RoomAgent', () {
    group('DefaultRoomAgent', () {
      test('creates with all fields', () {
        const agent = DefaultRoomAgent(
          id: 'agent-1',
          modelName: 'gpt-4o',
          retries: 3,
          systemPrompt: 'You are a helpful assistant.',
          providerType: 'openai',
          aguiFeatureNames: ['feature1', 'feature2'],
        );

        expect(agent.id, equals('agent-1'));
        expect(agent.modelName, equals('gpt-4o'));
        expect(agent.retries, equals(3));
        expect(agent.systemPrompt, equals('You are a helpful assistant.'));
        expect(agent.providerType, equals('openai'));
        expect(agent.aguiFeatureNames, equals(['feature1', 'feature2']));
      });

      test('creates with defaults', () {
        const agent = DefaultRoomAgent(
          id: 'agent-1',
          modelName: 'gpt-4o',
          retries: 3,
          providerType: 'openai',
        );

        expect(agent.systemPrompt, isNull);
        expect(agent.aguiFeatureNames, isEmpty);
      });

      test('toString includes id and modelName', () {
        const agent = DefaultRoomAgent(
          id: 'agent-1',
          modelName: 'gpt-4o',
          retries: 3,
          providerType: 'openai',
        );

        expect(agent.toString(), contains('agent-1'));
        expect(agent.toString(), contains('gpt-4o'));
      });
    });

    group('FactoryRoomAgent', () {
      test('creates with all fields', () {
        const agent = FactoryRoomAgent(
          id: 'agent-2',
          factoryName: 'my.custom.agent',
          extraConfig: {'key': 'value'},
          aguiFeatureNames: ['feature1'],
        );

        expect(agent.id, equals('agent-2'));
        expect(agent.factoryName, equals('my.custom.agent'));
        expect(agent.extraConfig, equals({'key': 'value'}));
        expect(agent.aguiFeatureNames, equals(['feature1']));
      });

      test('creates with defaults', () {
        const agent = FactoryRoomAgent(
          id: 'agent-2',
          factoryName: 'my.custom.agent',
        );

        expect(agent.extraConfig, isEmpty);
        expect(agent.aguiFeatureNames, isEmpty);
      });

      test('toString includes id and factoryName', () {
        const agent = FactoryRoomAgent(
          id: 'agent-2',
          factoryName: 'my.custom.agent',
        );

        expect(agent.toString(), contains('agent-2'));
        expect(agent.toString(), contains('my.custom.agent'));
      });
    });

    group('OtherRoomAgent', () {
      test('creates with all fields', () {
        const agent = OtherRoomAgent(
          id: 'agent-3',
          kind: 'custom',
          aguiFeatureNames: ['feature1'],
        );

        expect(agent.id, equals('agent-3'));
        expect(agent.kind, equals('custom'));
        expect(agent.aguiFeatureNames, equals(['feature1']));
      });

      test('creates with defaults', () {
        const agent = OtherRoomAgent(id: 'agent-3', kind: 'custom');

        expect(agent.aguiFeatureNames, isEmpty);
      });

      test('toString includes id and kind', () {
        const agent = OtherRoomAgent(id: 'agent-3', kind: 'custom');

        expect(agent.toString(), contains('agent-3'));
        expect(agent.toString(), contains('custom'));
      });
    });

    test('sealed class allows exhaustive switching', () {
      const RoomAgent agent = DefaultRoomAgent(
        id: 'agent-1',
        modelName: 'gpt-4o',
        retries: 3,
        providerType: 'openai',
      );

      final result = switch (agent) {
        DefaultRoomAgent() => 'default',
        FactoryRoomAgent() => 'factory',
        OtherRoomAgent() => 'other',
      };

      expect(result, equals('default'));
    });
  });
}
