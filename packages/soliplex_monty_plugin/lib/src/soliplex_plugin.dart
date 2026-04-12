import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'soliplex_connection.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Per-thread conversation state managed internally by the plugin.
///
/// Python never sees this — the plugin tracks message history and AG-UI state
/// so that reply calls can send the full context on each turn.
class _ThreadState {
  _ThreadState({
    required this.threadId,
    dynamic state,
  }) : state = state ?? <String, dynamic>{};

  final String threadId;
  final List<Message> messages = [];
  dynamic state;
  int _counter = 0;

  String nextId(String prefix) => '${prefix}_${++_counter}';
}

/// A [MontyPlugin] that bridges sandboxed Python to the Soliplex server API.
///
/// Every function requires an explicit `server` (first) and `room_id` (second)
/// — there are no defaults. The plugin supports multiple simultaneous server
/// connections.
///
/// Conversations are managed via two functions:
/// - `soliplex_new_thread` — create a thread and send the first message
/// - `soliplex_reply_thread` — continue an existing thread
///
/// Both stream AG-UI events via SSE, accumulate the response, and return the
/// agent's reply. Message history and AG-UI state are tracked internally per
/// thread.
///
/// ```monty
/// servers = soliplex_list_servers()
/// rooms = soliplex_list_rooms("my-server")
/// result = soliplex_new_thread("my-server", "my-room", "Hello!")
/// tid = result["thread_id"]
/// follow_up = soliplex_reply_thread(
///     "my-server", "my-room", tid, "Tell me more",
/// )
/// ```
class SoliplexPlugin extends MontyPlugin {
  /// Creates a [SoliplexPlugin].
  ///
  /// [connections] maps server IDs to their [SoliplexConnection] instances.
  SoliplexPlugin({
    required Map<String, SoliplexConnection> connections,
  }) : _connections = Map.unmodifiable(connections);

  final Map<String, SoliplexConnection> _connections;

  /// Per-thread conversation state (message history + AG-UI state).
  final Map<String, _ThreadState> _threadStates = {};

  @override
  String get namespace => 'soliplex';

  @override
  String? get systemPromptContext => '''
Soliplex connects you to remote servers, each hosting rooms with AI agents
that have RAG access to uploaded documents. Every function requires an
explicit server and room_id — there are no defaults.

Available servers: ${_connections.keys.join(', ')}

Workflow: discover servers → pick a room → converse with its agent.

Discovery:
  soliplex_list_servers()                      — all connected servers
  soliplex_list_rooms(server)                  — rooms on a server
  soliplex_get_room(server, room_id)           — room config, tools, skills

Documents:
  soliplex_get_documents(server, room_id)      — list RAG documents (metadata)
  soliplex_get_chunk(server, room_id, chunk_id) — visualize a RAG chunk

Conversation:
  soliplex_new_thread(server, room_id, message)
      — start a new conversation, returns thread_id and agent response
  soliplex_reply_thread(server, room_id, thread_id, message)
      — continue an existing conversation

  The agent on the server has RAG access to the room's documents.
  Conversation history is tracked automatically per thread.

Threads:
  soliplex_list_threads(server, room_id)       — list existing threads

Uploads:
  soliplex_upload_file(server, room_id, filename, content)
      — upload to room knowledge base (available to all threads)
  soliplex_upload_to_thread(server, room_id, thread_id, filename, content)
      — upload scoped to a single thread

MCP:
  soliplex_get_mcp_token(server, room_id)      — get MCP access token

Use help("soliplex_new_thread") for detailed parameter info on any function.''';

  @override
  List<HostFunction> get functions => [
        _listServers,
        _listRooms,
        _getRoom,
        _getDocuments,
        _getChunk,
        _listThreads,
        _newThread,
        _replyThread,
        _uploadToRoom,
        _uploadToThread,
        _getMcpToken,
      ];

  // -- Helpers ---------------------------------------------------------------

  SoliplexConnection _connection(String serverId) {
    final conn = _connections[serverId];
    if (conn == null) {
      throw ArgumentError(
        'Unknown server "$serverId". '
        'Available: ${_connections.keys.join(', ')}',
      );
    }
    return conn;
  }

  /// Consumes an AG-UI event stream, accumulating the assistant's response.
  ///
  /// Updates [threadState] with the assistant's message and any state snapshots
  /// received during the stream.
  Future<String> _consumeStream(
    Stream<BaseEvent> stream,
    _ThreadState threadState,
  ) async {
    final buffer = StringBuffer();
    String? lastMessageId;

    await for (final event in stream) {
      switch (event) {
        case TextMessageStartEvent(:final messageId):
          lastMessageId = messageId;
        case TextMessageContentEvent(:final delta):
          buffer.write(delta);
        case StateSnapshotEvent(:final snapshot):
          threadState.state = snapshot;
        case RunErrorEvent(:final message):
          throw Exception('Agent run failed: $message');
        case TextMessageEndEvent():
        case RunStartedEvent():
        case RunFinishedEvent():
        case _:
          break;
      }
    }

    final responseText = buffer.toString();

    threadState.messages.add(
      AssistantMessage(
        id: lastMessageId ?? threadState.nextId('assistant'),
        content: responseText,
      ),
    );

    return responseText;
  }

  // -- Server Discovery ------------------------------------------------------

  HostFunction get _listServers => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_list_servers',
          description: 'List all connected Soliplex servers.',
        ),
        handler: (args) async => jsonEncode(
          _connections.keys.map((id) => {'id': id}).toList(),
        ),
      );

  // -- Rooms -----------------------------------------------------------------

  HostFunction get _listRooms => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_list_rooms',
          description: 'List all available rooms on a server.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
          ],
        ),
        handler: (args) async {
          final rooms =
              await _connection(args['server']! as String).api.getRooms();
          return jsonEncode(
            rooms
                .map(
                  (r) => {
                    'id': r.id,
                    'name': r.name,
                    'description': r.description,
                  },
                )
                .toList(),
          );
        },
      );

  HostFunction get _getRoom => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_get_room',
          description:
              'Get full room configuration: tools, skills, agent, features.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final room = await conn.api.getRoom(roomId);
          return jsonEncode({
            'id': room.id,
            'name': room.name,
            'description': room.description,
            'welcome_message': room.welcomeMessage,
            'suggestions': room.suggestions,
            'tools': room.tools.keys.toList(),
            'skills': room.skills.keys.toList(),
            'enable_attachments': room.enableAttachments,
            'allow_mcp': room.allowMcp,
          });
        },
      );

  // -- Documents -------------------------------------------------------------

  HostFunction get _getDocuments => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_get_documents',
          description:
              "List documents in a room's RAG knowledge base (metadata).",
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final docs = await conn.api.getDocuments(roomId);
          return jsonEncode(
            docs
                .map(
                  (d) => {
                    'id': d.id,
                    'title': d.title,
                    'uri': d.uri,
                    'metadata': d.metadata,
                  },
                )
                .toList(),
          );
        },
      );

  HostFunction get _getChunk => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_get_chunk',
          description: 'Get page images for a RAG chunk with text highlighted. '
              'Returns base64-encoded images.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
            HostParam(
              name: 'chunk_id',
              type: HostParamType.string,
              description: 'Chunk ID to visualize.',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final chunkId = args['chunk_id']! as String;
          final chunk = await conn.api.getChunkVisualization(roomId, chunkId);
          return jsonEncode({
            'chunk_id': chunk.chunkId,
            'document_uri': chunk.documentUri,
            'page_count': chunk.imagesBase64.length,
          });
        },
      );

  // -- Threads ---------------------------------------------------------------

  HostFunction get _listThreads => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_list_threads',
          description: 'List conversation threads in a room.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final threads = await conn.api.getThreads(roomId);
          return jsonEncode(
            threads
                .map(
                  (t) => {
                    'id': t.id,
                    'name': t.name,
                    'created_at': t.createdAt.toIso8601String(),
                  },
                )
                .toList(),
          );
        },
      );

  // -- Conversation (AG-UI SSE) ----------------------------------------------

  HostFunction get _newThread => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_new_thread',
          description: "Start a new conversation with a room's agent. "
              'Creates a thread, sends the message, and returns the '
              "agent's response. The agent has RAG access to the room's "
              'documents.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
            HostParam(
              name: 'message',
              type: HostParamType.string,
              description: 'User message to send to the agent.',
            ),
          ],
        ),
        handler: _handleNewThread,
      );

  Future<Object?> _handleNewThread(Map<String, Object?> args) async {
    final conn = _connection(args['server']! as String);
    final roomId = args['room_id']! as String;
    final message = args['message']! as String;

    // Create thread (includes an initial run).
    final (threadInfo, aguiState) = await conn.api.createThread(roomId);
    final threadId = threadInfo.id;
    final runId = threadInfo.initialRunId;

    // Initialize thread state.
    final threadState = _ThreadState(threadId: threadId, state: aguiState);
    _threadStates[threadId] = threadState;

    // Build user message and add to history.
    final userMsg = UserMessage(
      id: threadState.nextId('user'),
      content: message,
    );
    threadState.messages.add(userMsg);

    // Execute the run via SSE.
    final input = SimpleRunAgentInput(
      threadId: threadId,
      runId: runId,
      messages: List.unmodifiable(threadState.messages),
      state: threadState.state,
    );
    final endpoint = 'rooms/$roomId/agui/$threadId/$runId';
    final stream = conn.streamClient.runAgent(endpoint, input);
    final responseText = await _consumeStream(stream, threadState);

    return jsonEncode({
      'thread_id': threadId,
      'run_id': runId,
      'response': responseText,
    });
  }

  HostFunction get _replyThread => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_reply_thread',
          description:
              'Continue an existing conversation. Sends a follow-up message '
              'and returns the agent response. Conversation history is '
              'tracked automatically.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
            HostParam(
              name: 'thread_id',
              type: HostParamType.string,
              description:
                  'Thread ID from a previous soliplex_new_thread call.',
            ),
            HostParam(
              name: 'message',
              type: HostParamType.string,
              description: 'User message to send.',
            ),
          ],
        ),
        handler: _handleReplyThread,
      );

  Future<Object?> _handleReplyThread(Map<String, Object?> args) async {
    final conn = _connection(args['server']! as String);
    final roomId = args['room_id']! as String;
    final threadId = args['thread_id']! as String;
    final message = args['message']! as String;

    // Look up or create thread state.
    final threadState = _threadStates.putIfAbsent(
      threadId,
      () => _ThreadState(threadId: threadId),
    );

    // Create a new run for this turn.
    final runInfo = await conn.api.createRun(roomId, threadId);
    final runId = runInfo.id;

    // Append user message to history.
    final userMsg = UserMessage(
      id: threadState.nextId('user'),
      content: message,
    );
    threadState.messages.add(userMsg);

    // Execute the run via SSE.
    final input = SimpleRunAgentInput(
      threadId: threadId,
      runId: runId,
      messages: List.unmodifiable(threadState.messages),
      state: threadState.state,
    );
    final endpoint = 'rooms/$roomId/agui/$threadId/$runId';
    final stream = conn.streamClient.runAgent(endpoint, input);
    final responseText = await _consumeStream(stream, threadState);

    return jsonEncode({
      'thread_id': threadId,
      'run_id': runId,
      'response': responseText,
    });
  }

  // -- Uploads ---------------------------------------------------------------

  HostFunction get _uploadToRoom => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_upload_file',
          description: "Upload a file to a room's knowledge base. "
              'Available to all conversations in the room.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
            HostParam(
              name: 'filename',
              type: HostParamType.string,
              description: 'Filename (e.g. "report.pdf").',
            ),
            HostParam(
              name: 'content',
              type: HostParamType.string,
              description: 'File content as text or base64-encoded string.',
            ),
            HostParam(
              name: 'mime_type',
              type: HostParamType.string,
              isRequired: false,
              description: 'MIME type. Defaults to application/octet-stream.',
              defaultValue: 'application/octet-stream',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final filename = args['filename']! as String;
          final content = args['content']! as String;
          final mimeType =
              args['mime_type'] as String? ?? 'application/octet-stream';
          await conn.api.uploadFileToRoom(
            roomId,
            filename: filename,
            fileBytes: utf8.encode(content),
            mimeType: mimeType,
          );
          return jsonEncode({'uploaded': filename, 'room_id': roomId});
        },
      );

  HostFunction get _uploadToThread => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_upload_to_thread',
          description:
              'Upload a file scoped to a specific conversation thread.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
            HostParam(
              name: 'thread_id',
              type: HostParamType.string,
              description: 'Thread ID.',
            ),
            HostParam(
              name: 'filename',
              type: HostParamType.string,
              description: 'Filename.',
            ),
            HostParam(
              name: 'content',
              type: HostParamType.string,
              description: 'File content as text or base64-encoded string.',
            ),
            HostParam(
              name: 'mime_type',
              type: HostParamType.string,
              isRequired: false,
              description: 'MIME type. Defaults to application/octet-stream.',
              defaultValue: 'application/octet-stream',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final threadId = args['thread_id']! as String;
          final filename = args['filename']! as String;
          final content = args['content']! as String;
          final mimeType =
              args['mime_type'] as String? ?? 'application/octet-stream';
          await conn.api.uploadFileToThread(
            roomId,
            threadId,
            filename: filename,
            fileBytes: utf8.encode(content),
            mimeType: mimeType,
          );
          return jsonEncode({
            'uploaded': filename,
            'room_id': roomId,
            'thread_id': threadId,
          });
        },
      );

  // -- MCP -------------------------------------------------------------------

  HostFunction get _getMcpToken => HostFunction(
        schema: const HostFunctionSchema(
          name: 'soliplex_get_mcp_token',
          description: 'Get an MCP access token for a room. '
              'Only works for rooms with allow_mcp enabled.',
          params: [
            HostParam(
              name: 'server',
              type: HostParamType.string,
              description: 'Server ID.',
            ),
            HostParam(
              name: 'room_id',
              type: HostParamType.string,
              description: 'Room ID.',
            ),
          ],
        ),
        handler: (args) async {
          final conn = _connection(args['server']! as String);
          final roomId = args['room_id']! as String;
          final token = await conn.api.getMcpToken(roomId);
          return jsonEncode({'room_id': roomId, 'mcp_token': token});
        },
      );

  // -- Child Inheritance -----------------------------------------------------

  @override
  MontyPlugin? createChildInstance({ChildSpawnContext? context}) {
    return SoliplexPlugin(connections: _connections);
  }

  // -- Lifecycle -------------------------------------------------------------

  @override
  Future<void> onDispose() async {
    await super.onDispose();
    for (final conn in _connections.values) {
      conn.api.close();
      conn.streamClient.close();
    }
  }
}
