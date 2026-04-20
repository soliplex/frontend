import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/application/agui_event_processor.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/backend_version_info.dart';
import 'package:soliplex_client/src/domain/chunk_visualization.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/feedback_type.dart';
import 'package:soliplex_client/src/domain/message_state.dart';
import 'package:soliplex_client/src/domain/quiz.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/run_info.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_info.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/multipart_encoder.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';

/// API client for Soliplex backend CRUD operations.
///
/// Provides methods for managing rooms, threads, and runs.
/// Built on top of [HttpTransport] for JSON handling and error mapping.
///
/// Example:
/// ```dart
/// final api = SoliplexApi(
///   transport: HttpTransport(client: DartHttpClient()),
///   urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
/// );
///
/// // List rooms
/// final rooms = await api.getRooms();
///
/// // Create a thread
/// final thread = await api.createThread('room-123');
/// print('Created thread: ${thread.id}');
///
/// api.close();
/// ```
class SoliplexApi {
  /// Creates an API client with the given [transport] and [urlBuilder].
  ///
  /// Parameters:
  /// - [transport]: HTTP transport for making requests
  /// - [urlBuilder]: URL builder configured with the API base URL
  /// - [onWarning]: Optional callback for warning messages (e.g., partial
  ///   failures during history loading). If not provided, warnings are silent.
  SoliplexApi({
    required HttpTransport transport,
    required UrlBuilder urlBuilder,
    void Function(String message)? onWarning,
  }) : _transport = transport,
       _urlBuilder = urlBuilder,
       _onWarning = onWarning;

  final HttpTransport _transport;
  final UrlBuilder _urlBuilder;
  final void Function(String message)? _onWarning;

  /// Maximum number of runs to cache. Covers ~5-10 threads of history.
  static const _maxCacheSize = 100;

  /// LRU cache for run events. Completed runs are immutable, so safe to cache.
  /// Uses insertion order - oldest entries are at the front.
  final _runEventsCache = <String, List<Map<String, dynamic>>>{};

  String _runCacheKey(String threadId, String runId) => '$threadId:$runId';

  /// Adds to cache with LRU eviction.
  void _cacheRunEvents(String key, List<Map<String, dynamic>> events) {
    // Remove if exists (to update position for LRU)
    _runEventsCache.remove(key);

    // Evict oldest entries if at capacity
    while (_runEventsCache.length >= _maxCacheSize) {
      _runEventsCache.remove(_runEventsCache.keys.first);
    }

    _runEventsCache[key] = events;
  }

  /// Gets from cache and updates LRU position.
  List<Map<String, dynamic>>? _getCachedRunEvents(String key) {
    final events = _runEventsCache.remove(key);
    if (events != null) {
      _runEventsCache[key] = events; // Re-add to move to end (most recent)
    }
    return events;
  }

  // ============================================================
  // Rooms
  // ============================================================

  /// Lists all available rooms.
  ///
  /// Returns a list of [Room] objects.
  ///
  /// The backend returns rooms as a map keyed by room ID. This method
  /// converts the map to a list of Room objects.
  ///
  /// Throws:
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<Room>> getRooms({CancelToken? cancelToken}) async {
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(path: 'rooms'),
      cancelToken: cancelToken,
    );
    // Backend returns a map of room_id -> room object
    // Skip malformed entries so one bad room doesn't break the list
    final rooms = <Room>[];
    for (final entry in response.entries) {
      try {
        rooms.add(roomFromJson(entry.value as Map<String, dynamic>));
      } catch (e) {
        developer.log(
          'Malformed room ignored (${entry.key}): $e',
          name: 'soliplex_client.api',
          level: 900,
        );
      }
    }
    return rooms;
  }

  /// Gets a room by ID.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  ///
  /// Returns the [Room] with the given ID.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] is empty
  /// - [NotFoundException] if room not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<Room> getRoom(String roomId, {CancelToken? cancelToken}) async {
    _requireNonEmpty(roomId, 'roomId');

    return _transport.request<Room>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId]),
      cancelToken: cancelToken,
      fromJson: roomFromJson,
    );
  }

  /// Gets the MCP token for a room.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  ///
  /// Returns the MCP token string.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] is empty
  /// - [NotFoundException] if room not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<String> getMcpToken(String roomId, {CancelToken? cancelToken}) async {
    _requireNonEmpty(roomId, 'roomId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'mcp_token']),
      cancelToken: cancelToken,
    );

    final token = response['mcp_token'] as String?;
    if (token == null) {
      throw FormatException(
        'Response missing "mcp_token" field for room $roomId',
      );
    }
    return token;
  }

  /// Gets documents available for narrowing RAG in a room.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  ///
  /// Returns a list of [RagDocument] objects for the room.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] is empty
  /// - [NotFoundException] if room not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<RagDocument>> getDocuments(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'documents']),
      cancelToken: cancelToken,
    );

    // Backend returns {"document_set": {id: {...}, ...}} - map keyed by doc ID
    final documentSet = response['document_set'] as Map<String, dynamic>?;
    if (documentSet == null || documentSet.isEmpty) {
      return [];
    }
    // Skip malformed entries so one bad document doesn't break the list
    final docs = <RagDocument>[];
    for (final entry in documentSet.entries) {
      try {
        docs.add(ragDocumentFromJson(entry.value as Map<String, dynamic>));
      } catch (e) {
        developer.log(
          'Malformed document ignored (${entry.key}): $e',
          name: 'soliplex_client.api',
          level: 900,
        );
      }
    }
    return docs;
  }

  // ============================================================
  // Threads
  // ============================================================

  /// Lists all threads in a room.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  ///
  /// Returns a list of [ThreadInfo] objects for the room.
  ///
  /// The backend returns threads wrapped in a {"threads": [...]} object.
  /// This method extracts the threads array.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] is empty
  /// - [NotFoundException] if room not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<ThreadInfo>> getThreads(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui']),
      cancelToken: cancelToken,
    );
    // Backend returns {"threads": [...]} - extract the threads array
    final threads = response['threads'] as List<dynamic>;
    return threads
        .map((e) => threadInfoFromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Gets a thread by ID.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Returns the [ThreadInfo] with the given ID.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [threadId] is empty
  /// - [NotFoundException] if thread not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<ThreadInfo> getThread(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    return _transport.request<ThreadInfo>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui', threadId]),
      cancelToken: cancelToken,
      fromJson: threadInfoFromJson,
    );
  }

  /// Creates a new thread in a room.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  ///
  /// Returns a record of ([ThreadInfo], AG-UI state). The state is extracted
  /// from the initial run's `run_input.state` and contains backend-initialized
  /// feature defaults (e.g., `rag`).
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] is empty
  /// - [NotFoundException] if room not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<(ThreadInfo, Map<String, dynamic>)> createThread(
    String roomId, {
    String? name,
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');

    final response = await _transport.request<Map<String, dynamic>>(
      'POST',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui']),
      body: {
        'metadata': {'name': name ?? 'New Thread', 'description': ''},
      },
      cancelToken: cancelToken,
    );

    // Extract initial run_id and AG-UI state from runs map
    String? initialRunId;
    var aguiState = const <String, dynamic>{};
    final runs = response['runs'] as Map<String, dynamic>?;
    if (runs != null && runs.isNotEmpty) {
      initialRunId = runs.keys.first;
      final run = runs[initialRunId] as Map<String, dynamic>?;
      final runInput = run?['run_input'] as Map<String, dynamic>?;
      final state = runInput?['state'];
      if (state is Map<String, dynamic>) {
        aguiState = state;
      }
    }

    final metadata = response['metadata'] as Map<String, dynamic>?;
    final threadName = metadata?['name'] as String? ?? name ?? '';

    final threadInfo = ThreadInfo(
      id: response['thread_id'] as String,
      roomId: roomId,
      initialRunId: initialRunId ?? '',
      name: threadName,
      createdAt: DateTime.now(),
    );

    return (threadInfo, aguiState);
  }

  /// Deletes a thread.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [threadId] is empty
  /// - [NotFoundException] if thread not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<void> deleteThread(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    await _transport.request<void>(
      'DELETE',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui', threadId]),
      cancelToken: cancelToken,
    );
  }

  /// Updates metadata for a thread.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [threadId] is empty
  /// - [NotFoundException] if thread not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<void> updateThreadMetadata(
    String roomId,
    String threadId, {
    String? name,
    String? description,
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    if (name == null && description == null) {
      throw ArgumentError('At least one metadata field must be provided');
    }

    await _transport.request<void>(
      'POST',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'agui', threadId, 'meta'],
      ),
      body: threadMetadataToJson(name: name, description: description),
      cancelToken: cancelToken,
    );
  }

  // ============================================================
  // Runs
  // ============================================================

  /// Creates a new run in a thread.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Returns a [RunInfo] for the newly created run.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [threadId] is empty
  /// - [NotFoundException] if thread not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<RunInfo> createRun(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    final response = await _transport.request<Map<String, dynamic>>(
      'POST',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui', threadId]),
      body: <String, dynamic>{},
      cancelToken: cancelToken,
    );

    // Normalize response: backend returns run_id, we use id
    return RunInfo(
      id: response['run_id'] as String,
      threadId: threadId,
      createdAt: DateTime.now(),
    );
  }

  /// Gets a run by ID.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  /// - [runId]: The run ID (must not be empty)
  ///
  /// Returns the [RunInfo] with the given ID.
  ///
  /// Throws:
  /// - [ArgumentError] if any ID is empty
  /// - [NotFoundException] if run not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<RunInfo> getRun(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(runId, 'runId');

    return _transport.request<RunInfo>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'agui', threadId, runId],
      ),
      cancelToken: cancelToken,
      fromJson: runInfoFromJson,
    );
  }

  // ============================================================
  // Feedback
  // ============================================================

  /// Submits feedback for a run.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  /// - [runId]: The run ID (must not be empty)
  /// - [feedback]: The feedback type (thumbs up or thumbs down)
  /// - [reason]: Optional reason for the feedback
  ///
  /// Re-submitting replaces any existing feedback for the run (upsert).
  /// The backend responds with HTTP 205 and no body.
  ///
  /// Throws:
  /// - [ArgumentError] if any ID is empty
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<void> submitFeedback(
    String roomId,
    String threadId,
    String runId,
    FeedbackType feedback, {
    String? reason,
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(runId, 'runId');

    await _transport.request<void>(
      'POST',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'agui', threadId, runId, 'feedback'],
      ),
      body: {'feedback': feedback.toJson(), 'reason': reason},
      cancelToken: cancelToken,
    );
  }

  // ============================================================
  // Messages
  // ============================================================

  /// Fetches historical messages for a thread by replaying stored events.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Returns [ThreadHistory] containing messages and AG-UI state reconstructed
  /// from stored events. Messages are ordered chronologically (oldest first)
  /// based on run creation time.
  ///
  /// This method fetches events from individual run endpoints in parallel,
  /// caches them (completed runs are immutable), and replays them to
  /// reconstruct the thread history including citations and other AG-UI state.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [threadId] is empty
  /// - [NotFoundException] if thread not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<ThreadHistory> getThreadHistory(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    // 1. Get thread to list runs
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui', threadId]),
      cancelToken: cancelToken,
    );

    final runs = response['runs'] as Map<String, dynamic>? ?? {};
    if (runs.isEmpty) return ThreadHistory(messages: const []);

    // 2. Get completed run IDs sorted by creation time
    final completedRunIds =
        _sortRunsByCreationTime(runs)
            .where((e) => (e.value as Map<String, dynamic>)['finished'] != null)
            .map((e) => (e.value as Map<String, dynamic>)['run_id'] as String)
            .toList();

    if (completedRunIds.isEmpty) return ThreadHistory(messages: const []);

    // 3. Fetch all run events in parallel (cache handles duplicates)
    final eventFutures = completedRunIds.map((runId) {
      return _fetchRunEvents(
        roomId,
        threadId,
        runId,
        cancelToken: cancelToken,
      ).then((events) => (runId: runId, events: events)).catchError(
        (Object e) {
          // Log transient failure but continue with other runs
          _onWarning?.call('Failed to fetch events for run $runId: $e');
          return (runId: runId, events: <Map<String, dynamic>>[]);
        },
        // Only catch transient errors - show partial results for batch ops:
        // - NetworkException: network blip, retry might succeed
        // - NotFoundException: run deleted between list and fetch (race)
        // Let ApiException propagate - systemic problem (500, 429, 400)
        test: (e) => e is NetworkException || e is NotFoundException,
      );
    });

    final results = await Future.wait(eventFutures);

    // 4. Collect events in run order (results may arrive out of order)
    final runIdToEvents = {for (final r in results) r.runId: r.events};
    final eventsPerRun =
        <({String runId, List<Map<String, dynamic>> events})>[];
    for (final runId in completedRunIds) {
      final runEvents = runIdToEvents[runId] ?? [];
      if (runEvents.isNotEmpty) {
        eventsPerRun.add((runId: runId, events: runEvents));
      }
    }

    // 5. Replay events to reconstruct history (messages + AG-UI state)
    return _replayEventsToHistory(eventsPerRun, threadId);
  }

  /// Fetches events for a single run, using cache for completed runs.
  ///
  /// Returns events including synthetic user message events extracted from
  /// run_input.messages. The backend stores user input separately from
  /// streamed events, so we synthesize TEXT_MESSAGE events for them.
  Future<List<Map<String, dynamic>>> _fetchRunEvents(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async {
    final cacheKey = _runCacheKey(threadId, runId);
    final cached = _getCachedRunEvents(cacheKey);
    if (cached != null) return cached;

    final rawRun = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'agui', threadId, runId],
      ),
      cancelToken: cancelToken,
    );

    // Extract user messages from run_input and create synthetic events
    final userMessageEvents = _extractUserMessageEvents(rawRun);

    final events =
        (rawRun['events'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    // Combine: user message events first, then actual streamed events
    final allEvents = [...userMessageEvents, ...events];
    _cacheRunEvents(cacheKey, allEvents);
    return allEvents;
  }

  /// Extracts the initiating user message from run_input and creates
  /// synthetic events.
  ///
  /// Each run's `run_input.messages` contains the full conversation context,
  /// but only the last user message initiated THIS run. Prior user messages
  /// were already processed in earlier runs.
  List<Map<String, dynamic>> _extractUserMessageEvents(
    Map<String, dynamic> rawRun,
  ) {
    final runInput = rawRun['run_input'] as Map<String, dynamic>?;
    if (runInput == null) return [];

    final messages = runInput['messages'] as List<dynamic>? ?? [];

    // Find the last user message — the one that initiated this run.
    Map<String, dynamic>? lastUserMessage;
    for (var i = messages.length - 1; i >= 0; i--) {
      final raw = messages[i];
      if (raw is! Map<String, dynamic>) continue;
      if ((raw['role'] as String? ?? 'user') == 'user') {
        lastUserMessage = raw;
        break;
      }
    }
    if (lastUserMessage == null) return [];

    final runId = rawRun['run_id'] as String? ?? 'unknown';
    final id = lastUserMessage['id'] as String? ?? 'user-$runId';
    final content = lastUserMessage['content'] as String? ?? '';

    return [
      {'type': 'TEXT_MESSAGE_START', 'messageId': id, 'role': 'user'},
      {'type': 'TEXT_MESSAGE_CONTENT', 'messageId': id, 'delta': content},
      {'type': 'TEXT_MESSAGE_END', 'messageId': id},
    ];
  }

  /// Replays events to reconstruct thread history (messages + AG-UI state).
  ///
  /// Processes events per-run to properly correlate citations with user
  /// messages. Each run's citations are keyed by the user message ID that
  /// initiated that run.
  ThreadHistory _replayEventsToHistory(
    List<({String runId, List<Map<String, dynamic>> events})> eventsPerRun,
    String threadId,
  ) {
    if (eventsPerRun.isEmpty) return ThreadHistory(messages: const []);

    var conversation = Conversation.empty(threadId: threadId);
    var streaming = const AwaitingText() as StreamingState;
    const decoder = EventDecoder();
    final extractor = CitationExtractor();
    final messageStates = <String, MessageState>{};
    var skippedEventCount = 0;

    for (final (:runId, :events) in eventsPerRun) {
      // Capture AG-UI state before processing this run
      final previousAguiState = conversation.aguiState;

      // Find user message ID from LAST TEXT_MESSAGE_START with role=user.
      // The run_input.messages contains ALL conversation messages, but the
      // LAST user message is the one that initiated THIS run.
      String? userMessageId;
      for (final eventJson in events) {
        final type = eventJson['type'] as String?;
        if (type == 'TEXT_MESSAGE_START') {
          final role = eventJson['role'] as String?;
          if (role == 'user') {
            userMessageId = eventJson['messageId'] as String?;
            // Don't break - keep iterating to find the last one
          }
        }
      }

      // Process all events in this run
      for (final eventJson in events) {
        try {
          final event = decoder.decodeJson(eventJson);
          final result = processEvent(conversation, streaming, event);
          conversation = result.conversation;
          streaming = result.streaming;
        } on DecodingError {
          skippedEventCount++;
        }
      }

      // Extract new citations by comparing state before/after this run
      if (userMessageId != null) {
        final sourceReferences = extractor.extractNew(
          previousAguiState,
          conversation.aguiState,
        );
        messageStates[userMessageId] = MessageState(
          userMessageId: userMessageId,
          sourceReferences: sourceReferences,
          runId: runId,
        );
      }
    }

    if (skippedEventCount > 0) {
      _onWarning?.call(
        'Skipped $skippedEventCount malformed event(s) '
        'while loading thread $threadId',
      );
    }

    return ThreadHistory(
      messages: conversation.messages,
      aguiState: conversation.aguiState,
      messageStates: messageStates,
    );
  }

  /// Sorts runs by creation time (oldest first).
  List<MapEntry<String, dynamic>> _sortRunsByCreationTime(
    Map<String, dynamic> runs,
  ) {
    return runs.entries.toList()..sort((a, b) {
      final aData = a.value as Map<String, dynamic>;
      final bData = b.value as Map<String, dynamic>;
      final aCreated = aData['created'] as String?;
      final bCreated = bData['created'] as String?;

      if (aCreated == null && bCreated == null) return 0;
      if (aCreated == null) return 1;
      if (bCreated == null) return -1;

      // Use tryParse to handle malformed timestamps gracefully
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final aTime = DateTime.tryParse(aCreated) ?? epoch;
      final bTime = DateTime.tryParse(bCreated) ?? epoch;
      return aTime.compareTo(bTime);
    });
  }

  // ============================================================
  // Quizzes
  // ============================================================

  /// Gets a quiz by ID.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [quizId]: The quiz ID (must not be empty)
  ///
  /// Returns the [Quiz] with the given ID.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [quizId] is empty
  /// - [NotFoundException] if quiz not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<Quiz> getQuiz(
    String roomId,
    String quizId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(quizId, 'quizId');

    return _transport.request<Quiz>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'quiz', quizId]),
      cancelToken: cancelToken,
      fromJson: quizFromJson,
    );
  }

  /// Submits an answer for a quiz question.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [quizId]: The quiz ID (must not be empty)
  /// - [questionId]: The question UUID (must not be empty)
  /// - [answer]: The user's answer text
  ///
  /// Returns a [QuizAnswerResult] indicating if the answer was correct.
  ///
  /// Throws:
  /// - [ArgumentError] if any ID is empty
  /// - [NotFoundException] if quiz or question not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<QuizAnswerResult> submitQuizAnswer(
    String roomId,
    String quizId,
    String questionId,
    String answer, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(quizId, 'quizId');
    _requireNonEmpty(questionId, 'questionId');

    return _transport.request<QuizAnswerResult>(
      'POST',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'quiz', quizId, questionId],
      ),
      body: {'text': answer},
      cancelToken: cancelToken,
      fromJson: quizAnswerResultFromJson,
    );
  }

  // ============================================================
  // Chunk Visualization
  // ============================================================

  /// Gets page images for a chunk with highlighted text.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [chunkId]: The chunk ID (must not be empty)
  ///
  /// Returns [ChunkVisualization] containing base64-encoded page images.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [chunkId] is empty
  /// - [NotFoundException] if chunk not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<ChunkVisualization> getChunkVisualization(
    String roomId,
    String chunkId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(chunkId, 'chunkId');

    return _transport.request<ChunkVisualization>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'chunk', chunkId]),
      cancelToken: cancelToken,
      fromJson: ChunkVisualization.fromJson,
    );
  }

  // ============================================================
  // Installation Info
  // ============================================================

  /// Gets backend version information.
  ///
  /// Returns [BackendVersionInfo] containing the soliplex version
  /// and all installed package versions.
  ///
  /// Throws:
  /// - [NetworkException] if connection fails
  /// - [ApiException] for server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<BackendVersionInfo> getBackendVersionInfo({
    CancelToken? cancelToken,
  }) async {
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['installation', 'versions']),
      cancelToken: cancelToken,
    );

    return backendVersionInfoFromJson(response);
  }

  /// Gets Monty-compatible Python schema validators from the backend.
  ///
  /// Returns a map of schema name to Python validator code string.
  /// Each value is a Monty-safe Python function definition like
  /// `def validate_tool(raw): ...`.
  ///
  /// Throws:
  /// - [NetworkException] if connection fails
  /// - [ApiException] for server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<Map<String, String>> getMontySchemas({
    CancelToken? cancelToken,
  }) async {
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['installation', 'schemas', 'monty']),
      cancelToken: cancelToken,
    );

    final schemas = response['schemas'] as Map<String, dynamic>?;
    if (schemas == null) return {};
    return schemas.map((k, v) => MapEntry(k, v as String));
  }

  // ============================================================
  // Uploads
  // ============================================================

  /// Uploads a file to a room's shared upload directory.
  ///
  /// The backend stores the file at `{upload_path}/rooms/{roomId}/`.
  /// Requires admin access.
  Future<void> uploadFileToRoom(
    String roomId, {
    required String filename,
    required List<int> fileBytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final encoded = encodeMultipart(
      fieldName: 'upload_file',
      filename: filename,
      fileBytes: fileBytes,
      mimeType: mimeType,
    );
    await _transport.request<void>(
      'POST',
      _urlBuilder.build(pathSegments: ['uploads', roomId]),
      body: encoded.bodyBytes,
      headers: {'content-type': encoded.contentType},
    );
  }

  /// Uploads a file to a thread's upload directory.
  ///
  /// The backend stores the file at `{upload_path}/threads/{threadId}/`.
  /// Requires room membership and a valid thread ID.
  Future<void> uploadFileToThread(
    String roomId,
    String threadId, {
    required String filename,
    required List<int> fileBytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final encoded = encodeMultipart(
      fieldName: 'upload_file',
      filename: filename,
      fileBytes: fileBytes,
      mimeType: mimeType,
    );
    await _transport.request<void>(
      'POST',
      _urlBuilder.build(pathSegments: ['uploads', roomId, threadId]),
      body: encoded.bodyBytes,
      headers: {'content-type': encoded.contentType},
    );
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  /// Closes the API client and releases resources.
  ///
  /// After calling this method, no further requests should be made.
  void close() {
    _runEventsCache.clear();
    _transport.close();
  }

  // ============================================================
  // Private helpers
  // ============================================================

  /// Validates that a string value is not empty.
  void _requireNonEmpty(String value, String name) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }
}
