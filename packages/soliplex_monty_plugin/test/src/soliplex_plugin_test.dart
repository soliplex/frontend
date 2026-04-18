import 'package:dart_monty/dart_monty.dart' as dm;
import 'package:dart_monty/dart_monty_bridge.dart'
    show HostFunction, HostFunctionSchema;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class MockAgentSession extends Mock implements dm.AgentSession {}

// -- Fixtures ----------------------------------------------------------------

const _serverId = 'test-server';
const _alias = 'test';
const _serverUrl = 'https://test.example.com';
const _roomId = 'test-room';
const _threadId = 'thread-1';
const _runId = 'run-1';
final _now = DateTime(2026);
const _ctx = SessionContext(serverId: _serverId, roomId: _roomId);

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
  late List<SoliplexTool> tools;
  late Map<String, SoliplexConnection> connections;

  setUpAll(() {
    registerFallbackValue(
      const SimpleRunAgentInput(threadId: '', runId: ''),
    );
    registerFallbackValue(
      HostFunction(
        schema: const HostFunctionSchema(name: '_fallback', description: ''),
        handler: (_) async => null,
      ),
    );
  });

  setUp(() {
    mockApi = MockSoliplexApi();
    mockStream = MockAgUiStreamClient();
    connections = {
      _serverId: SoliplexConnection(
        serverId: _serverId,
        alias: _alias,
        serverUrl: _serverUrl,
        api: mockApi,
        streamClient: mockStream,
      ),
    };
    tools = buildSoliplexTools(_ctx, () => connections);
  });

  Future<Object?> call(
    String name,
    Map<String, Object?> args,
  ) {
    final tool = tools.firstWhere((t) => t.name == name);
    return tool.handler(args);
  }

  // -- Discovery -------------------------------------------------------------

  group('soliplex_list_servers', () {
    test('returns all server IDs', () async {
      final result =
          (await call('soliplex_list_servers', {}))! as List<dynamic>;
      expect(result, hasLength(1));
      final server = result[0] as Map<String, dynamic>;
      expect(server['id'], _serverId);
      expect(server['alias'], _alias);
      expect(server['url'], _serverUrl);
    });

    test('returns multiple servers', () async {
      final mockApi2 = MockSoliplexApi();
      final mockStream2 = MockAgUiStreamClient();
      final multiConnections = {
        'alpha': SoliplexConnection(
          serverId: 'alpha',
          alias: 'Alpha',
          serverUrl: 'https://alpha.example.com',
          api: mockApi,
          streamClient: mockStream,
        ),
        'beta': SoliplexConnection(
          serverId: 'beta',
          alias: 'Beta',
          serverUrl: 'https://beta.example.com',
          api: mockApi2,
          streamClient: mockStream2,
        ),
      };
      final multiTools = buildSoliplexTools(_ctx, () => multiConnections);
      final tool =
          multiTools.firstWhere((t) => t.name == 'soliplex_list_servers');
      final result = (await tool.handler({}))! as List<dynamic>;
      final ids =
          result.cast<Map<String, dynamic>>().map((e) => e['id']).toList();
      expect(ids, containsAll(['alpha', 'beta']));
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

      final result = (await call('soliplex_list_rooms', {'server': _serverId}))!
          as List<dynamic>;
      final room = result[0] as Map<String, dynamic>;
      expect(room['id'], 'r1');
      expect(room['name'], 'Room 1');
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

      final result = (await call('soliplex_get_room', {
        'server': _serverId,
        'room_id': _roomId,
      }))! as Map<String, dynamic>;
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

      final result = (await call('soliplex_get_documents', {
        'server': _serverId,
        'room_id': _roomId,
      }))! as List<dynamic>;
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

      final result = (await call('soliplex_get_chunk', {
        'server': _serverId,
        'room_id': _roomId,
        'chunk_id': 'c1',
      }))! as Map<String, dynamic>;
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

      final result = (await call('soliplex_list_threads', {
        'server': _serverId,
        'room_id': _roomId,
      }))! as List<dynamic>;
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

      final result = (await call('soliplex_new_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'message': 'Hello',
      }))! as Map<String, dynamic>;

      expect(result['thread_id'], _threadId);
      expect(result['run_id'], _runId);
      expect(result['response'], 'Hello world');

      final captured = verify(
        () => mockStream.runAgent(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], 'rooms/$_roomId/agui/$_threadId/$_runId');

      final input = captured[1] as SimpleRunAgentInput;
      expect(input.messages, hasLength(1));
      expect(input.messages![0], isA<UserMessage>());
      expect((input.messages![0] as UserMessage).content, 'Hello');
      expect(input.state, {'rag': true});
    });

    test('accumulates multi-delta response', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(deltas: ['Hello ', 'world', '!']),
      );

      final result = (await call('soliplex_new_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'message': 'Hi',
      }))! as Map<String, dynamic>;
      expect(result['response'], 'Hello world!');
    });

    test('captures StateSnapshotEvent', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(stateSnapshot: {'updated': 'state'}),
      );

      await call('soliplex_new_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'message': 'Hi',
      });

      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'run-2'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream(runId: 'run-2'));

      await call('soliplex_reply_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'thread_id': _threadId,
        'message': 'Follow up',
      });

      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      expect(input.state, {'updated': 'state'});
    });

    test('throws on RunErrorEvent', () async {
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _errorStream());

      expect(
        () => call('soliplex_new_thread', {
          'server': _serverId,
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
      when(
        () => mockApi.createThread(_roomId, name: any(named: 'name')),
      ).thenAnswer(
        (_) async => (_threadInfo(), <String, dynamic>{}),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream(deltas: ['First response']));

      await call('soliplex_new_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'message': 'Turn 1',
      });

      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'run-2'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer(
        (_) => _happyStream(runId: 'run-2', deltas: ['Second response']),
      );

      final result = (await call('soliplex_reply_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'thread_id': _threadId,
        'message': 'Turn 2',
      }))! as Map<String, dynamic>;

      expect(result['response'], 'Second response');
      expect(result['run_id'], 'run-2');

      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      expect(input.messages, hasLength(3));
      expect(input.messages![0], isA<UserMessage>());
      expect(input.messages![1], isA<AssistantMessage>());
      expect(input.messages![2], isA<UserMessage>());
      expect((input.messages![2] as UserMessage).content, 'Turn 2');
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
        (_) => _happyStream(threadId: 'orphan-thread', runId: 'run-x'),
      );

      final result = (await call('soliplex_reply_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'thread_id': 'orphan-thread',
        'message': 'Hi',
      }))! as Map<String, dynamic>;
      expect(result['response'], 'Hello world');

      final captured = verify(
        () => mockStream.runAgent(any(), captureAny()),
      ).captured;
      final input = captured.last as SimpleRunAgentInput;
      expect(input.messages, hasLength(1));
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

      final result = (await call('soliplex_upload_file', {
        'server': _serverId,
        'room_id': _roomId,
        'filename': 'test.txt',
        'content': 'hello',
      }))! as Map<String, dynamic>;
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

      final result = (await call('soliplex_upload_to_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'thread_id': _threadId,
        'filename': 'test.txt',
        'content': 'hello',
      }))! as Map<String, dynamic>;
      expect(result['uploaded'], 'test.txt');
      expect(result['thread_id'], _threadId);
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
              contains(_serverId),
            ),
          ),
        ),
      );
    });
  });

  // -- Fresh instance --------------------------------------------------------

  group('fresh tools instance', () {
    test('new buildSoliplexTools call has no shared thread history', () async {
      when(
        () => mockApi.createThread(_roomId, name: any(named: 'name')),
      ).thenAnswer(
        (_) async => (_threadInfo(), <String, dynamic>{}),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream());

      await call('soliplex_new_thread', {
        'server': _serverId,
        'room_id': _roomId,
        'message': 'Hi',
      });

      // Fresh tools instance — no shared thread state with parent.
      final childTools = buildSoliplexTools(_ctx, () => connections);
      when(() => mockApi.createRun(_roomId, _threadId)).thenAnswer(
        (_) async => _runInfo(id: 'child-run'),
      );
      when(
        () => mockStream.runAgent(any(), any()),
      ).thenAnswer((_) => _happyStream(runId: 'child-run'));

      final childTool =
          childTools.firstWhere((t) => t.name == 'soliplex_reply_thread');
      await childTool.handler({
        'server': _serverId,
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

  // -- System prompt ---------------------------------------------------------

  group('buildSoliplexSystemPrompt', () {
    test('mentions server alias and id', () {
      final prompt = buildSoliplexSystemPrompt(connections);
      expect(prompt, contains(_alias));
      expect(prompt, contains(_serverId));
    });
  });

  // -- Tool count ------------------------------------------------------------

  group('tool count', () {
    test('buildSoliplexTools returns 10 tools', () {
      expect(tools, hasLength(10));
    });
  });

  // -- Duplicate registration ------------------------------------------------

  group('MontyScriptEnvironment duplicate registration', () {
    SoliplexTool makeTool(String name) => SoliplexTool(
          name: name,
          description: 'Test tool',
          parameters: {
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          handler: (args) async => null,
        );

    MockAgentSession mockSession({List<String> existingNames = const []}) {
      final session = MockAgentSession();
      when(() => session.schemas).thenReturn([
        for (final n in existingNames)
          HostFunctionSchema(name: n, description: 'built-in'),
      ]);
      when(() => session.register(any())).thenReturn(null);
      return session;
    }

    test(
      'throws StateError when two tools in the list share the same name',
      () {
        final session = mockSession();
        expect(
          () => MontyScriptEnvironment.forTest(
            session,
            tools: [makeTool('foo'), makeTool('foo')],
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('"foo"'),
            ),
          ),
        );
      },
    );

    test(
      'throws StateError when a tool name conflicts with a bridge built-in',
      () {
        // Simulate the dart_monty bridge having already registered 'help'.
        final session = mockSession(existingNames: ['help']);
        expect(
          () => MontyScriptEnvironment.forTest(
            session,
            tools: [makeTool('help')],
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('"help"'),
            ),
          ),
        );
      },
    );

    test('succeeds when all names are unique and conflict-free', () {
      final session = mockSession(existingNames: ['built_in_foo']);
      expect(
        () => MontyScriptEnvironment.forTest(
          session,
          tools: [makeTool('my_tool'), makeTool('other_tool')],
        ),
        returnsNormally,
      );
    });
  });
}
