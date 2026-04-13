import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart' as dm;
import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_monty_plugin/src/soliplex_connection.dart';

// ---------------------------------------------------------------------------
// Thread state
// ---------------------------------------------------------------------------

/// Per-thread conversation state tracked by [MontyScriptEnvironment].
///
/// Stores message history and AG-UI state so that reply calls can send full
/// context on each turn without requiring the caller to manage history.
class _ThreadState {
  _ThreadState({required this.threadId, dynamic state})
      : state = state ?? <String, dynamic>{};

  final String threadId;
  final List<Message> messages = [];
  dynamic state;
  int _counter = 0;

  String nextId(String prefix) => '${prefix}_${++_counter}';
}

// ---------------------------------------------------------------------------
// MontyScriptEnvironment
// ---------------------------------------------------------------------------

/// Concrete [ScriptEnvironment] backed by a [dm.AgentSession].
///
/// Registers Soliplex operations directly as [dm.HostFunction]s on the
/// bridge, then projects the bridge's schema registry to [ClientTool]s
/// visible to the server-side LLM.  An `execute_python` tool is also
/// exposed for general-purpose Python scripting.
///
/// ```dart
/// final env = MontyScriptEnvironment(
///   connections: {'demo': myConnection},
/// );
/// ```
class MontyScriptEnvironment implements ScriptEnvironment {
  /// Creates a [MontyScriptEnvironment] with the given server [connections].
  ///
  /// [connections] are used to build Soliplex host functions registered
  /// directly on the dart_monty bridge.
  /// [os] is an optional OS provider for the Python interpreter.
  MontyScriptEnvironment({
    required Map<String, SoliplexConnection> connections,
    dm.OsProvider? os,
  })  : _connections = Map.unmodifiable(connections),
        _montySession = dm.AgentSession(os: os) {
    _registerSoliplexFunctions();
  }

  /// Creates a [MontyScriptEnvironment] with an explicit [session].
  ///
  /// Only for testing. Avoids loading the Python runtime.
  @visibleForTesting
  MontyScriptEnvironment.forTest(dm.AgentSession session)
      : _connections = const {},
        _montySession = session;

  final Map<String, SoliplexConnection> _connections;
  final dm.AgentSession _montySession;

  final Signal<ScriptingState> _stateSignal = signal(ScriptingState.idle);
  bool _disposed = false;

  /// Direct handler lookup — avoids routing Dart invocations through Python.
  final Map<String, dm.HostFunctionHandler> _handlers = {};

  /// Serialises concurrent `execute()` calls on the dart_monty bridge.
  ///
  /// A single `AgentSession` owns one Python interpreter (Dart Isolate on FFI,
  /// Web Worker on WASM). Concurrent `execute()` calls on the same session
  /// interleave variable mutations inside that interpreter. The mutex ensures
  /// only one `execute()` runs at a time so Python state is never stomped by a
  /// racing call.
  final Mutex _executeMutex = Mutex();

  /// Per-thread conversation state for multi-turn Soliplex conversations.
  final Map<String, _ThreadState> _threadStates = {};

  // Lazily built: execute_python + all registered host function schemas.
  late final List<ClientTool> _tools = [
    _buildExecutePythonTool(),
    ..._montySession.schemas
        .where((s) => !s.name.startsWith('_'))
        .map(_projectToClientTool),
  ];

  @override
  List<ClientTool> get tools => _tools;

  @override
  ReadonlySignal<ScriptingState> get scriptingState => _stateSignal.readonly();

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSignal.set(ScriptingState.disposed);
    unawaited(_montySession.dispose());
  }

  // ---------------------------------------------------------------------------
  // ClientTool projection
  // ---------------------------------------------------------------------------

  /// Projects a [dm.HostFunctionSchema] to a [ClientTool] that invokes the
  /// registered Dart handler directly (no Python hop).
  ClientTool _projectToClientTool(dm.HostFunctionSchema schema) {
    return ClientTool(
      definition: Tool(
        name: schema.name,
        description: schema.description,
        parameters: Map<String, Object>.from(schema.toJsonSchema()),
      ),
      executor: (toolCall, context) async {
        if (_disposed) {
          throw StateError('MontyScriptEnvironment has been disposed');
        }
        if (context.cancelToken.isCancelled) return '';

        final rawArgs = toolCall.arguments;
        final args = rawArgs.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(rawArgs) as Map<String, dynamic>)
                .cast<String, Object?>();

        _stateSignal.set(ScriptingState.executing);
        try {
          final result = await _handlers[schema.name]!(args);
          return switch (result) {
            null => '',
            final String s => s,
            _ => jsonEncode(result),
          };
        } finally {
          if (!_disposed) _stateSignal.set(ScriptingState.idle);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // execute_python tool
  // ---------------------------------------------------------------------------

  ClientTool _buildExecutePythonTool() {
    return ClientTool(
      definition: const Tool(
        name: 'execute_python',
        description: 'Execute Python code in a sandboxed interpreter. '
            'Variables persist across calls. '
            'Returns the last expression value as a string.',
        parameters: {
          'type': 'object',
          'properties': {
            'code': {
              'type': 'string',
              'description': 'Python code to execute.',
            },
          },
          'required': ['code'],
        },
      ),
      executor: _executePython,
    );
  }

  Future<String> _executePython(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    if (_disposed) throw StateError('MontyScriptEnvironment has been disposed');

    final rawArgs = toolCall.arguments;
    final args = (rawArgs.isEmpty ? <String, dynamic>{} : jsonDecode(rawArgs))
        as Map<String, dynamic>;
    final code = args['code'] as String? ?? '';

    if (context.cancelToken.isCancelled) return '';

    _stateSignal.set(ScriptingState.executing);
    try {
      final result = await _executeMutex.protect(
        () => _montySession.execute(code),
      );

      if (result.error != null) {
        throw Exception('Python error: ${result.error!.message}');
      }

      return result.value?.dartValue?.toString() ?? '';
    } finally {
      if (!_disposed) {
        _stateSignal.set(ScriptingState.idle);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Soliplex host function registration
  // ---------------------------------------------------------------------------

  void _registerSoliplexFunctions() {
    _register(
      dm.HostFunction(
        schema: const dm.HostFunctionSchema(
          name: 'soliplex_list_servers',
          description: 'List all connected Soliplex servers.',
        ),
        handler: (_) async => jsonEncode(
          _connections.keys.map((id) => {'id': id}).toList(),
        ),
      ),
    );

    _register(
      dm.HostFunction(
        schema: const dm.HostFunctionSchema(
          name: 'soliplex_list_rooms',
          description: 'List all available rooms on a server.',
          params: [
            dm.HostParam(
              name: 'server',
              type: dm.HostParamType.string,
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
      ),
    );

    _register(
      dm.HostFunction(
        schema: const dm.HostFunctionSchema(
          name: 'soliplex_list_threads',
          description: 'List conversation threads in a room.',
          params: [
            dm.HostParam(
              name: 'server',
              type: dm.HostParamType.string,
              description: 'Server ID.',
            ),
            dm.HostParam(
              name: 'room_id',
              type: dm.HostParamType.string,
              description: 'Room ID.',
            ),
          ],
        ),
        handler: (args) async {
          final threads = await _connection(args['server']! as String)
              .api
              .getThreads(args['room_id']! as String);
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
      ),
    );

    _register(
      dm.HostFunction(
        schema: const dm.HostFunctionSchema(
          name: 'soliplex_new_thread',
          description: "Start a new conversation with a room's agent. "
              'Creates a thread, sends the message, and returns the '
              "agent's reply. The agent has RAG access to the room's "
              'documents.',
          params: [
            dm.HostParam(
              name: 'server',
              type: dm.HostParamType.string,
              description: 'Server ID.',
            ),
            dm.HostParam(
              name: 'room_id',
              type: dm.HostParamType.string,
              description: 'Room ID.',
            ),
            dm.HostParam(
              name: 'message',
              type: dm.HostParamType.string,
              description: 'User message to send to the agent.',
            ),
          ],
        ),
        handler: _handleNewThread,
      ),
    );

    _register(
      dm.HostFunction(
        schema: const dm.HostFunctionSchema(
          name: 'soliplex_reply_thread',
          description: 'Continue an existing conversation. Sends a follow-up '
              'message and returns the agent reply. Conversation history is '
              'tracked automatically.',
          params: [
            dm.HostParam(
              name: 'server',
              type: dm.HostParamType.string,
              description: 'Server ID.',
            ),
            dm.HostParam(
              name: 'room_id',
              type: dm.HostParamType.string,
              description: 'Room ID.',
            ),
            dm.HostParam(
              name: 'thread_id',
              type: dm.HostParamType.string,
              description:
                  'Thread ID from a previous soliplex_new_thread call.',
            ),
            dm.HostParam(
              name: 'message',
              type: dm.HostParamType.string,
              description: 'User message to send.',
            ),
          ],
        ),
        handler: _handleReplyThread,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Conversation handlers
  // ---------------------------------------------------------------------------

  Future<Object?> _handleNewThread(Map<String, Object?> args) async {
    final conn = _connection(args['server']! as String);
    final roomId = args['room_id']! as String;
    final message = args['message']! as String;

    final (threadInfo, aguiState) = await conn.api.createThread(roomId);
    final threadId = threadInfo.id;
    final runId = threadInfo.initialRunId;

    final threadState = _ThreadState(threadId: threadId, state: aguiState);
    _threadStates[threadId] = threadState;

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

    return jsonEncode({
      'thread_id': threadId,
      'run_id': runId,
      'response': responseText,
    });
  }

  Future<Object?> _handleReplyThread(Map<String, Object?> args) async {
    final conn = _connection(args['server']! as String);
    final roomId = args['room_id']! as String;
    final threadId = args['thread_id']! as String;
    final message = args['message']! as String;

    final threadState = _threadStates.putIfAbsent(
      threadId,
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

    return jsonEncode({
      'thread_id': threadId,
      'run_id': runId,
      'response': responseText,
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _register(dm.HostFunction fn) {
    _handlers[fn.schema.name] = fn.handler;
    _montySession.register(fn);
  }

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
}
