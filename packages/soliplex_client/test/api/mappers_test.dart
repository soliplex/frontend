import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/domain/quiz.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/room_agent.dart';
import 'package:soliplex_client/src/domain/room_skill.dart';
import 'package:soliplex_client/src/domain/run_info.dart';
import 'package:soliplex_client/src/domain/thread_info.dart';
import 'package:test/test.dart';

void main() {
  group('BackendVersionInfo mappers', () {
    group('backendVersionInfoFromJson', () {
      test('parses correctly with all fields', () {
        final json = <String, dynamic>{
          'soliplex': {
            'version': '0.36.dev0',
            'editable_project_location': '/path',
          },
          'fastapi': {'version': '0.124.0'},
          'pydantic': {'version': '2.12.5'},
        };

        final info = backendVersionInfoFromJson(json);

        expect(info.soliplexVersion, equals('0.36.dev0'));
        expect(info.packageVersions, hasLength(3));
        expect(info.packageVersions['soliplex'], equals('0.36.dev0'));
        expect(info.packageVersions['fastapi'], equals('0.124.0'));
        expect(info.packageVersions['pydantic'], equals('2.12.5'));
      });

      test('returns Unknown when soliplex key is missing', () {
        final json = <String, dynamic>{
          'fastapi': {'version': '0.124.0'},
        };

        final info = backendVersionInfoFromJson(json);

        expect(info.soliplexVersion, equals('Unknown'));
        expect(info.packageVersions['fastapi'], equals('0.124.0'));
      });

      test('returns Unknown when soliplex version is null', () {
        final json = <String, dynamic>{
          'soliplex': {'version': null},
        };

        final info = backendVersionInfoFromJson(json);

        expect(info.soliplexVersion, equals('Unknown'));
      });

      test('handles empty response', () {
        final json = <String, dynamic>{};

        final info = backendVersionInfoFromJson(json);

        expect(info.soliplexVersion, equals('Unknown'));
        expect(info.packageVersions, isEmpty);
      });

      test('skips entries without version field', () {
        final json = <String, dynamic>{
          'soliplex': {'version': '0.36.dev0'},
          'invalid': {'no_version': 'here'},
          'also_invalid': 'not a map',
        };

        final info = backendVersionInfoFromJson(json);

        expect(info.packageVersions, hasLength(1));
        expect(info.packageVersions.containsKey('invalid'), isFalse);
        expect(info.packageVersions.containsKey('also_invalid'), isFalse);
      });
    });
  });

  group('Room mappers', () {
    group('roomFromJson', () {
      test('parses correctly with all fields', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'description': 'A test room',
          'metadata': {'key': 'value'},
        };

        final room = roomFromJson(json);

        expect(room.id, equals('room-1'));
        expect(room.name, equals('Test Room'));
        expect(room.description, equals('A test room'));
        expect(room.metadata, equals({'key': 'value'}));
      });

      test('parses correctly with only required fields', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.id, equals('room-1'));
        expect(room.name, equals('Test Room'));
        expect(room.description, equals(''));
        expect(room.metadata, equals(const <String, dynamic>{}));
      });

      test('throws FormatException when id is missing', () {
        final json = <String, dynamic>{'name': 'Test Room'};
        expect(() => roomFromJson(json), throwsFormatException);
      });

      test('throws FormatException when id is non-string', () {
        final json = <String, dynamic>{'id': 123, 'name': 'Test Room'};
        expect(() => roomFromJson(json), throwsFormatException);
      });

      test('throws FormatException when name is missing', () {
        final json = <String, dynamic>{'id': 'room-1'};
        expect(() => roomFromJson(json), throwsFormatException);
      });

      test('throws FormatException when name is non-string', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 42};
        expect(() => roomFromJson(json), throwsFormatException);
      });

      test('handles null description', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'description': null,
        };

        final room = roomFromJson(json);

        expect(room.description, equals(''));
      });

      test('handles null metadata', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'metadata': null,
        };

        final room = roomFromJson(json);

        expect(room.metadata, equals(const <String, dynamic>{}));
      });

      test('parses suggestions correctly', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'suggestions': ['How can I help?', 'Tell me more'],
        };

        final room = roomFromJson(json);

        expect(room.suggestions, equals(['How can I help?', 'Tell me more']));
        expect(room.hasSuggestions, isTrue);
      });

      test('handles missing suggestions field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.suggestions, isEmpty);
        expect(room.hasSuggestions, isFalse);
      });

      test('handles null suggestions', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'suggestions': null,
        };

        final room = roomFromJson(json);

        expect(room.suggestions, isEmpty);
        expect(room.hasSuggestions, isFalse);
      });

      test('filters out non-string suggestions', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'suggestions': ['Valid', 123, null, 'Also valid', true],
        };

        final room = roomFromJson(json);

        expect(room.suggestions, equals(['Valid', 'Also valid']));
      });
    });

    group('roomFromJson — new fields', () {
      test('parses welcome_message', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'welcome_message': 'Welcome!',
        };

        final room = roomFromJson(json);

        expect(room.welcomeMessage, equals('Welcome!'));
        expect(room.hasWelcomeMessage, isTrue);
      });

      test('handles null welcome_message', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'welcome_message': null,
        };

        final room = roomFromJson(json);

        expect(room.welcomeMessage, equals(''));
        expect(room.hasWelcomeMessage, isFalse);
      });

      test('parses enable_attachments', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'enable_attachments': true,
        };

        final room = roomFromJson(json);

        expect(room.enableAttachments, isTrue);
      });

      test('handles null enable_attachments', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'enable_attachments': null,
        };

        final room = roomFromJson(json);

        expect(room.enableAttachments, isFalse);
      });

      test('parses tools map (backend format)', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': {
            'search': {
              'tool_name': 'search',
              'tool_description': 'Search documents',
            },
            'lookup': {
              'tool_name': 'lookup',
              'tool_description': 'Lookup data',
            },
          },
        };

        final room = roomFromJson(json);

        expect(room.toolDefinitions, hasLength(2));
        expect(room.hasToolDefinitions, isTrue);
        final names = room.toolDefinitions.map((t) => t['tool_name']).toList();
        expect(names, containsAll(['search', 'lookup']));
      });

      test('parses tools list (fallback format)', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': [
            {'tool_name': 'search', 'tool_description': 'Search documents'},
            {'tool_name': 'lookup', 'tool_description': 'Lookup data'},
          ],
        };

        final room = roomFromJson(json);

        expect(room.toolDefinitions, hasLength(2));
        expect(room.toolDefinitions[0]['tool_name'], equals('search'));
        expect(room.toolDefinitions[1]['tool_name'], equals('lookup'));
      });

      test('handles empty tools map', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': <String, dynamic>{},
        };

        final room = roomFromJson(json);

        expect(room.toolDefinitions, isEmpty);
        expect(room.hasToolDefinitions, isFalse);
      });

      test('handles null tools', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': null,
        };

        final room = roomFromJson(json);

        expect(room.toolDefinitions, isEmpty);
        expect(room.hasToolDefinitions, isFalse);
      });

      test('handles missing tools field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.toolDefinitions, isEmpty);
      });

      test('filters out non-map tool entries', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': [
            {'tool_name': 'valid'},
            'not-a-map',
            42,
            null,
            {'tool_name': 'also-valid'},
          ],
        };

        final room = roomFromJson(json);

        expect(room.toolDefinitions, hasLength(2));
        expect(room.toolDefinitions[0]['tool_name'], equals('valid'));
        expect(room.toolDefinitions[1]['tool_name'], equals('also-valid'));
      });

      test('parses agui_feature_names', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agui_feature_names': ['streaming', 'tools'],
        };

        final room = roomFromJson(json);

        expect(room.aguiFeatureNames, equals(['streaming', 'tools']));
        expect(room.hasAguiFeatures, isTrue);
      });

      test('handles null agui_feature_names', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agui_feature_names': null,
        };

        final room = roomFromJson(json);

        expect(room.aguiFeatureNames, isEmpty);
        expect(room.hasAguiFeatures, isFalse);
      });

      test('filters out non-string feature names', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agui_feature_names': ['streaming', 42, null, 'tools', true],
        };

        final room = roomFromJson(json);

        expect(room.aguiFeatureNames, equals(['streaming', 'tools']));
      });
    });

    group('roomToJson', () {
      test('serializes correctly with all fields', () {
        const room = Room(
          id: 'room-1',
          name: 'Test Room',
          description: 'A test room',
          metadata: {'key': 'value'},
        );

        final json = roomToJson(room);

        expect(json['id'], equals('room-1'));
        expect(json['name'], equals('Test Room'));
        expect(json['description'], equals('A test room'));
        expect(json['metadata'], equals({'key': 'value'}));
      });

      test('excludes empty fields', () {
        const room = Room(id: 'room-1', name: 'Test Room');

        final json = roomToJson(room);

        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('description'), isFalse);
        expect(json.containsKey('metadata'), isFalse);
        expect(json.containsKey('welcome_message'), isFalse);
        expect(json.containsKey('enable_attachments'), isFalse);
        expect(json.containsKey('tools'), isFalse);
        expect(json.containsKey('agui_feature_names'), isFalse);
      });

      test('serializes new fields when non-default', () {
        const room = Room(
          id: 'room-1',
          name: 'Test Room',
          welcomeMessage: 'Welcome!',
          enableAttachments: true,
          toolDefinitions: [
            {'tool_name': 'search', 'tool_description': 'Search'},
          ],
          aguiFeatureNames: ['streaming'],
        );

        final json = roomToJson(room);

        expect(json['welcome_message'], equals('Welcome!'));
        expect(json['enable_attachments'], isTrue);
        expect(json['tools'], isA<Map<String, dynamic>>());
        final toolsMap = json['tools'] as Map<String, dynamic>;
        final firstTool = toolsMap.values.first as Map<String, dynamic>;
        expect(firstTool['tool_name'], 'search');
        expect(json['agui_feature_names'], equals(['streaming']));
      });
    });

    test('roundtrip serialization', () {
      const original = Room(
        id: 'room-1',
        name: 'Test Room',
        description: 'A test room',
        metadata: {'key': 'value'},
        skills: {
          'web_search': RoomSkill(
            name: 'Web Search',
            description: 'Search the web',
            source: 'filesystem',
            license: 'MIT',
            allowedTools: ['search', 'fetch'],
            metadata: {'author': 'test'},
          ),
        },
      );

      final json = roomToJson(original);
      final restored = roomFromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.description, equals(original.description));
      expect(restored.metadata, equals(original.metadata));
      expect(restored.skills, hasLength(1));
      final skill = restored.skills['web_search']!;
      expect(skill.name, equals('Web Search'));
      expect(skill.description, equals('Search the web'));
      expect(skill.source, equals('filesystem'));
      expect(skill.license, equals('MIT'));
      expect(skill.allowedTools, equals(['search', 'fetch']));
      expect(skill.metadata, equals({'author': 'test'}));
    });
  });

  group('RagDocument mappers', () {
    group('ragDocumentFromJson', () {
      test('parses correctly with all fields', () {
        final json = <String, dynamic>{
          'id': 'doc-uuid-123',
          'title': 'User Manual.pdf',
          'uri': 'file:///docs/manual.pdf',
          'metadata': {'source': 'upload', 'content-type': 'application/pdf'},
          'created_at': '2025-01-15T10:30:00.000',
          'updated_at': '2025-02-20T14:00:00.000',
        };

        final doc = ragDocumentFromJson(json);

        expect(doc.id, equals('doc-uuid-123'));
        expect(doc.title, equals('User Manual.pdf'));
        expect(doc.uri, equals('file:///docs/manual.pdf'));
        expect(
          doc.metadata,
          equals({'source': 'upload', 'content-type': 'application/pdf'}),
        );
        expect(doc.createdAt, equals(DateTime.utc(2025, 1, 15, 10, 30)));
        expect(doc.updatedAt, equals(DateTime.utc(2025, 2, 20, 14)));
      });

      test('defaults optional fields gracefully', () {
        final json = <String, dynamic>{
          'id': 'doc-uuid-123',
          'title': 'Manual.pdf',
        };

        final doc = ragDocumentFromJson(json);

        expect(doc.uri, equals(''));
        expect(doc.metadata, equals(const <String, dynamic>{}));
        expect(doc.createdAt, isNull);
        expect(doc.updatedAt, isNull);
      });

      test('defaults to null for malformed timestamps', () {
        final json = <String, dynamic>{
          'id': 'doc-uuid-123',
          'title': 'Manual.pdf',
          'created_at': 'not-a-date',
          'updated_at': 'also-bad',
        };

        final doc = ragDocumentFromJson(json);

        expect(doc.createdAt, isNull);
        expect(doc.updatedAt, isNull);
      });

      test('falls back to uri when title is null', () {
        final json = <String, dynamic>{
          'id': 'doc-uuid-123',
          'title': null,
          'uri': 'file:///docs/manual.pdf',
        };

        final doc = ragDocumentFromJson(json);

        expect(doc.id, equals('doc-uuid-123'));
        expect(doc.title, equals('file:///docs/manual.pdf'));
      });

      test('falls back to Untitled when title and uri are null', () {
        final json = <String, dynamic>{
          'id': 'doc-uuid-123',
          'title': null,
          'uri': null,
        };

        final doc = ragDocumentFromJson(json);

        expect(doc.id, equals('doc-uuid-123'));
        expect(doc.title, equals('Untitled'));
      });
    });

    group('ragDocumentToJson', () {
      test('serializes correctly with all fields', () {
        final doc = RagDocument(
          id: 'doc-uuid-123',
          title: 'User Manual.pdf',
          uri: 'file:///docs/manual.pdf',
          metadata: const {'source': 'upload'},
          createdAt: DateTime.utc(2025, 1, 15, 10, 30),
          updatedAt: DateTime.utc(2025, 2, 20, 14),
        );

        final json = ragDocumentToJson(doc);

        expect(json['id'], equals('doc-uuid-123'));
        expect(json['title'], equals('User Manual.pdf'));
        expect(json['uri'], equals('file:///docs/manual.pdf'));
        expect(json['metadata'], equals({'source': 'upload'}));
        expect(json['created_at'], equals('2025-01-15T10:30:00.000'));
        expect(json['updated_at'], equals('2025-02-20T14:00:00.000'));
      });

      test('excludes empty/null optional fields', () {
        const doc = RagDocument(id: 'doc-uuid-123', title: 'Manual.pdf');

        final json = ragDocumentToJson(doc);

        expect(json.containsKey('uri'), isFalse);
        expect(json.containsKey('metadata'), isFalse);
        expect(json.containsKey('created_at'), isFalse);
        expect(json.containsKey('updated_at'), isFalse);
      });
    });

    test('roundtrip serialization', () {
      final original = RagDocument(
        id: 'doc-uuid-123',
        title: 'User Manual.pdf',
        uri: 'file:///docs/manual.pdf',
        metadata: const {'source': 'upload'},
        createdAt: DateTime.utc(2025, 1, 15, 10, 30),
        updatedAt: DateTime.utc(2025, 2, 20, 14),
      );

      final json = ragDocumentToJson(original);
      final restored = ragDocumentFromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.title, equals(original.title));
      expect(restored.uri, equals(original.uri));
      expect(restored.metadata, equals(original.metadata));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.updatedAt, equals(original.updatedAt));
    });
  });

  group('ThreadInfo mappers', () {
    group('threadInfoFromJson', () {
      test('parses correctly with all fields', () {
        final json = <String, dynamic>{
          'id': 'thread-1',
          'room_id': 'room-1',
          'initial_run_id': 'run-1',
          'name': 'Test Thread',
          'description': 'A test thread',
          'created': '2025-01-01T00:00:00.000',
          'metadata': {'key': 'value'},
        };

        final thread = threadInfoFromJson(json);

        expect(thread.id, equals('thread-1'));
        expect(thread.roomId, equals('room-1'));
        expect(thread.initialRunId, equals('run-1'));
        expect(thread.name, equals('Test Thread'));
        expect(thread.description, equals('A test thread'));
        expect(thread.createdAt, equals(DateTime.utc(2025)));
        expect(thread.metadata, equals({'key': 'value'}));
      });

      test('parses correctly with only required fields', () {
        final json = <String, dynamic>{
          'id': 'thread-1',
          'room_id': 'room-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final thread = threadInfoFromJson(json);

        expect(thread.id, equals('thread-1'));
        expect(thread.roomId, equals('room-1'));
        expect(thread.initialRunId, equals(''));
        expect(thread.name, equals(''));
        expect(thread.description, equals(''));
        expect(thread.createdAt, equals(DateTime.utc(2025, 1, 15, 10, 30)));
        expect(thread.metadata, equals(const <String, dynamic>{}));
      });

      test('throws FormatException when created is missing', () {
        final json = <String, dynamic>{'id': 'thread-1', 'room_id': 'room-1'};

        expect(() => threadInfoFromJson(json), throwsFormatException);
      });

      test('handles thread_id field', () {
        final json = <String, dynamic>{
          'thread_id': 'thread-1',
          'room_id': 'room-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final thread = threadInfoFromJson(json);

        expect(thread.id, equals('thread-1'));
      });

      test('handles missing room_id', () {
        final json = <String, dynamic>{
          'id': 'thread-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final thread = threadInfoFromJson(json);

        expect(thread.roomId, equals(''));
      });

      test('throws FormatException for invalid created DateTime', () {
        final json = <String, dynamic>{
          'id': 'thread-1',
          'room_id': 'room-1',
          'created': 'invalid-date',
        };

        expect(() => threadInfoFromJson(json), throwsFormatException);
      });

      test('handles null optional fields', () {
        final json = <String, dynamic>{
          'id': 'thread-1',
          'room_id': 'room-1',
          'created': '2025-01-15T10:30:00.000',
          'initial_run_id': null,
          'name': null,
          'description': null,
          'metadata': null,
        };

        final thread = threadInfoFromJson(json);

        expect(thread.initialRunId, equals(''));
        expect(thread.name, equals(''));
        expect(thread.description, equals(''));
        expect(thread.metadata, equals(const <String, dynamic>{}));
      });

      test('parses created timestamp', () {
        final json = <String, dynamic>{
          'thread_id': 'thread-1',
          'room_id': 'room-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final thread = threadInfoFromJson(json);

        expect(thread.id, equals('thread-1'));
        expect(thread.createdAt, equals(DateTime.utc(2025, 1, 15, 10, 30)));
      });

      test(
        'extracts name and description from metadata when not at top level',
        () {
          final json = <String, dynamic>{
            'thread_id': 'thread-1',
            'room_id': 'room-1',
            'created': '2025-01-15T10:30:00.000',
            'metadata': {
              'name': 'Thread from metadata',
              'description': 'Description from metadata',
            },
          };

          final thread = threadInfoFromJson(json);

          expect(thread.name, equals('Thread from metadata'));
          expect(thread.description, equals('Description from metadata'));
        },
      );

      test('prefers top-level name/description over metadata', () {
        final json = <String, dynamic>{
          'id': 'thread-1',
          'room_id': 'room-1',
          'created': '2025-01-15T10:30:00.000',
          'name': 'Top level name',
          'description': 'Top level description',
          'metadata': {
            'name': 'Metadata name',
            'description': 'Metadata description',
          },
        };

        final thread = threadInfoFromJson(json);

        expect(thread.name, equals('Top level name'));
        expect(thread.description, equals('Top level description'));
      });
    });

    group('threadInfoToJson', () {
      test('serializes correctly with all fields', () {
        final createdAt = DateTime.utc(2025);
        final thread = ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          initialRunId: 'run-1',
          name: 'Test Thread',
          description: 'A test thread',
          createdAt: createdAt,
          metadata: const {'key': 'value'},
        );

        final json = threadInfoToJson(thread);

        expect(json['id'], equals('thread-1'));
        expect(json['room_id'], equals('room-1'));
        expect(json['initial_run_id'], equals('run-1'));
        expect(json['name'], equals('Test Thread'));
        expect(json['description'], equals('A test thread'));
        expect(json['created'], equals('2025-01-01T00:00:00.000'));
        expect(json['metadata'], equals({'key': 'value'}));
      });

      test('excludes empty fields', () {
        final thread = ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          createdAt: DateTime.utc(2025),
        );

        final json = threadInfoToJson(thread);

        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('room_id'), isTrue);
        expect(json.containsKey('created'), isTrue);
        expect(json.containsKey('initial_run_id'), isFalse);
        expect(json.containsKey('name'), isFalse);
        expect(json.containsKey('description'), isFalse);
        expect(json.containsKey('metadata'), isFalse);
      });
    });

    test('roundtrip serialization', () {
      final createdAt = DateTime.utc(2025);
      final original = ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        initialRunId: 'run-1',
        name: 'Test Thread',
        description: 'A test thread',
        createdAt: createdAt,
        metadata: const {'key': 'value'},
      );

      final json = threadInfoToJson(original);
      final restored = threadInfoFromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.roomId, equals(original.roomId));
      expect(restored.initialRunId, equals(original.initialRunId));
      expect(restored.name, equals(original.name));
      expect(restored.description, equals(original.description));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.metadata, equals(original.metadata));
    });
  });

  group('RunInfo mappers', () {
    group('runInfoFromJson', () {
      test('parses correctly with all fields', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'thread_id': 'thread-1',
          'label': 'Test Run',
          'created': '2025-01-01T00:00:00.000',
          'completed_at': '2025-01-02T00:00:00.000',
          'status': 'completed',
          'metadata': {'key': 'value'},
        };

        final run = runInfoFromJson(json);

        expect(run.id, equals('run-1'));
        expect(run.threadId, equals('thread-1'));
        expect(run.label, equals('Test Run'));
        expect(run.createdAt, equals(DateTime.utc(2025)));
        expect(run.completion, isA<CompletedAt>());
        expect(run.status, equals(RunStatus.completed));
        expect(run.metadata, equals({'key': 'value'}));
      });

      test('parses correctly with only required fields', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'thread_id': 'thread-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final run = runInfoFromJson(json);

        expect(run.id, equals('run-1'));
        expect(run.threadId, equals('thread-1'));
        expect(run.label, equals(''));
        expect(run.createdAt, equals(DateTime.utc(2025, 1, 15, 10, 30)));
        expect(run.completion, isA<NotCompleted>());
        expect(run.status, equals(RunStatus.pending));
        expect(run.metadata, equals(const <String, dynamic>{}));
      });

      test('throws FormatException when created is missing', () {
        final json = <String, dynamic>{'id': 'run-1', 'thread_id': 'thread-1'};

        expect(() => runInfoFromJson(json), throwsFormatException);
      });

      test('handles run_id field', () {
        final json = <String, dynamic>{
          'run_id': 'run-1',
          'thread_id': 'thread-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final run = runInfoFromJson(json);

        expect(run.id, equals('run-1'));
      });

      test('handles missing thread_id', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'created': '2025-01-15T10:30:00.000',
        };

        final run = runInfoFromJson(json);

        expect(run.threadId, equals(''));
      });

      test('throws FormatException for invalid completed_at DateTime', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'thread_id': 'thread-1',
          'created': '2025-01-15T10:30:00.000',
          'completed_at': 'invalid-date',
        };

        expect(() => runInfoFromJson(json), throwsFormatException);
      });

      test('throws FormatException for invalid created DateTime', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'thread_id': 'thread-1',
          'created': 'invalid-date',
        };

        expect(() => runInfoFromJson(json), throwsFormatException);
      });

      test('handles null label', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'thread_id': 'thread-1',
          'created': '2025-01-15T10:30:00.000',
          'label': null,
        };

        final run = runInfoFromJson(json);

        expect(run.label, equals(''));
      });

      test('handles null metadata', () {
        final json = <String, dynamic>{
          'id': 'run-1',
          'thread_id': 'thread-1',
          'created': '2025-01-15T10:30:00.000',
          'metadata': null,
        };

        final run = runInfoFromJson(json);

        expect(run.metadata, equals(const <String, dynamic>{}));
      });
    });

    group('runInfoToJson', () {
      test('serializes correctly with all fields', () {
        final createdAt = DateTime.utc(2025);
        final completedAt = DateTime.utc(2025, 1, 2);
        final run = RunInfo(
          id: 'run-1',
          threadId: 'thread-1',
          label: 'Test Run',
          createdAt: createdAt,
          completion: CompletedAt(completedAt),
          status: RunStatus.completed,
          metadata: const {'key': 'value'},
        );

        final json = runInfoToJson(run);

        expect(json['id'], equals('run-1'));
        expect(json['thread_id'], equals('thread-1'));
        expect(json['label'], equals('Test Run'));
        expect(json['created'], equals('2025-01-01T00:00:00.000'));
        expect(json['completed_at'], equals('2025-01-02T00:00:00.000'));
        expect(json['status'], equals('completed'));
        expect(json['metadata'], equals({'key': 'value'}));
      });

      test('excludes empty fields', () {
        final run = RunInfo(
          id: 'run-1',
          threadId: 'thread-1',
          createdAt: DateTime.utc(2025),
        );

        final json = runInfoToJson(run);

        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('thread_id'), isTrue);
        expect(json.containsKey('created'), isTrue);
        expect(json.containsKey('status'), isTrue);
        expect(json.containsKey('label'), isFalse);
        expect(json.containsKey('completed_at'), isFalse);
        expect(json.containsKey('metadata'), isFalse);
      });
    });

    test('roundtrip serialization', () {
      final createdAt = DateTime.utc(2025);
      final completedAt = DateTime.utc(2025, 1, 2);
      final original = RunInfo(
        id: 'run-1',
        threadId: 'thread-1',
        label: 'Test Run',
        createdAt: createdAt,
        completion: CompletedAt(completedAt),
        status: RunStatus.completed,
        metadata: const {'key': 'value'},
      );

      final json = runInfoToJson(original);
      final restored = runInfoFromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.threadId, equals(original.threadId));
      expect(restored.label, equals(original.label));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.isCompleted, equals(original.isCompleted));
      expect(restored.status, equals(original.status));
      expect(restored.metadata, equals(original.metadata));
    });
  });

  group('runStatusFromString', () {
    test('parses valid status strings', () {
      expect(runStatusFromString('pending'), equals(RunStatus.pending));
      expect(runStatusFromString('running'), equals(RunStatus.running));
      expect(runStatusFromString('completed'), equals(RunStatus.completed));
      expect(runStatusFromString('failed'), equals(RunStatus.failed));
      expect(runStatusFromString('cancelled'), equals(RunStatus.cancelled));
    });

    test('handles uppercase status strings', () {
      expect(runStatusFromString('PENDING'), equals(RunStatus.pending));
      expect(runStatusFromString('Running'), equals(RunStatus.running));
      expect(runStatusFromString('COMPLETED'), equals(RunStatus.completed));
    });

    test('returns pending for null', () {
      expect(runStatusFromString(null), equals(RunStatus.pending));
    });

    test('returns unknown for unrecognized status', () {
      // 'unknown' is now a valid enum value, so it maps to itself
      expect(runStatusFromString('unknown'), equals(RunStatus.unknown));
      // Truly unrecognized values also map to unknown
      expect(runStatusFromString('invalid'), equals(RunStatus.unknown));
      expect(runStatusFromString('foobar'), equals(RunStatus.unknown));
    });
  });

  group('Quiz mappers', () {
    group('questionTypeFromJson', () {
      test('parses multiple-choice with options', () {
        final json = <String, dynamic>{
          'type': 'multiple-choice',
          'uuid': 'q-1',
          'options': ['A', 'B', 'C', 'D'],
        };

        final type = questionTypeFromJson(json);

        expect(type, isA<MultipleChoice>());
        expect((type as MultipleChoice).options, equals(['A', 'B', 'C', 'D']));
      });

      test('parses fill-blank', () {
        final json = <String, dynamic>{'type': 'fill-blank', 'uuid': 'q-1'};

        final type = questionTypeFromJson(json);

        expect(type, isA<FillBlank>());
      });

      test('parses qa as FreeForm', () {
        final json = <String, dynamic>{'type': 'qa', 'uuid': 'q-1'};

        final type = questionTypeFromJson(json);

        expect(type, isA<FreeForm>());
      });

      test('defaults unknown type to FreeForm', () {
        final json = <String, dynamic>{'type': 'unknown-type', 'uuid': 'q-1'};

        final type = questionTypeFromJson(json);

        expect(type, isA<FreeForm>());
      });
    });

    group('quizQuestionFromJson', () {
      test('parses question with multiple-choice', () {
        final json = <String, dynamic>{
          'inputs': 'What is the capital of France?',
          'expected_output': 'Paris',
          'metadata': {
            'type': 'multiple-choice',
            'uuid': 'q-123',
            'options': ['London', 'Paris', 'Berlin', 'Madrid'],
          },
        };

        final question = quizQuestionFromJson(json);

        expect(question.id, equals('q-123'));
        expect(question.text, equals('What is the capital of France?'));
        // Note: answer is intentionally not exposed in QuizQuestion
        expect(question.type, isA<MultipleChoice>());
        final options = (question.type as MultipleChoice).options;
        expect(options, equals(['London', 'Paris', 'Berlin', 'Madrid']));
      });

      test('parses question with fill-blank', () {
        final json = <String, dynamic>{
          'inputs': 'The sky is ____.',
          'expected_output': 'blue',
          'metadata': {'type': 'fill-blank', 'uuid': 'q-456'},
        };

        final question = quizQuestionFromJson(json);

        expect(question.id, equals('q-456'));
        expect(question.text, equals('The sky is ____.'));
        expect(question.type, isA<FillBlank>());
      });

      test('parses question with qa (free-form)', () {
        final json = <String, dynamic>{
          'inputs': 'Explain photosynthesis.',
          'expected_output': 'Process by which plants convert sunlight.',
          'metadata': {'type': 'qa', 'uuid': 'q-789'},
        };

        final question = quizQuestionFromJson(json);

        expect(question.id, equals('q-789'));
        expect(question.text, equals('Explain photosynthesis.'));
        expect(question.type, isA<FreeForm>());
      });
    });

    group('questionLimitFromJson', () {
      test('returns AllQuestions for null', () {
        final limit = questionLimitFromJson(null);

        expect(limit, isA<AllQuestions>());
      });

      test('returns LimitedQuestions for positive int', () {
        final limit = questionLimitFromJson(5);

        expect(limit, isA<LimitedQuestions>());
        expect((limit as LimitedQuestions).count, equals(5));
      });
    });

    group('quizFromJson', () {
      test('parses quiz with all fields', () {
        final json = <String, dynamic>{
          'id': 'quiz-1',
          'title': 'Geography Quiz',
          'randomize': true,
          'max_questions': 3,
          'questions': [
            {
              'inputs': 'What is the capital of France?',
              'expected_output': 'Paris',
              'metadata': {
                'type': 'multiple-choice',
                'uuid': 'q-1',
                'options': ['London', 'Paris', 'Berlin'],
              },
            },
            {
              'inputs': 'The largest ocean is ____.',
              'expected_output': 'Pacific',
              'metadata': {'type': 'fill-blank', 'uuid': 'q-2'},
            },
          ],
        };

        final quiz = quizFromJson(json);

        expect(quiz.id, equals('quiz-1'));
        expect(quiz.title, equals('Geography Quiz'));
        expect(quiz.randomize, isTrue);
        expect(quiz.questionLimit, isA<LimitedQuestions>());
        expect((quiz.questionLimit as LimitedQuestions).count, equals(3));
        expect(quiz.questions, hasLength(2));
        expect(quiz.questions[0].id, equals('q-1'));
        expect(quiz.questions[1].id, equals('q-2'));
      });

      test('parses quiz with minimal fields', () {
        final json = <String, dynamic>{
          'id': 'quiz-2',
          'title': 'Simple Quiz',
          'questions': <Map<String, dynamic>>[],
        };

        final quiz = quizFromJson(json);

        expect(quiz.id, equals('quiz-2'));
        expect(quiz.title, equals('Simple Quiz'));
        expect(quiz.randomize, isFalse);
        expect(quiz.questionLimit, isA<AllQuestions>());
        expect(quiz.questions, isEmpty);
      });

      test('handles null randomize', () {
        final json = <String, dynamic>{
          'id': 'quiz-3',
          'title': 'Quiz',
          'randomize': null,
          'questions': <Map<String, dynamic>>[],
        };

        final quiz = quizFromJson(json);

        expect(quiz.randomize, isFalse);
      });
    });

    group('quizAnswerResultFromJson', () {
      test('parses correct answer', () {
        final json = <String, dynamic>{
          'correct': 'true',
          'expected_output': 'The correct answer',
        };

        final result = quizAnswerResultFromJson(json);

        expect(result, isA<CorrectAnswer>());
        expect(result.isCorrect, isTrue);
      });

      test('parses incorrect answer', () {
        final json = <String, dynamic>{
          'correct': 'false',
          'expected_output': 'The correct answer',
        };

        final result = quizAnswerResultFromJson(json);

        expect(result, isA<IncorrectAnswer>());
        expect(result.isCorrect, isFalse);
        expect(
          (result as IncorrectAnswer).expectedAnswer,
          equals('The correct answer'),
        );
      });

      test('handles missing expected_output for incorrect answer', () {
        final json = <String, dynamic>{'correct': 'false'};

        final result = quizAnswerResultFromJson(json);

        expect(result, isA<IncorrectAnswer>());
        expect(
          (result as IncorrectAnswer).expectedAnswer,
          equals('(correct answer not provided)'),
        );
      });

      test('throws on invalid correct value', () {
        final json = <String, dynamic>{
          'correct': 'maybe',
          'expected_output': 'Answer',
        };

        expect(
          () => quizAnswerResultFromJson(json),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('roomFromJson with agent', () {
      test('parses default agent', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {
            'kind': 'default',
            'id': 'agent-1',
            'model_name': 'gpt-4o',
            'retries': 3,
            'system_prompt': 'You are helpful.',
            'provider_type': 'openai',
            'provider_base_url': 'https://api.openai.com',
            'provider_key': 'sk-secret',
            'agui_feature_names': ['feature1'],
          },
        };

        final room = roomFromJson(json);

        expect(room.agent, isA<DefaultRoomAgent>());
        final agent = room.agent! as DefaultRoomAgent;
        expect(agent.id, equals('agent-1'));
        expect(agent.modelName, equals('gpt-4o'));
        expect(agent.retries, equals(3));
        expect(agent.systemPrompt, equals('You are helpful.'));
        expect(agent.providerType, equals('openai'));
        expect(agent.aguiFeatureNames, equals(['feature1']));
      });

      test('parses default agent when kind field is omitted', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {
            'id': 'agent-1',
            'model_name': 'gemini-2.5-flash',
            'retries': 3,
            'system_prompt': 'You are a friendly agent.',
            'provider_type': 'google',
            'provider_base_url': null,
            'provider_key': 'secret:GEMINI_API_KEY',
            'agui_feature_names': <String>[],
          },
        };

        final room = roomFromJson(json);

        expect(room.agent, isA<DefaultRoomAgent>());
        final agent = room.agent! as DefaultRoomAgent;
        expect(agent.id, equals('agent-1'));
        expect(agent.modelName, equals('gemini-2.5-flash'));
        expect(agent.retries, equals(3));
        expect(agent.systemPrompt, equals('You are a friendly agent.'));
        expect(agent.providerType, equals('google'));
        expect(agent.aguiFeatureNames, isEmpty);
      });

      test('parses agent without kind or model_name as OtherRoomAgent', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {
            'id': 'agent-1',
            'agui_feature_names': ['some.feature'],
          },
        };

        final room = roomFromJson(json);

        expect(room.agent, isA<OtherRoomAgent>());
        final agent = room.agent! as OtherRoomAgent;
        expect(agent.id, equals('agent-1'));
        expect(agent.kind, isEmpty);
        expect(agent.aguiFeatureNames, equals(['some.feature']));
      });

      test('parses factory agent', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {
            'kind': 'factory',
            'id': 'agent-2',
            'factory_name': 'my.custom.agent',
            'with_agent_config': true,
            'extra_config': {'key': 'value'},
            'agui_feature_names': ['f1'],
          },
        };

        final room = roomFromJson(json);

        expect(room.agent, isA<FactoryRoomAgent>());
        final agent = room.agent! as FactoryRoomAgent;
        expect(agent.id, equals('agent-2'));
        expect(agent.factoryName, equals('my.custom.agent'));
        expect(agent.extraConfig, equals({'key': 'value'}));
        expect(agent.aguiFeatureNames, equals(['f1']));
      });

      test('parses unknown agent kind as OtherRoomAgent', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {
            'kind': 'custom_kind',
            'id': 'agent-3',
            'agui_feature_names': <String>[],
          },
        };

        final room = roomFromJson(json);

        expect(room.agent, isA<OtherRoomAgent>());
        final agent = room.agent! as OtherRoomAgent;
        expect(agent.id, equals('agent-3'));
        expect(agent.kind, equals('custom_kind'));
      });

      test('handles missing agent field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.agent, isNull);
      });

      test('handles null agent field', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': null,
        };

        final room = roomFromJson(json);

        expect(room.agent, isNull);
      });

      test('handles default agent with null system_prompt', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {
            'kind': 'default',
            'id': 'agent-1',
            'model_name': 'gpt-4o',
            'retries': 3,
            'system_prompt': null,
            'provider_type': 'openai',
            'provider_base_url': null,
            'provider_key': 'sk-secret',
          },
        };

        final room = roomFromJson(json);

        final agent = room.agent! as DefaultRoomAgent;
        expect(agent.systemPrompt, isNull);
      });

      test('sets agent to null when agent id is non-string type', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {'kind': 'default', 'id': 123, 'model_name': 'gpt-4o'},
        };

        final room = roomFromJson(json);
        expect(room.agent, isNull);
      });

      test('sets agent to null for default agent missing id', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {'kind': 'default', 'model_name': 'gpt-4o'},
        };

        final room = roomFromJson(json);
        expect(room.agent, isNull);
      });

      test('sets agent to null for default agent missing model_name', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {'kind': 'default', 'id': 'agent-1'},
        };

        final room = roomFromJson(json);
        expect(room.agent, isNull);
      });

      test('sets agent to null for factory agent missing factory_name', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agent': {'kind': 'factory', 'id': 'agent-1'},
        };

        final room = roomFromJson(json);
        expect(room.agent, isNull);
      });
    });

    group('roomFromJson with tools', () {
      test('parses tools map', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': {
            'rag_search': {
              'kind': 'search',
              'tool_name': 'rag_search',
              'tool_description': 'Search documents',
              'tool_requires': 'tool_config',
              'allow_mcp': true,
              'agui_feature_names': ['f1'],
              'extra_parameters': {'rag_lancedb_stem': '/data'},
            },
          },
        };

        final room = roomFromJson(json);

        expect(room.tools, hasLength(1));
        expect(room.tools.containsKey('rag_search'), isTrue);
        final tool = room.tools['rag_search']!;
        expect(tool.name, equals('rag_search'));
        expect(tool.description, equals('Search documents'));
        expect(tool.kind, equals('search'));
        expect(tool.toolRequires, equals('tool_config'));
        expect(tool.allowMcp, isTrue);
        expect(tool.aguiFeatureNames, equals(['f1']));
        expect(tool.extraParameters, equals({'rag_lancedb_stem': '/data'}));
      });

      test('handles missing tools field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.tools, isEmpty);
      });

      test('handles null tools field', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': null,
        };

        final room = roomFromJson(json);

        expect(room.tools, isEmpty);
      });

      test('skips malformed tool entry and parses valid ones', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'tools': {
            'good_tool': {'kind': 'search', 'tool_description': 'Works fine'},
            'bad_tool': 'not a map',
            'another_good': {'kind': 'rag'},
          },
        };

        final room = roomFromJson(json);

        expect(room.tools, hasLength(2));
        expect(room.tools.containsKey('good_tool'), isTrue);
        expect(room.tools.containsKey('another_good'), isTrue);
        expect(room.tools.containsKey('bad_tool'), isFalse);
      });
    });

    group('roomFromJson with mcp_client_toolsets', () {
      test('parses mcp client toolsets', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'mcp_client_toolsets': {
            'my_toolset': {
              'kind': 'http',
              'allowed_tools': ['tool1', 'tool2'],
              'toolset_params': {'url': 'http://localhost:3000'},
            },
          },
        };

        final room = roomFromJson(json);

        expect(room.mcpClientToolsets, hasLength(1));
        final toolset = room.mcpClientToolsets['my_toolset']!;
        expect(toolset.kind, equals('http'));
        expect(toolset.allowedTools, equals(['tool1', 'tool2']));
        expect(toolset.toolsetParams, equals({'url': 'http://localhost:3000'}));
      });

      test('handles null allowed_tools', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'mcp_client_toolsets': {
            'my_toolset': {
              'kind': 'stdio',
              'allowed_tools': null,
              'toolset_params': <String, dynamic>{},
            },
          },
        };

        final room = roomFromJson(json);

        final toolset = room.mcpClientToolsets['my_toolset']!;
        expect(toolset.allowedTools, isNull);
      });

      test('filters non-string items from allowed_tools', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'mcp_client_toolsets': {
            'my_toolset': {
              'kind': 'http',
              'allowed_tools': ['tool1', 123, null, 'tool2'],
              'toolset_params': <String, dynamic>{},
            },
          },
        };

        final room = roomFromJson(json);

        final toolset = room.mcpClientToolsets['my_toolset']!;
        expect(toolset.allowedTools, equals(['tool1', 'tool2']));
      });

      test('handles missing mcp_client_toolsets field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.mcpClientToolsets, isEmpty);
      });

      test('skips malformed toolset entry and parses valid ones', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'mcp_client_toolsets': {
            'good': {'kind': 'http'},
            'bad': 'not a map',
            'also_good': {'kind': 'stdio'},
          },
        };

        final room = roomFromJson(json);

        expect(room.mcpClientToolsets, hasLength(2));
        expect(room.mcpClientToolsets.containsKey('good'), isTrue);
        expect(room.mcpClientToolsets.containsKey('also_good'), isTrue);
        expect(room.mcpClientToolsets.containsKey('bad'), isFalse);
      });
    });

    group('roomSkillFromJson', () {
      test('parses all fields', () {
        final skill = roomSkillFromJson('web_search', {
          'name': 'Web Search',
          'description': 'Search the web',
          'source': 'filesystem',
          'license': 'MIT',
          'compatibility': '>=1.0.0',
          'allowed_tools': 'search fetch',
          'state_namespace': 'web_search_state',
          'metadata': {'author': 'test'},
          'state_type_schema': {'type': 'object'},
        });

        expect(skill.name, equals('Web Search'));
        expect(skill.description, equals('Search the web'));
        expect(skill.source, equals('filesystem'));
        expect(skill.license, equals('MIT'));
        expect(skill.compatibility, equals('>=1.0.0'));
        expect(skill.allowedTools, equals(['search', 'fetch']));
        expect(skill.stateNamespace, equals('web_search_state'));
        expect(skill.metadata, equals({'author': 'test'}));
        expect(skill.stateTypeSchema, equals({'type': 'object'}));
      });

      test('defaults name to key when missing', () {
        final skill = roomSkillFromJson('fallback_name', {
          'description': 'A skill',
        });

        expect(skill.name, equals('fallback_name'));
      });

      test('defaults optional fields to null', () {
        final skill = roomSkillFromJson('basic', {
          'description': 'Basic skill',
        });

        expect(skill.description, equals('Basic skill'));
        expect(skill.source, isNull);
        expect(skill.license, isNull);
        expect(skill.compatibility, isNull);
        expect(skill.allowedTools, isNull);
        expect(skill.stateNamespace, isNull);
        expect(skill.metadata, isEmpty);
        expect(skill.stateTypeSchema, isNull);
      });
    });

    group('roomFromJson with skills', () {
      test('parses skills map', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'skills': {
            'web_search': {
              'name': 'Web Search',
              'description': 'Search the web',
              'source': 'filesystem',
            },
          },
        };

        final room = roomFromJson(json);

        expect(room.skills, hasLength(1));
        final skill = room.skills['web_search']!;
        expect(skill.name, equals('Web Search'));
        expect(skill.description, equals('Search the web'));
        expect(skill.source, equals('filesystem'));
      });

      test('handles missing skills field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.skills, isEmpty);
      });

      test('skips malformed skill entries', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'skills': {
            'good': {'description': 'A good skill'},
            'bad': 'not a map',
            'also_good': {'description': 'Another good skill'},
          },
        };

        final room = roomFromJson(json);

        expect(room.skills, hasLength(2));
        expect(room.skills.containsKey('good'), isTrue);
        expect(room.skills.containsKey('also_good'), isTrue);
        expect(room.skills.containsKey('bad'), isFalse);
      });
    });

    group('roomFromJson with scalar fields', () {
      test('parses welcome_message', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'welcome_message': 'Welcome!',
        };

        final room = roomFromJson(json);

        expect(room.welcomeMessage, equals('Welcome!'));
      });

      test('parses enable_attachments', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'enable_attachments': true,
        };

        final room = roomFromJson(json);

        expect(room.enableAttachments, isTrue);
      });

      test('parses allow_mcp', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'allow_mcp': true,
        };

        final room = roomFromJson(json);

        expect(room.allowMcp, isTrue);
      });

      test('parses agui_feature_names', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'agui_feature_names': ['feature1', 'feature2'],
        };

        final room = roomFromJson(json);

        expect(room.aguiFeatureNames, equals(['feature1', 'feature2']));
      });

      test('handles missing scalar fields with defaults', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.welcomeMessage, equals(''));
        expect(room.enableAttachments, isFalse);
        expect(room.allowMcp, isFalse);
        expect(room.aguiFeatureNames, isEmpty);
      });
    });

    group('roomFromJson with quizIds', () {
      test('extracts quiz IDs from quizzes map', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'quizzes': {
            'quiz-1': {'id': 'quiz-1', 'title': 'Quiz 1'},
            'quiz-2': {'id': 'quiz-2', 'title': 'Quiz 2'},
          },
        };

        final room = roomFromJson(json);

        expect(room.quizIds, containsAll(['quiz-1', 'quiz-2']));
        expect(room.hasQuizzes, isTrue);
      });

      test('handles missing quizzes field', () {
        final json = <String, dynamic>{'id': 'room-1', 'name': 'Test Room'};

        final room = roomFromJson(json);

        expect(room.quizIds, isEmpty);
        expect(room.hasQuizzes, isFalse);
      });

      test('handles null quizzes field', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'quizzes': null,
        };

        final room = roomFromJson(json);

        expect(room.quizIds, isEmpty);
        expect(room.hasQuizzes, isFalse);
      });

      test('handles empty quizzes map', () {
        final json = <String, dynamic>{
          'id': 'room-1',
          'name': 'Test Room',
          'quizzes': <String, dynamic>{},
        };

        final room = roomFromJson(json);

        expect(room.quizIds, isEmpty);
        expect(room.hasQuizzes, isFalse);
      });
    });
  });
}
