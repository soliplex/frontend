import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// A [MontyPlugin] that bridges sandboxed Python to the Soliplex server API.
///
/// Exposes servers, rooms, threads, runs, documents, and uploads as host
/// functions callable from Python code running in a Monty sandbox.
///
/// Based on the consumer-skills reference from soliplex/soliplex. The plugin
/// models conversations via the AG-UI protocol: create thread → create run →
/// execute run (SSE) → accumulate messages.
///
/// Supports multiple simultaneous server connections. Each function accepts
/// an optional `server` parameter; when omitted, [defaultServerId] is used.
///
/// ```monty
/// help()                                   # see all available functions
/// servers = soliplex_list_servers()
/// rooms = soliplex_list_rooms()
/// room = soliplex_get_room("my-room")
/// docs = soliplex_get_documents("my-room")
/// thread = soliplex_create_thread("my-room")
/// response = soliplex_converse("my-room", "What can you help me with?")
/// ```
class SoliplexPlugin extends MontyPlugin {
  /// Creates a [SoliplexPlugin].
  ///
  /// [connections] maps server IDs to their [SoliplexApi] instances.
  /// [defaultServerId] is used when Python calls omit the `server` parameter.
  /// [defaultRoomId] is used when Python calls omit the `room_id` parameter.
  SoliplexPlugin({
    required Map<String, SoliplexApi> connections,
    required this.defaultServerId,
    this.defaultRoomId,
  }) : _connections = Map.unmodifiable(connections);

  final Map<String, SoliplexApi> _connections;

  /// Server used when `server` parameter is omitted.
  final String defaultServerId;

  /// Room used when `room_id` parameter is omitted.
  final String? defaultRoomId;

  @override
  String get namespace => 'soliplex';

  @override
  String? get systemPromptContext => '''
Soliplex server integration. Query rooms, documents, threads, and have
conversations with server-side agents that have RAG context.

Connected servers: ${_connections.keys.join(', ')} (default: $defaultServerId)
${defaultRoomId != null ? 'Default room: $defaultRoomId' : ''}

Key functions:
- soliplex_converse(room_id, message) — have a conversation with a room's agent
- soliplex_list_rooms() — discover available rooms
- soliplex_get_documents(room_id) — list RAG documents in a room
- soliplex_upload_file(room_id, filename, content) — upload a file to a room
- help("soliplex_converse") — detailed parameter info''';

  @override
  List<HostFunction> get functions => [
    _listServers,
    _listRooms,
    _getRoom,
    _getDocuments,
    _getChunk,
    _listThreads,
    _createThread,
    _deleteThread,
    _converse,
    _uploadToRoom,
    _uploadToThread,
    _getMcpToken,
  ];

  // -- Helpers ---------------------------------------------------------------

  SoliplexApi _api([String? serverId]) {
    final id = serverId ?? defaultServerId;
    final api = _connections[id];
    if (api == null) {
      throw ArgumentError(
        'Unknown server "$id". '
        'Available: ${_connections.keys.join(', ')}',
      );
    }
    return api;
  }

  String _requireRoomId(Map<String, Object?> args) {
    final roomId = args['room_id'] as String? ?? defaultRoomId;
    if (roomId == null) {
      throw ArgumentError(
        'room_id is required (no default room configured)',
      );
    }
    return roomId;
  }

  // -- Server Discovery ------------------------------------------------------

  HostFunction get _listServers => HostFunction(
    schema: const HostFunctionSchema(
      name: 'soliplex_list_servers',
      description: 'List all connected Soliplex servers.',
    ),
    handler: (args) async => jsonEncode(
      _connections.keys
          .map(
            (id) => {'id': id, 'is_default': id == defaultServerId},
          )
          .toList(),
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
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final rooms = await _api(args['server'] as String?).getRooms();
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
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final room = await _api(args['server'] as String?).getRoom(roomId);
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
      description: "List documents in a room's RAG knowledge base (metadata).",
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final docs = await _api(args['server'] as String?).getDocuments(roomId);
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
      description:
          'Get page images for a RAG chunk with text highlighted. '
          'Returns base64-encoded images.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'chunk_id',
          type: HostParamType.string,
          description: 'Chunk ID to visualize.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final chunkId = args['chunk_id']! as String;
      final chunk = await _api(args['server'] as String?)
          .getChunkVisualization(roomId, chunkId);
      return jsonEncode({
        'chunk_id': chunk.chunkId,
        'document_uri': chunk.documentUri,
        'page_count': chunk.imagesBase64.length,
        // Return image count, not full base64 by default (too large).
        // Use soliplex_get_chunk_image for specific pages.
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
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final threads =
          await _api(args['server'] as String?).getThreads(roomId);
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

  HostFunction get _createThread => HostFunction(
    schema: const HostFunctionSchema(
      name: 'soliplex_create_thread',
      description:
          'Create a new conversation thread in a room. '
          'Returns thread_id, initial_run_id, and agui_state needed '
          'to execute the first run.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'name',
          type: HostParamType.string,
          isRequired: false,
          description: 'Thread name. Defaults to "New Thread".',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final name = args['name'] as String?;
      final (threadInfo, aguiState) = await _api(args['server'] as String?)
          .createThread(roomId, name: name);
      return jsonEncode({
        'thread_id': threadInfo.id,
        'room_id': threadInfo.roomId,
        'initial_run_id': threadInfo.initialRunId,
        'name': threadInfo.name,
        'created_at': threadInfo.createdAt.toIso8601String(),
        'agui_state': aguiState,
      });
    },
  );

  HostFunction get _deleteThread => HostFunction(
    schema: const HostFunctionSchema(
      name: 'soliplex_delete_thread',
      description: 'Delete a conversation thread.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'thread_id',
          type: HostParamType.string,
          description: 'Thread ID to delete.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final threadId = args['thread_id']! as String;
      await _api(args['server'] as String?).deleteThread(roomId, threadId);
      return jsonEncode({'deleted': threadId});
    },
  );

  // -- Conversation (AG-UI) --------------------------------------------------

  HostFunction get _converse => HostFunction(
    schema: const HostFunctionSchema(
      name: 'soliplex_converse',
      description:
          "Have a conversation with a room's agent. Creates a thread, "
          "sends a message, and returns the agent's response. "
          "The agent has RAG access to the room's documents. "
          'For multi-turn conversations, pass the thread_id from a '
          'previous call and include message_history.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'message',
          type: HostParamType.string,
          description: 'User message to send to the agent.',
        ),
        HostParam(
          name: 'thread_id',
          type: HostParamType.string,
          isRequired: false,
          description:
              'Existing thread ID for follow-up messages. '
              'Omit to start a new conversation.',
        ),
        HostParam(
          name: 'message_history',
          type: HostParamType.list,
          isRequired: false,
          description:
              'Prior messages as list of {role, content} dicts. '
              'Required for multi-turn conversations — the server does '
              'not maintain history across runs.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: _handleConverse,
  );

  // TODO(runyaga): Implement full AG-UI conversation flow with:
  // - SSE streaming (execute run)
  // - Client-side tool calling (dispatch to local host functions)
  // - AG-UI state pass-through (STATE_SNAPSHOT, STATE_DELTA)
  // - Event streaming to bridge events
  // This is substantial — shares machinery with ClawSessionExtension.
  Future<Object?> _handleConverse(Map<String, Object?> args) async {
    final roomId = _requireRoomId(args);
    // message and message_history will be used when SSE execution is wired.
    final _ = args['message']! as String;
    final existingThreadId = args['thread_id'] as String?;
    final api = _api(args['server'] as String?);

    // Create or reuse thread.
    String threadId;
    if (existingThreadId != null) {
      threadId = existingThreadId;
    } else {
      final (threadInfo, _) = await api.createThread(roomId);
      threadId = threadInfo.id;
    }

    // Create a new run.
    final runInfo = await api.createRun(roomId, threadId);

    return jsonEncode({
      'thread_id': threadId,
      'run_id': runInfo.id,
      'status': 'created',
      'note': 'SSE execution not yet implemented — use thread_id and '
          'run_id with the AG-UI stream client directly.',
    });
  }

  // -- Uploads ---------------------------------------------------------------

  HostFunction get _uploadToRoom => HostFunction(
    schema: const HostFunctionSchema(
      name: 'soliplex_upload_file',
      description:
          "Upload a file to a room's knowledge base. "
          'Available to all conversations in the room.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
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
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final filename = args['filename']! as String;
      final content = args['content']! as String;
      final mimeType = args['mime_type'] as String? ?? 'application/octet-stream';
      await _api(args['server'] as String?).uploadFileToRoom(
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
      description: 'Upload a file scoped to a specific conversation thread.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
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
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final threadId = args['thread_id']! as String;
      final filename = args['filename']! as String;
      final content = args['content']! as String;
      final mimeType = args['mime_type'] as String? ?? 'application/octet-stream';
      await _api(args['server'] as String?).uploadFileToThread(
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
      description:
          'Get an MCP access token for a room. '
          'Only works for rooms with allow_mcp enabled.',
      params: [
        HostParam(
          name: 'room_id',
          type: HostParamType.string,
          isRequired: false,
          description: 'Room ID. Omit for default room.',
        ),
        HostParam(
          name: 'server',
          type: HostParamType.string,
          isRequired: false,
          description: 'Server ID. Omit for default server.',
        ),
      ],
    ),
    handler: (args) async {
      final roomId = _requireRoomId(args);
      final token =
          await _api(args['server'] as String?).getMcpToken(roomId);
      return jsonEncode({'room_id': roomId, 'mcp_token': token});
    },
  );

  // -- Child Inheritance -----------------------------------------------------

  @override
  MontyPlugin? createChildInstance({ChildSpawnContext? context}) {
    return SoliplexPlugin(
      connections: _connections,
      defaultServerId: defaultServerId,
      defaultRoomId: defaultRoomId,
    );
  }
}
