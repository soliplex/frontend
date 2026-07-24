import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('Room', () {
    test('creates with required fields', () {
      const room = Room(id: 'room-1', name: 'Test Room');

      expect(room.id, equals('room-1'));
      expect(room.name, equals('Test Room'));
      expect(room.description, equals(''));
      expect(room.metadata, equals(const <String, dynamic>{}));
      expect(room.quizzes, equals(const <String, String>{}));
      expect(room.suggestions, equals(const <String>[]));
      expect(room.welcomeMessage, equals(''));
      expect(room.toolDefinitions, equals(const <Map<String, dynamic>>[]));
      expect(room.aguiFeatureNames, equals(const <String>[]));
      expect(room.quizIds, isEmpty);
      expect(room.hasDescription, isFalse);
      expect(room.hasQuizzes, isFalse);
      expect(room.hasSuggestions, isFalse);
      expect(room.hasWelcomeMessage, isFalse);
      expect(room.hasToolDefinitions, isFalse);
      expect(room.hasAguiFeatures, isFalse);
      expect(room.allowMcp, isFalse);
      expect(room.agent, isNull);
      expect(room.tools, isEmpty);
      expect(room.mcpClientToolsets, isEmpty);
    });

    test('creates with all fields', () {
      const agent = DefaultRoomAgent(
        id: 'agent-1',
        modelName: 'gpt-4o',
        retries: 3,
        providerType: 'openai',
      );
      const tool = RoomTool(
        name: 'search',
        description: 'Search docs',
        kind: 'search',
      );
      const toolset = McpClientToolset(kind: 'http');

      const room = Room(
        id: 'room-1',
        name: 'Test Room',
        description: 'A test room',
        metadata: {'key': 'value'},
        quizzes: {'quiz-1': 'Quiz One', 'quiz-2': 'Quiz Two'},
        suggestions: ['How can I help?', 'Tell me more'],
        welcomeMessage: 'Welcome!',
        allowMcp: true,
        agent: agent,
        tools: {'search': tool},
        mcpClientToolsets: {'toolset-1': toolset},
        toolDefinitions: [
          {'tool_name': 'search', 'tool_description': 'Search docs'},
        ],
        aguiFeatureNames: ['streaming', 'tools'],
      );

      expect(room.id, equals('room-1'));
      expect(room.name, equals('Test Room'));
      expect(room.description, equals('A test room'));
      expect(room.metadata, equals({'key': 'value'}));
      expect(
        room.quizzes,
        equals({'quiz-1': 'Quiz One', 'quiz-2': 'Quiz Two'}),
      );
      expect(room.suggestions, equals(['How can I help?', 'Tell me more']));
      expect(room.welcomeMessage, equals('Welcome!'));
      expect(room.allowMcp, isTrue);
      expect(room.agent, equals(agent));
      expect(room.tools, equals({'search': tool}));
      expect(room.mcpClientToolsets, equals({'toolset-1': toolset}));
      expect(room.toolDefinitions, hasLength(1));
      expect(room.aguiFeatureNames, equals(['streaming', 'tools']));
      expect(room.quizIds, containsAll(['quiz-1', 'quiz-2']));
      expect(room.hasDescription, isTrue);
      expect(room.hasQuizzes, isTrue);
      expect(room.hasSuggestions, isTrue);
      expect(room.hasWelcomeMessage, isTrue);
      expect(room.hasToolDefinitions, isTrue);
      expect(room.hasAguiFeatures, isTrue);
    });

    group('copyWith', () {
      test('creates modified copy', () {
        const room = Room(id: 'room-1', name: 'Test Room');
        final modified = room.copyWith(name: 'Modified Room');

        expect(modified.id, equals('room-1'));
        expect(modified.name, equals('Modified Room'));
        expect(room.name, equals('Test Room'));
      });

      test('creates copy with all fields modified', () {
        const room = Room(id: 'room-1', name: 'Test Room');
        final modified = room.copyWith(
          id: 'room-2',
          name: 'New Room',
          description: 'New description',
          metadata: {'new': 'data'},
          quizzes: {'quiz-1': 'Quiz One'},
          suggestions: ['Suggestion 1', 'Suggestion 2'],
          welcomeMessage: 'Hello!',
          toolDefinitions: [
            {'tool_name': 'lookup'},
          ],
          aguiFeatureNames: ['streaming'],
        );

        expect(modified.id, equals('room-2'));
        expect(modified.name, equals('New Room'));
        expect(modified.description, equals('New description'));
        expect(modified.metadata, equals({'new': 'data'}));
        expect(modified.quizzes, equals({'quiz-1': 'Quiz One'}));
        expect(modified.quizIds, equals(['quiz-1']));
        expect(modified.suggestions, equals(['Suggestion 1', 'Suggestion 2']));
        expect(modified.welcomeMessage, equals('Hello!'));
        expect(modified.toolDefinitions, hasLength(1));
        expect(modified.aguiFeatureNames, equals(['streaming']));
      });

      test('creates identical copy when no parameters passed', () {
        const room = Room(
          id: 'room-1',
          name: 'Test Room',
          description: 'A description',
          metadata: {'key': 'value'},
          quizzes: {'quiz-1': 'Quiz One'},
          suggestions: ['Suggestion'],
          welcomeMessage: 'Hi',
          toolDefinitions: [
            {'tool_name': 'test'},
          ],
          aguiFeatureNames: ['streaming'],
        );
        final copy = room.copyWith();

        expect(copy.id, equals(room.id));
        expect(copy.name, equals(room.name));
        expect(copy.description, equals(room.description));
        expect(copy.metadata, equals(room.metadata));
        expect(copy.quizzes, equals(room.quizzes));
        expect(copy.quizIds, equals(room.quizIds));
        expect(copy.suggestions, equals(room.suggestions));
        expect(copy.welcomeMessage, equals(room.welcomeMessage));
        expect(copy.toolDefinitions, equals(room.toolDefinitions));
        expect(copy.aguiFeatureNames, equals(room.aguiFeatureNames));
      });
    });

    group('equality', () {
      test('equal based on id', () {
        const room1 = Room(id: 'room-1', name: 'Room 1');
        const room2 = Room(id: 'room-1', name: 'Room 2');
        const room3 = Room(id: 'room-2', name: 'Room 1');

        expect(room1, equals(room2));
        expect(room1, isNot(equals(room3)));
      });

      test('identical returns true', () {
        const room = Room(id: 'room-1', name: 'Test Room');
        expect(room == room, isTrue);
      });
    });

    test('hashCode based on id', () {
      const room1 = Room(id: 'room-1', name: 'Room 1');
      const room2 = Room(id: 'room-1', name: 'Room 2');

      expect(room1.hashCode, equals(room2.hashCode));
    });

    test('toString includes id and name', () {
      const room = Room(id: 'room-1', name: 'Test Room');

      final str = room.toString();

      expect(str, contains('room-1'));
      expect(str, contains('Test Room'));
    });

    group('supportsAttachments', () {
      test('is true when the sandbox skill is present', () {
        const room = Room(
          id: 'r1',
          name: 'Test',
          skills: {
            sandboxSkillName: RoomSkill(
              name: sandboxSkillName,
              description: 'Sandbox',
            ),
          },
        );
        expect(room.supportsAttachments, isTrue);
      });

      test('is false when the sandbox skill is absent', () {
        const room = Room(id: 'r1', name: 'Test');
        expect(room.supportsAttachments, isFalse);
      });

      test('is false when only a different skill is present', () {
        const room = Room(
          id: 'r1',
          name: 'Test',
          skills: {
            'other-skill': RoomSkill(name: 'other-skill', description: 'Other'),
          },
        );
        expect(room.supportsAttachments, isFalse);
      });
    });
  });
}
