import 'dart:convert';

import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

// -- Fixtures ----------------------------------------------------------------

const _server = 'test-server';
const _roomId = 'test-room';
const _threadId = 'thread-1';
const _runId = 'run-1';
final _now = DateTime(2026);

ThreadInfo _threadInfo({String? id, String? runId}) => ThreadInfo(
      id: id ?? _threadId,
      roomId: _roomId,
      initialRunId: runId ?? _runId,
      createdAt: _now,
    );

RunInfo _runInfo({String? id}) => RunInfo(
      id: id ?? _runId,
      threadId: _threadId,
      createdAt: _now,
    );

Stream<BaseEvent> _happyStream({
  String threadId = _threadId,
  String runId = _runId,
  String messageId = 'msg-1',
  List<String> deltas = const ['Hello world'],
  dynamic stateSnapshot,
}) {
  return Stream.fromIterable([
    RunStartedEvent(threadId: threadId, runId: runId),
    TextMessageStartEvent(messageId: messageId),
    for (final d in deltas)
      TextMessageContentEvent(messageId: messageId, delta: d),
    TextMessageEndEvent(messageId: messageId),
    if (stateSnapshot != null) StateSnapshotEvent(snapshot: stateSnapshot),
    RunFinishedEvent(threadId: threadId, runId: runId),
  ]);
}

Stream<BaseEvent> _errorStream({
  String threadId = _threadId,
  String runId = _runId,
  String error = 'something broke',
}) {
  return Stream.fromIterable([
    RunStartedEvent(threadId: threadId, runId: runId),
    RunErrorEvent(message: error),
  ]);
}

// -- Tests -------------------------------------------------------------------

void main() {
  late MockSoliplexApi mockApi;
  late MockAgUiStreamClient mockStream;
  late SoliplexPlugin plugin;

  setUpAll(() {
    registerFallbackValue(
      const SimpleRunAgentInput(threadId: '', runId: ''),
    );
  });

  setUp(() {
    mockApi = MockSoliplexApi();
    mockStream = MockAgUiStreamClient();
    plugin = SoliplexPlugin(
      connections: {
        _server: SoliplexConnection(
          api: mockApi,
          streamClient: mockStream,
        ),
      },
    );
  });

  Future<Object?> call(
    String name,
    Map<String, Object?> args,
  ) {
    final fn = plugin.functions.firstWhere(
      (f) => f.schema.name == name,
    );
    return fn.handler(args);
  }

  Map<String, dynamic> decodeJson(Object? result) =>
      json.decode(result! as String) as Map<String, dynamic>;

  List<dynamic> decodeJsonList(Object? result) =>
      json.decode(result! as String) as List<dynamic>;

  // -- Discovery -------------------------------------------------------------

  group('soliplex_list_servers', () {
    test('returns all server IDs', () async {
      final result = decodeJsonList(
        await call('soliplex_list_servers', {}),
      );
      expect(result, [
        {'id': _server},
      ]);
    });

    test('returns multiple servers', () {
      final multi = SoliplexPlugin(
        connections: {
          'alpha': SoliplexConnection(
            api: mockApi,
            streamClient: mockStream,
          ),
          'beta': SoliplexConnection(
            api: mockApi,
            streamClient: mockStream,
          ),
        },
      );
      final fn = multi.functions.firstWhere(
        (f) => f.schema.name == 'soliplex_list_servers',
      );
      expect(
        fn.handler({}),
        completion(
          equals(
            json.encode([
              {'id': 'alpha'},
              {'id': 'beta'},
            ]),
          ),
        ),
      );
    });
  });

  // -- Rooms -----------------------------------------------------------------

  group('soliplex_list_rooms', () {
    test('returns rooms from API', () async {
      when(() => mockApi.getRooms()).thenAnswer(
        (_) async => [
          const Room(id: 'r1', name: 'Room 1', description: 'Desc'),
        ],
      );

      final result = decodeJsonList(
        await call('soliplex_list_rooms', {'server': _server}),
      );
      expect(result, [
        {'id': 'r1', 'name': 'Room 1', 'description': 'Desc'},
      ]);
    });

    test('throws on unknown server', () {
      expect(
        () => call('soliplex_list_rooms', {'server': 'nope'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Unknown server "nope"'),
          ),
        ),
      );
    });
  });

  group('soliplex_get_room', () {
    test('returns room config', () async {
      when(() => mockApi.getRoom(_roomId)).thenAnswer(
        (_) async => const Room(
          id: _roomId,
          name: 'Test Room',
          description: 'A test',
          welcomeMessage: 'Hi',
          suggestions: ['Try this'],
          tools: {
            'tool1': RoomTool(
              kind: 'test',
              name: 'tool1',
              description: 'A tool',
            ),
          },
          skills: {
            'skill1': RoomSkill(
              name: 'skill1',
              description: 'A skill',
            ),
          },
          enableAttachments: true,
          allowMcp: true,
        ),
      );

      final result = decodeJson(
        await call('soliplex_get_room', {
          'server': _server,
          'room_id': _roomId,
        }),
      );
      expect(result['id'], _roomId);
      expect(result['name'], 'Test Room');
      expect(result['tools'], ['tool1']);
      expect(result['skills'], ['skill1']);
      expect(result['enable_attachments'], true);
      expect(result['allow_mcp'], true);
    });
  });

  // -- Documents -------------------------------------------------------------

  group('soliplex_get_documents', () {
    test('returns document metadata', () async {
      when(() => mockApi.getDocuments(_roomId)).thenAnswer(
        (_) async => [
          const RagDocument(id: 'd1', title: 'Doc 1'),
        ],
      );

      final result = decodeJsonList(
        await call('soliplex_get_documents', {
          'server': _server,
          'room_id': _roomId,
        }),
      );
      expect(result, hasLength(1));
      final doc = result[0] as Map<String, dynamic>;
      expect(doc['id'], 'd1');
      expect(doc['title'], 'Doc 1');
    });
  });

  group('soliplex_get_chunk', () {
    test('returns chunk info', () async {
      when(
        () => mockApi.getChunkVisualization(_roomId, 'c1'),
      ).thenAnswer(
        (_) async => ChunkVisualization(
          chunkId: 'c1',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1', 'img2'],
        ),
      );

      final result = decodeJson(
        await call('soliplex_get_chunk', {
          'server': _server,
          'room_id': _roomId,
          'chunk_id': 'c1',
        }),
      );
      expect(result['chunk_id'], 'c1');
      expect(result['page_count'], 2);
    });
  });

  // -- Threads ---------------------------------------------------------------

  group('soliplex_list_threads', () {
    test('returns thread list', () async {
      when(() => mockApi.getThreads(_roomId)).thenAnswer(
        (_) async => [
          ThreadInfo(
            id: 't1',
            roomId: _roomId,
            name: 'Chat 1',
            createdAt: _now,
          ),
        ],
      );

      final result = decodeJsonList(
        await call('soliplex_list_threads', {
          'server': _server,
          'room_id': _roomId,
        }),
      );
      expect(result, hasLength(1));
      final thread = result[0] as Map<String, dynamic>;
      expect(thread['id'], 't1');
      expect(thread['name'], 'Chat 1');
    });
  });

  // -- Conversation ----------------------------------------------------------

  group('soliplex_new_thread', () {
    setUp(() {
      when(
        () => mockApi.createThread(_roomId, name: any(named: 'name')),
      ).thenAnswer(
        (_) async => (_threadInfo(), <String, dynamic>{'rag': true}),
      );
    });

    test('creates thread, streams SSE, returns response', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream());

      final result = decodeJson(
        await call('soliplex_new_thread', {
          'server': _server,
          'room_id': _roomId,
          'message': 'Hello',
        }),
      );

      expect(result['thread_id'], _threadId);
      expect(result['run_id'], _runId);
      expect(result['response'], 'Hello world');

      // Verify the endpoint.
      final captured = verify(
        () => mockStream.runAgent(captureAny(), captureAny()),
      ).captured;
      expect(
        captured[0],
        'rooms/$_roomId/agui/$_threadId/$_runId',
      );

      // Verify input has the user message.
      final input = captured[1] as SimpleRunAgentInput;
      expect(input.messages, hasLength(1));
      expect(input.messages![0], isA<UserMessage>());
      expect(
        (input.messages![0] as UserMessage).content,
        'Hello',
      );
      expect(input.state, {'rag': true});
    });

    test('accumulates multi-delta response', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(deltas: ['Hello ', 'world', '!']),
      );

      final result = decodeJson(
        await call('soliplex_new_thread', {
          'server': _server,
          'room_id': _roomId,
          'message': 'Hi',
        }),
      );
      expect(result['response'], 'Hello world!');
    });

    test('captures StateSnapshotEvent', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(
          stateSnapshot: {'updated': 'state'},
        ),
      );

      await call('soliplex_new_thread', {
        'server': _server,
        'room_id': _roomId,
        'message': 'Hi',
      });

      // Verify by doing a reply — should use updated state.
      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'run-2'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream(runId: 'run-2'));

      await call('soliplex_reply_thread', {
        'server': _server,
        'room_id': _roomId,
        'thread_id': _threadId,
        'message': 'Follow up',
      });

      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      // The second call's input should have the updated state.
      final input = captured.last as SimpleRunAgentInput;
      expect(input.state, {'updated': 'state'});
    });

    test('throws on RunErrorEvent', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _errorStream());

      expect(
        () => call('soliplex_new_thread', {
          'server': _server,
          'room_id': _roomId,
          'message': 'Hi',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('something broke'),
          ),
        ),
      );
    });
  });

  group('soliplex_reply_thread', () {
    test('sends full history after new_thread', () async {
      // First: new_thread.
      when(
        () => mockApi.createThread(_roomId, name: any(named: 'name')),
      ).thenAnswer(
        (_) async => (_threadInfo(), <String, dynamic>{}),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(deltas: ['First response']),
      );

      await call('soliplex_new_thread', {
        'server': _server,
        'room_id': _roomId,
        'message': 'Turn 1',
      });

      // Then: reply_thread.
      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'run-2'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(
          runId: 'run-2',
          deltas: ['Second response'],
        ),
      );

      final result = decodeJson(
        await call('soliplex_reply_thread', {
          'server': _server,
          'room_id': _roomId,
          'thread_id': _threadId,
          'message': 'Turn 2',
        }),
      );

      expect(result['response'], 'Second response');
      expect(result['run_id'], 'run-2');

      // Verify the input contains full message history.
      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      // user_1 + assistant_1 + user_2 = 3 messages
      expect(input.messages, hasLength(3));
      expect(input.messages![0], isA<UserMessage>());
      expect(input.messages![1], isA<AssistantMessage>());
      expect(input.messages![2], isA<UserMessage>());
      expect(
        (input.messages![2] as UserMessage).content,
        'Turn 2',
      );
    });

    test('works without prior state', () async {
      when(() => mockApi.createRun(_roomId, 'orphan-thread')).thenAnswer(
        (_) async => RunInfo(
          id: 'run-x',
          threadId: 'orphan-thread',
          createdAt: _now,
        ),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(
          threadId: 'orphan-thread',
          runId: 'run-x',
        ),
      );

      final result = decodeJson(
        await call('soliplex_reply_thread', {
          'server': _server,
          'room_id': _roomId,
          'thread_id': 'orphan-thread',
          'message': 'Hi',
        }),
      );
      expect(result['response'], 'Hello world');

      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      // Only the single user message.
      expect(input.messages, hasLength(1));
    });

    test('accumulates across three turns', () async {
      // Turn 1: new_thread.
      when(
        () => mockApi.createThread(_roomId, name: any(named: 'name')),
      ).thenAnswer(
        (_) async => (_threadInfo(), <String, dynamic>{}),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream(deltas: ['R1']));

      await call('soliplex_new_thread', {
        'server': _server,
        'room_id': _roomId,
        'message': 'M1',
      });

      // Turn 2: reply.
      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'run-2'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(runId: 'run-2', deltas: ['R2']),
      );

      await call('soliplex_reply_thread', {
        'server': _server,
        'room_id': _roomId,
        'thread_id': _threadId,
        'message': 'M2',
      });

      // Turn 3: reply.
      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'run-3'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(runId: 'run-3', deltas: ['R3']),
      );

      await call('soliplex_reply_thread', {
        'server': _server,
        'room_id': _roomId,
        'thread_id': _threadId,
        'message': 'M3',
      });

      // Verify turn 3 input has 5 messages:
      // user_1, assistant_1, user_2, assistant_2, user_3
      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      expect(input.messages, hasLength(5));
    });
  });

  // -- Uploads ---------------------------------------------------------------

  group('soliplex_upload_file', () {
    test('uploads to room', () async {
      when(
        () => mockApi.uploadFileToRoom(
          _roomId,
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async {});

      final result = decodeJson(
        await call('soliplex_upload_file', {
          'server': _server,
          'room_id': _roomId,
          'filename': 'test.txt',
          'content': 'hello',
        }),
      );
      expect(result['uploaded'], 'test.txt');
      expect(result['room_id'], _roomId);
    });
  });

  group('soliplex_upload_to_thread', () {
    test('uploads to thread', () async {
      when(
        () => mockApi.uploadFileToThread(
          _roomId,
          _threadId,
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async {});

      final result = decodeJson(
        await call('soliplex_upload_to_thread', {
          'server': _server,
          'room_id': _roomId,
          'thread_id': _threadId,
          'filename': 'test.txt',
          'content': 'hello',
        }),
      );
      expect(result['uploaded'], 'test.txt');
      expect(result['thread_id'], _threadId);
    });
  });

  // -- MCP -------------------------------------------------------------------

  group('soliplex_get_mcp_token', () {
    test('returns token', () async {
      when(() => mockApi.getMcpToken(_roomId)).thenAnswer(
        (_) async => 'tok-123',
      );

      final result = decodeJson(
        await call('soliplex_get_mcp_token', {
          'server': _server,
          'room_id': _roomId,
        }),
      );
      expect(result['mcp_token'], 'tok-123');
    });
  });

  // -- Error handling --------------------------------------------------------

  group('error handling', () {
    test('unknown server throws ArgumentError', () {
      expect(
        () => call('soliplex_list_rooms', {'server': 'missing'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Unknown server "missing"'),
              contains(_server),
            ),
          ),
        ),
      );
    });
  });

  // -- Child inheritance -----------------------------------------------------

  group('createChildInstance', () {
    test('returns plugin with fresh state', () async {
      // Seed parent with a thread.
      when(
        () => mockApi.createThread(_roomId, name: any(named: 'name')),
      ).thenAnswer(
        (_) async => (_threadInfo(), <String, dynamic>{}),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream());

      await call('soliplex_new_thread', {
        'server': _server,
        'room_id': _roomId,
        'message': 'Hi',
      });

      // Create child.
      final child = plugin.createChildInstance()! as SoliplexPlugin;

      // Child's reply_thread on the same thread_id should not have
      // the parent's history — it creates fresh state.
      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'child-run'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(runId: 'child-run'),
      );

      final childFn = child.functions.firstWhere(
        (f) => f.schema.name == 'soliplex_reply_thread',
      );
      await childFn.handler({
        'server': _server,
        'room_id': _roomId,
        'thread_id': _threadId,
        'message': 'From child',
      });

      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      // Child only has its own message, not parent's history.
      expect(input.messages, hasLength(1));
    });
  });

  // -- Plugin metadata -------------------------------------------------------

  group('plugin metadata', () {
    test('namespace is soliplex', () {
      expect(plugin.namespace, 'soliplex');
    });

    test('has 11 functions', () {
      expect(plugin.functions, hasLength(11));
    });

    test('systemPromptContext mentions all servers', () {
      expect(
        plugin.systemPromptContext,
        contains(_server),
      );
    });
  });
}
