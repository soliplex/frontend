import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart'
    show LogManager, LoggerFactory;

import '../../modules/auth/admin_status.dart';
import '../../modules/auth/auth_session.dart';
import '../../modules/auth/server_entry.dart';
import '../../modules/room/agent_runtime_manager.dart';
import '../../modules/room/execution_tracker_extension.dart';
import '../../modules/room/human_approval_extension.dart';
import '../../modules/room/run_registry.dart';
import '../../modules/room/tool_calls_extension.dart';
import '../../modules/room/upload_tracker_registry.dart';

/// Everything the chat screen talks to, answered from memory.
///
/// Mirrors the wiring in `buildStandardKit` — a [ServerEntry] whose
/// connection carries a [SoliplexApi] and an [AgUiStreamClient], the runtime
/// manager, the run and upload registries — with the network replaced by
/// [StaticSoliplexApi] and [ScriptedAgUiStreamClient]. Any request neither
/// stubs reaches [_NoNetworkClient] and throws, naming the request, so a
/// mockup that wanders off the stubbed surface fails visibly rather than
/// hanging on a socket.
class StaticBackend {
  StaticBackend({
    required this.api,
    String serverId = 'https://mock.soliplex.local',
    String alias = 'mock',
    String serverName = 'Mock server',
  }) {
    final client = _NoNetworkClient();
    entry = ServerEntry(
      serverId: serverId,
      alias: alias,
      serverUrl: Uri.parse(serverId),
      auth:
          AuthSession(refreshService: TokenRefreshService(httpClient: client)),
      httpClient: client,
      connection: ServerConnection(
        serverId: serverId,
        api: api,
        agUiStreamClient: ScriptedAgUiStreamClient(api),
      ),
      adminStatus: AdminStatus(api: api, serverId: serverId),
      requiresAuth: false,
      name: serverName,
    );
    servers = Signal<Map<String, ServerEntry>>({serverId: entry});
    runtimeManager = AgentRuntimeManager(
      platform: const NativePlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: LogManager.instance.getLogger('mockup.chat'),
      extensionFactory: () async => [
        ExecutionTrackerExtension(
          logger: LogManager.instance.getLogger('mockup.chat.execution'),
        ),
        ToolCallsExtension(),
        HumanApprovalExtension(),
      ],
      servers: servers,
    );
    registry = RunRegistry(servers: servers);
    uploadRegistry = UploadTrackerRegistry(servers: servers);
  }

  final StaticSoliplexApi api;
  late final ServerEntry entry;
  late final Signal<Map<String, ServerEntry>> servers;
  late final AgentRuntimeManager runtimeManager;
  late final RunRegistry registry;
  late final UploadTrackerRegistry uploadRegistry;

  Future<void> dispose() async {
    await runtimeManager.dispose();
    registry.dispose();
    uploadRegistry.dispose();
    servers.dispose();
  }
}

/// A [SoliplexApi] answered from the maps it is given. The maps are live:
/// creating, renaming or deleting a thread edits them, and a scripted reply
/// appends to a history, so leaving a thread and coming back shows what
/// happened there.
class StaticSoliplexApi extends SoliplexApi {
  StaticSoliplexApi({
    required this.rooms,
    required this.threads,
    required this.histories,
    this.documents = const {},
    this.isAdmin = true,
  }) : super(
          transport: HttpTransport(client: _NoNetworkClient()),
          urlBuilder: UrlBuilder('https://mock.soliplex.local/api/v1'),
        );

  final List<Room> rooms;

  /// Room id → its threads.
  final Map<String, List<ThreadInfo>> threads;

  /// Thread id → its history.
  final Map<String, ThreadHistory> histories;

  /// Room id → its RAG corpus.
  final Map<String, List<RagDocument>> documents;

  /// Room id → files uploaded to the room; thread id → files uploaded to the
  /// thread. Both feed the composer's attached-files panel.
  final Map<String, List<FileUpload>> roomUploads = {};
  final Map<String, List<FileUpload>> threadUploads = {};

  /// Whether upload controls show; the app gates them on admin status.
  final bool isAdmin;

  var _sequence = 0;
  String nextId(String prefix) => '$prefix-${++_sequence}';

  @override
  Future<List<Room>> getRooms({CancelToken? cancelToken}) async => rooms;

  @override
  Future<Room> getRoom(String roomId, {CancelToken? cancelToken}) async =>
      rooms.firstWhere((r) => r.id == roomId);

  @override
  Future<Map<String, RoomStats>> getRoomsStats({
    CancelToken? cancelToken,
  }) async =>
      {
        for (final room in rooms)
          room.id: RoomStats(
            lastActivity: threads[room.id]
                ?.map((t) => t.lastActivity ?? t.createdAt)
                .fold<DateTime?>(
                  null,
                  (a, b) => a == null || b.isAfter(a) ? b : a,
                ),
          ),
      };

  @override
  Future<List<ThreadInfo>> getThreads(
    String roomId, {
    CancelToken? cancelToken,
  }) async =>
      List.of(threads[roomId] ?? const []);

  @override
  Future<ThreadHistory> getThreadHistory(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async =>
      histories[threadId] ?? ThreadHistory(messages: const []);

  @override
  Future<List<RagDocument>> getDocuments(
    String roomId, {
    CancelToken? cancelToken,
  }) async =>
      documents[roomId] ?? const [];

  @override
  Future<List<FileUpload>> getRoomUploads(
    String roomId, {
    CancelToken? cancelToken,
  }) async =>
      roomUploads[roomId] ?? const [];

  @override
  Future<List<FileUpload>> getThreadUploads(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async =>
      threadUploads[threadId] ?? const [];

  @override
  Future<void> uploadFileToRoom(
    String roomId, {
    required String filename,
    required Stream<List<int>> Function() openStream,
    required int contentLength,
    String mimeType = 'application/octet-stream',
    Object? webFileBlob,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await _accept(openStream, contentLength, onProgress);
    (roomUploads[roomId] ??= []).add(_uploaded(filename));
  }

  @override
  Future<void> uploadFileToThread(
    String roomId,
    String threadId, {
    required String filename,
    required Stream<List<int>> Function() openStream,
    required int contentLength,
    String mimeType = 'application/octet-stream',
    Object? webFileBlob,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await _accept(openStream, contentLength, onProgress);
    (threadUploads[threadId] ??= []).add(_uploaded(filename));
  }

  /// Drains the file with a little progress so the composer's upload row
  /// gets to show its pending state.
  Future<void> _accept(
    Stream<List<int>> Function() openStream,
    int contentLength,
    void Function(int sent, int total)? onProgress,
  ) async {
    var sent = 0;
    await for (final chunk in openStream()) {
      sent += chunk.length;
      onProgress?.call(sent, contentLength);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  FileUpload _uploaded(String filename) => FileUpload(
        filename: filename,
        url: Uri.parse('https://mock.soliplex.local/uploads/$filename'),
      );

  @override
  Future<List<WorkdirFile>> getRunWorkdirFiles(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async =>
      const [];

  @override
  Future<(ThreadInfo, Map<String, dynamic>)> createThread(
    String roomId, {
    String? name,
    CancelToken? cancelToken,
  }) async {
    final thread = ThreadInfo(
      id: nextId('thread'),
      roomId: roomId,
      name: name ?? '',
      createdAt: DateTime.now().toUtc(),
    );
    (threads[roomId] ??= []).insert(0, thread);
    histories[thread.id] = ThreadHistory(messages: const []);
    return (thread, const <String, dynamic>{});
  }

  @override
  Future<void> deleteThread(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    threads[roomId]?.removeWhere((t) => t.id == threadId);
    histories.remove(threadId);
  }

  @override
  Future<void> updateThreadMetadata(
    String roomId,
    String threadId, {
    String? name,
    String? description,
    CancelToken? cancelToken,
  }) async {
    final list = threads[roomId];
    if (list == null) return;
    final i = list.indexWhere((t) => t.id == threadId);
    if (i < 0) return;
    list[i] = list[i].copyWith(name: name, description: description);
  }

  @override
  Future<RunInfo> createRun(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async =>
      RunInfo(
        id: nextId('run'),
        threadId: threadId,
        createdAt: DateTime.now().toUtc(),
      );

  @override
  Future<RunFeedback?> getRunFeedback(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async =>
      null;

  @override
  Future<void> submitFeedback(
    String roomId,
    String threadId,
    String runId,
    FeedbackType feedback, {
    String? reason,
    CancelToken? cancelToken,
  }) async {}

  @override
  Future<String> getMcpToken(String roomId, {CancelToken? cancelToken}) async =>
      'mock-mcp-token';

  @override
  Future<bool> getIsAdminUser({CancelToken? cancelToken}) async => isAdmin;
}

/// Streams a canned reply to whatever was sent, word by word, then records
/// the exchange in the [StaticSoliplexApi]'s history so it survives leaving
/// the thread.
///
/// Override [replyTo] to script something specific.
class ScriptedAgUiStreamClient extends AgUiStreamClient {
  ScriptedAgUiStreamClient(
    this.api, {
    this.replyTo = defaultReply,
    this.wordDelay = const Duration(milliseconds: 40),
  }) : super(
          httpTransport: HttpTransport(client: _NoNetworkClient()),
          urlBuilder: UrlBuilder('https://mock.soliplex.local/api/v1'),
        );

  final StaticSoliplexApi api;
  final String Function(String prompt) replyTo;
  final Duration wordDelay;

  static String defaultReply(String prompt) => '''
You said: *${prompt.trim()}*

This reply is scripted by `ScriptedAgUiStreamClient` — nothing left the
device. A few things it can render:

- **Bold**, *italics*, `inline code`
- A list, like this one

```dart
final answer = 42;
```
''';

  @override
  Stream<DecodeOutcome> runAgent(
    String endpoint,
    SimpleRunAgentInput input, {
    CancelToken? cancelToken,
    ResumePolicy? resumePolicy,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async* {
    final threadId = input.threadId ?? '';
    final runId = input.runId ?? api.nextId('run');
    final last = input.messages?.lastOrNull;
    final prompt = switch (last) {
      UserMessage(messageContent: TextContent(:final text)) => text,
      _ => '',
    };
    final reply = replyTo(prompt);
    final messageId = api.nextId('assistant');

    DecodedEvent wrap(BaseEvent e) => DecodedEvent(e, e.toJson());

    yield wrap(RunStartedEvent(threadId: threadId, runId: runId));
    yield wrap(TextMessageStartEvent(messageId: messageId));
    for (final word in reply.split(RegExp(r'(?<= )'))) {
      if (cancelToken?.isCancelled ?? false) return;
      await Future<void>.delayed(wordDelay);
      yield wrap(TextMessageContentEvent(messageId: messageId, delta: word));
    }
    yield wrap(TextMessageEndEvent(messageId: messageId));
    yield wrap(RunFinishedEvent(threadId: threadId, runId: runId));

    final now = DateTime.now().toUtc();
    final history =
        api.histories[threadId] ?? ThreadHistory(messages: const []);
    api.histories[threadId] = ThreadHistory(
      messages: [
        ...history.messages,
        TextMessage(
          id: last?.id ?? api.nextId('user'),
          user: ChatUser.user,
          createdAt: now,
          text: prompt,
        ),
        TextMessage(
          id: messageId,
          user: ChatUser.assistant,
          createdAt: now,
          text: reply,
        ),
      ],
      messageStates: history.messageStates,
      runs: history.runs,
    );
  }
}

/// Fails every request by name. The stubs above never reach it; a code path
/// that does is one the mockup has not stubbed yet.
class _NoNetworkClient extends SoliplexHttpClient {
  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    CancelToken? cancelToken,
  }) =>
      throw StateError('Mockup backend: unstubbed $method ${uri.path}');

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) =>
      throw StateError('Mockup backend: unstubbed stream $method ${uri.path}');

  @override
  void close() {}
}
