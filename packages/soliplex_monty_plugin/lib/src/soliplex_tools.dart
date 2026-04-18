import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart'
    show SessionContext, ThreadKey;
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/src/soliplex_connection.dart';
import 'package:soliplex_monty_plugin/src/soliplex_tool.dart';

/// Per-thread conversation state managed internally.
class _ThreadState {
  _ThreadState({
    required this.threadId,
    Object? state,
  }) : state = state ?? <String, dynamic>{};

  final String threadId;
  final List<Message> messages = [];
  Object? state;
  int _counter = 0;

  String nextId(String prefix) => '${prefix}_${++_counter}';
}

/// Helper to build the system prompt context for Soliplex tools.
String buildSoliplexSystemPrompt(Map<String, SoliplexConnection> connections) {
  final servers =
      connections.values.map((c) => '${c.alias} (${c.serverId})').join(', ');

  return '''
Soliplex connects you to remote servers, each hosting rooms with AI agents
that have RAG access to uploaded documents. Every function requires an
explicit server and room_id — there are no defaults.

Available servers: $servers

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

All functions follow the pattern: soliplex_<action>(server, room_id, ...).''';
}

/// Builds the standard set of Soliplex tools.
List<SoliplexTool> buildSoliplexTools(
  SessionContext ctx,
  Map<String, SoliplexConnection> connections,
) {
  final threadStates = <ThreadKey, _ThreadState>{};

  SoliplexConnection connection(String serverId) {
    final conn = connections[serverId];
    if (conn == null) {
      throw ArgumentError(
        'Unknown server "$serverId". '
        'Available: ${connections.keys.join(', ')}',
      );
    }
    return conn;
  }

  return [
    // -- Server Discovery ----------------------------------------------------
    SoliplexTool(
      name: 'soliplex_list_servers',
      description: 'List all connected Soliplex servers.',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      handler: (args) async => connections.values
          .map(
            (c) => {
              'id': c.serverId,
              'alias': c.alias,
              'url': c.serverUrl,
            },
          )
          .toList(),
    ),

    // -- Rooms ---------------------------------------------------------------
    SoliplexTool(
      name: 'soliplex_list_rooms',
      description: 'List all available rooms on a server.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
        },
        'required': ['server'],
      },
      handler: (args) async {
        final rooms =
            await connection(args['server']! as String).api.getRooms();
        return rooms
            .map(
              (r) => {
                'id': r.id,
                'name': r.name,
                'description': r.description,
              },
            )
            .toList();
      },
    ),

    SoliplexTool(
      name: 'soliplex_get_room',
      description:
          'Get full room configuration: tools, skills, agent, features.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
        },
        'required': ['server', 'room_id'],
      },
      handler: (args) async {
        final conn = connection(args['server']! as String);
        final roomId = args['room_id']! as String;
        final room = await conn.api.getRoom(roomId);
        return {
          'id': room.id,
          'name': room.name,
          'description': room.description,
          'welcome_message': room.welcomeMessage,
          'suggestions': room.suggestions,
          'tools': room.tools.keys.toList(),
          'skills': room.skills.keys.toList(),
          'enable_attachments': room.enableAttachments,
          'allow_mcp': room.allowMcp,
        };
      },
    ),

    // -- Documents -----------------------------------------------------------
    SoliplexTool(
      name: 'soliplex_get_documents',
      description: "List documents in a room's RAG knowledge base (metadata).",
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
        },
        'required': ['server', 'room_id'],
      },
      handler: (args) async {
        final conn = connection(args['server']! as String);
        final roomId = args['room_id']! as String;
        final docs = await conn.api.getDocuments(roomId);
        return docs
            .map(
              (d) => {
                'id': d.id,
                'title': d.title,
                'uri': d.uri,
                'metadata': d.metadata,
              },
            )
            .toList();
      },
    ),

    SoliplexTool(
      name: 'soliplex_get_chunk',
      description: 'Get metadata for a RAG chunk: chunk ID, document URI, '
          'and page count.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
          'chunk_id': {
            'type': 'string',
            'description': 'Chunk ID to visualize.',
          },
        },
        'required': ['server', 'room_id', 'chunk_id'],
      },
      handler: (args) async {
        final conn = connection(args['server']! as String);
        final roomId = args['room_id']! as String;
        final chunkId = args['chunk_id']! as String;
        final chunk = await conn.api.getChunkVisualization(roomId, chunkId);
        return {
          'chunk_id': chunk.chunkId,
          'document_uri': chunk.documentUri,
          'page_count': chunk.imagesBase64.length,
        };
      },
    ),

    // -- Threads -------------------------------------------------------------
    SoliplexTool(
      name: 'soliplex_list_threads',
      description: 'List conversation threads in a room.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
        },
        'required': ['server', 'room_id'],
      },
      handler: (args) async {
        final conn = connection(args['server']! as String);
        final roomId = args['room_id']! as String;
        final threads = await conn.api.getThreads(roomId);
        return threads
            .map(
              (t) => {
                'id': t.id,
                'name': t.name,
                'created_at': t.createdAt.toIso8601String(),
              },
            )
            .toList();
      },
    ),

    // -- Conversation (AG-UI SSE) --------------------------------------------
    SoliplexTool(
      name: 'soliplex_new_thread',
      description: "Start a new conversation with a room's agent. "
          'Creates a thread, sends the message, and returns the '
          "agent's response. The agent has RAG access to the room's "
          'documents.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
          'message': {
            'type': 'string',
            'description': 'User message to send to the agent.',
          },
        },
        'required': ['server', 'room_id', 'message'],
      },
      handler: (args) async {
        final serverId = args['server']! as String;
        final conn = connection(serverId);
        final roomId = args['room_id']! as String;
        final message = args['message']! as String;

        final (threadInfo, aguiState) = await conn.api.createThread(roomId);
        final threadId = threadInfo.id;
        final runId = threadInfo.initialRunId;

        final key = (serverId: serverId, roomId: roomId, threadId: threadId);
        final threadState = _ThreadState(threadId: threadId, state: aguiState);
        threadStates[key] = threadState;

        final userMsg = UserMessage(
          id: threadState.nextId('user'),
          content: message,
        );
        threadState.messages.add(userMsg);

        final input = SimpleRunAgentInput(
          threadId: threadId,
          runId: runId,
          messages: List.unmodifiable(threadState.messages),
          state: threadState.state,
        );
        final endpoint = 'rooms/$roomId/agui/$threadId/$runId';
        final stream = conn.streamClient.runAgent(endpoint, input);
        final responseText = await _consumeStream(stream, threadState);

        return {
          'thread_id': threadId,
          'run_id': runId,
          'response': responseText,
        };
      },
    ),

    SoliplexTool(
      name: 'soliplex_reply_thread',
      description:
          'Continue an existing conversation. Sends a follow-up message '
          'and returns the agent response. Conversation history is '
          'tracked automatically.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
          'thread_id': {
            'type': 'string',
            'description':
                'Thread ID from a previous soliplex_new_thread call.',
          },
          'message': {'type': 'string', 'description': 'User message to send.'},
        },
        'required': ['server', 'room_id', 'thread_id', 'message'],
      },
      handler: (args) async {
        final serverId = args['server']! as String;
        final conn = connection(serverId);
        final roomId = args['room_id']! as String;
        final threadId = args['thread_id']! as String;
        final message = args['message']! as String;

        final key = (serverId: serverId, roomId: roomId, threadId: threadId);
        final threadState = threadStates.putIfAbsent(
          key,
          () => _ThreadState(threadId: threadId),
        );

        final runInfo = await conn.api.createRun(roomId, threadId);
        final runId = runInfo.id;

        final userMsg = UserMessage(
          id: threadState.nextId('user'),
          content: message,
        );
        threadState.messages.add(userMsg);

        final input = SimpleRunAgentInput(
          threadId: threadId,
          runId: runId,
          messages: List.unmodifiable(threadState.messages),
          state: threadState.state,
        );
        final endpoint = 'rooms/$roomId/agui/$threadId/$runId';
        final stream = conn.streamClient.runAgent(endpoint, input);
        final responseText = await _consumeStream(stream, threadState);

        return {
          'thread_id': threadId,
          'run_id': runId,
          'response': responseText,
        };
      },
    ),

    // -- Uploads -------------------------------------------------------------
    SoliplexTool(
      name: 'soliplex_upload_file',
      description: "Upload a file to a room's knowledge base. "
          'Available to all conversations in the room.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
          'filename': {'type': 'string', 'description': 'Filename.'},
          'content': {
            'type': 'string',
            'description': 'File content as text or base64 string.',
          },
          'mime_type': {
            'type': 'string',
            'description': 'MIME type.',
            'default': 'application/octet-stream',
          },
        },
        'required': ['server', 'room_id', 'filename', 'content'],
      },
      handler: (args) async {
        final conn = connection(args['server']! as String);
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
        return {'uploaded': filename, 'room_id': roomId};
      },
    ),

    SoliplexTool(
      name: 'soliplex_upload_to_thread',
      description: 'Upload a file scoped to a specific conversation thread.',
      parameters: {
        'type': 'object',
        'properties': {
          'server': {
            'type': 'string',
            'description':
                "Server ID — use the 'id' field from soliplex_list_servers().",
          },
          'room_id': {'type': 'string', 'description': 'Room ID.'},
          'thread_id': {'type': 'string', 'description': 'Thread ID.'},
          'filename': {'type': 'string', 'description': 'Filename.'},
          'content': {
            'type': 'string',
            'description': 'File content as text or base64 string.',
          },
          'mime_type': {
            'type': 'string',
            'description': 'MIME type.',
            'default': 'application/octet-stream',
          },
        },
        'required': ['server', 'room_id', 'thread_id', 'filename', 'content'],
      },
      handler: (args) async {
        final conn = connection(args['server']! as String);
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
        return {
          'uploaded': filename,
          'room_id': roomId,
          'thread_id': threadId,
        };
      },
    ),
  ];
}

/// Helper to build the introspection tool (help).
SoliplexTool buildHelpTool(List<SoliplexTool> tools) {
  return SoliplexTool(
    name: 'help',
    description: 'Show detailed information about available tools.',
    parameters: {
      'type': 'object',
      'properties': {
        'name': {
          'type': 'string',
          'description': 'Tool name to look up. Omit to list all.',
        },
      },
    },
    handler: (args) async {
      final name = args['name'] as String?;
      if (name == null) {
        final allTools = [
          ...tools.map((t) => {'name': t.name, 'description': t.description}),
          {
            'name': 'help',
            'description': 'Show detailed information about available tools.',
          },
        ];
        return {'tools': allTools};
      }
      final tool = tools.firstWhere(
        (t) => t.name == name,
        orElse: () => throw ArgumentError('Unknown tool: $name'),
      );
      return {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters,
      };
    },
  );
}

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
