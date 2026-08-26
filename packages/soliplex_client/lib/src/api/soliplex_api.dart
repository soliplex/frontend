import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/application/agui_event_processor.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/backend_version_info.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/chunk_visualization.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/feedback_type.dart';
import 'package:soliplex_client/src/domain/file_upload.dart';
import 'package:soliplex_client/src/domain/message_state.dart';
import 'package:soliplex_client/src/domain/quiz.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/room_stats.dart';
import 'package:soliplex_client/src/domain/run_info.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_info.dart';
import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/multipart_encoder.dart';
import 'package:soliplex_client/src/http/web_multipart_file_body.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex_client.api');

/// The user message that initiated a run, read from its persisted `run_input`
/// because the backend never echoes the user's own turn as AG-UI events.
///
/// `text` is always the message's text. `parts` is set only when the message
/// carried an attachment — an image, or a placeholder for one that could not be
/// rebuilt — the only case where the ordered form says more than `text` alone.
/// So a non-null `parts` always satisfies [TextMessage.fromParts].
typedef _RunUserMessage = ({
  String messageId,
  List<MessagePart>? parts,
  String text,
});

/// What a run's GET yielded: the AG-UI events the backend streamed, plus the
/// user message that initiated the run, which those events never carry.
///
/// `events` is `List<Object?>` rather than `List<dynamic>` deliberately. Items
/// must survive shape drift as *data* — the replay loop mints a drop tile for
/// any non-Map entry — but `dynamic` would also switch off the static checking
/// that forces each consumer to narrow before use, which is the one thing
/// keeping that drift from becoming a runtime throw.
typedef _RunPayload = ({
  List<Object?> events,
  _RunUserMessage? userMessage,
});

/// A run with nothing to replay. `events` is empty rather than null so the
/// replay loop reads one shape either way.
///
/// Not a sentinel: records compare field-wise, so a run the backend genuinely
/// returned empty can compare equal to this. What marks a run as missing is its
/// `fetchError`, never a comparison against this value.
const _RunPayload _noRunData = (
  events: <Object?>[],
  userMessage: null,
);

/// One run as replay sees it: its payload joined with the identity, fetch
/// outcome, and server `created` time from the thread listing, in creation
/// order.
///
/// Separate from [_RunPayload] because [_RunPayload] is what the run cache
/// stores. A fetch outcome or a listing timestamp folded into it would be
/// served again on the next open of the thread, long after it stopped being
/// true.
typedef _ReplayRun = ({
  String runId,
  _RunPayload payload,
  SoliplexException? fetchError,
  StackTrace? fetchStackTrace,
  DateTime? created,
});

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
  })  : _transport = transport,
        _urlBuilder = urlBuilder,
        _onWarning = onWarning;

  final HttpTransport _transport;
  final UrlBuilder _urlBuilder;
  final void Function(String message)? _onWarning;

  /// Maximum number of runs to cache. Covers ~5-10 threads of history.
  static const _maxCacheSize = 100;

  /// LRU cache for run events. Completed runs are immutable, so safe to cache.
  /// Uses insertion order - oldest entries are at the front.
  ///
  /// The reconstructed user message rides the same entry rather than a parallel
  /// map: a cache hit returns before [_fetchRunEvents] ever sees `run_input`
  /// again, so parts kept anywhere else would be lost the second time a thread
  /// is opened in one session. That also means an entry retains its message's
  /// image bytes until it is evicted — past the close of the thread it belongs
  /// to — and eviction counts entries, not bytes.
  final _runEventsCache = <String, _RunPayload>{};

  String _runCacheKey(String threadId, String runId) => '$threadId:$runId';

  /// Adds to cache with LRU eviction.
  void _cacheRunEvents(String key, _RunPayload run) {
    // Remove if exists (to update position for LRU)
    _runEventsCache.remove(key);

    // Evict oldest entries if at capacity
    while (_runEventsCache.length >= _maxCacheSize) {
      _runEventsCache.remove(_runEventsCache.keys.first);
    }

    _runEventsCache[key] = run;
  }

  /// Gets from cache and updates LRU position.
  _RunPayload? _getCachedRunEvents(String key) {
    final run = _runEventsCache.remove(key);
    if (run != null) {
      _runEventsCache[key] = run; // Re-add to move to end (most recent)
    }
    return run;
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
        final json = entry.value as Map<String, dynamic>;
        rooms.add(roomFromJson(json));
        _noteUploadCapability(entry.key, json);
      } catch (e, st) {
        // The room id names the entry; the failure carries the payload that
        // produced it, so only its shape is kept.
        _logger.warning(
          'Malformed room ignored',
          attributes: {'roomId': entry.key, 'failure': describeFailure(e)},
          stackTrace: st,
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
      // Mapped inside the transport so a malformed payload still surfaces as
      // [MalformedResponseException] rather than the mapper's own failure.
      fromJson: (json) {
        final room = roomFromJson(json);
        _noteUploadCapability(roomId, json);
        return room;
      },
    );
  }

  /// Whether [_noteUploadCapability] has already recorded an omission.
  bool _reportedUploadCapabilityOmission = false;

  /// Records that the server did not report upload capability for [roomId].
  ///
  /// Absence withholds every upload control, which is otherwise
  /// indistinguishable from a room the installation has no upload path for,
  /// so this record is where that difference survives. It is written once per
  /// server: the omission belongs to the release the server runs, not to one
  /// room, and every room in a session comes from one release. Both the
  /// listing and the single-room fetch report, because a deep link reaches a
  /// room without ever listing one.
  ///
  /// Only a payload that reports neither scope counts, per
  /// [roomOmitsUploadCapability]. A release that publishes one key and not the
  /// other withholds that scope's control with nothing recorded here — the two
  /// keys ship together, so nothing is expected to produce it.
  void _noteUploadCapability(String roomId, Map<String, dynamic> json) {
    if (_reportedUploadCapabilityOmission) return;
    if (!roomOmitsUploadCapability(json)) return;
    _reportedUploadCapabilityOmission = true;
    _logger.warning(
      'Server did not report upload capability; attach controls withheld',
      attributes: {'roomId': roomId, 'baseUrl': _urlBuilder.baseUrl},
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

    return _requireString(response, 'mcp_token', 'getMcpToken(room $roomId)');
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
    final rawThreads = response['threads'];
    if (rawThreads is! List) {
      throw MalformedResponseException(
        message: 'getThreads: expected a list "threads", '
            'got ${rawThreads.runtimeType}.',
      );
    }
    try {
      return rawThreads
          .map((e) => threadInfoFromJson(e as Map<String, dynamic>))
          .toList();
    } on SoliplexException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw MalformedResponseException(
        message: 'getThreads: malformed thread entry: '
            '${describeFailure(error)}',
        originalError: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Gets last-activity stats for the user's accessible rooms in one request.
  ///
  /// Returns a map keyed by room ID, holding what the stats endpoint reports
  /// for the requesting user. The map may omit rooms — callers should treat an
  /// absent room the same as one with no activity. Malformed entries are
  /// skipped rather than failing the batch. A present entry with a `null`
  /// [RoomStats.lastActivity] means the room has no activity for this user.
  ///
  /// Throws:
  /// - [AuthException] if unauthenticated (401)
  /// - [PermissionDeniedException] if the authorization policy forbids it (403)
  /// - [NotFoundException] if the endpoint is absent (pre-stats backend, 404)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<Map<String, RoomStats>> getRoomsStats({
    CancelToken? cancelToken,
  }) async {
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['stats', 'rooms']),
      cancelToken: cancelToken,
    );
    // Skip malformed entries so one bad room doesn't drop the whole server's
    // activity.
    final stats = <String, RoomStats>{};
    var skipped = 0;
    for (final entry in response.entries) {
      try {
        stats[entry.key] = roomStatsFromJson(
          entry.value as Map<String, dynamic>,
        );
      } catch (e) {
        skipped++;
        developer.log(
          'Malformed room stats ignored (${entry.key}): $e',
          name: 'soliplex_client.api',
          level: 900,
        );
      }
    }
    if (skipped > 0 && stats.isEmpty) {
      // Every entry failing on a non-empty response is a systemic break (the
      // payload shape changed), not a single bad room — surface it loudly. The
      // caller can't tell this apart from "no activity", so it would otherwise
      // be invisible.
      developer.log(
        'All $skipped room stats entries were malformed; '
        'returning no activity',
        name: 'soliplex_client.api',
        level: 1000,
      );
    } else if (skipped > 0) {
      // Partial failure: tie the scattered per-entry warnings together so a
      // subset regression (e.g. a renamed field on some rooms) reads as one
      // signal rather than isolated noise.
      developer.log(
        '$skipped of ${response.length} room stats entries were malformed',
        name: 'soliplex_client.api',
        level: 900,
      );
    }
    return stats;
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

    // Prefer the backend's server `created`; fall back to the client clock if
    // the response omits it or the value is malformed.
    final threadInfo = ThreadInfo(
      id: _requireString(response, 'thread_id', 'createThread'),
      roomId: roomId,
      initialRunId: initialRunId ?? '',
      name: threadName,
      createdAt: _createdOrNow(response['created']),
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

    // Normalize response: backend returns run_id, we use id. Prefer the
    // backend's server `created`; fall back to the client clock if the response
    // omits it or the value is malformed.
    return RunInfo(
      id: _requireString(response, 'run_id', 'createRun'),
      threadId: threadId,
      createdAt: _createdOrNow(response['created']),
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

    // Envelope-level shape drift (`runs` arrives as a list/scalar instead
    // of a map) is a backend bug — retry can't fix it. Throw so the UI
    // surfaces a non-retryable error rather than rendering an empty
    // thread (which is indistinguishable from a fresh thread). Null /
    // missing stays a legitimate empty thread.
    final rawRuns = response['runs'];
    if (rawRuns != null && rawRuns is! Map<String, dynamic>) {
      throw MalformedResponseException(
        message: 'Thread history `runs` field has unexpected shape: '
            '${rawRuns.runtimeType}',
      );
    }
    final runs =
        rawRuns is Map<String, dynamic> ? rawRuns : const <String, dynamic>{};
    if (runs.isEmpty) return ThreadHistory(messages: const []);
    final documentFilter = _extractLatestDocumentFilter(runs);

    // 2. Walk runs in creation order, collecting:
    //    - completed run ids → fetched in parallel below
    //    - malformed entries → preserved as drop-tile placeholders so the
    //      run is visibly absent rather than silently filtered out
    //    Unfinished runs are skipped without surfacing — they are still
    //    in flight, not corrupted.
    final completedRunIds = <String>[];
    final preFetchDrops =
        <({String runId, MalformedResponseException error})>[];
    for (final entry in _sortRunsByCreationTime(runs)) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        preFetchDrops.add(
          (
            runId: entry.key,
            error: MalformedResponseException(
              message: 'Run entry ${entry.key} has unexpected shape: '
                  '${value.runtimeType}',
            ),
          ),
        );
        continue;
      }
      if (value['finished'] == null) continue;
      final rawRunId = value['run_id'];
      // Blank is rejected alongside the wrong type: a run id stands in for a
      // missing message id below, where two runs sharing one would have the
      // second's message dropped as a repeat.
      if (rawRunId is! String || rawRunId.isEmpty) {
        final got =
            rawRunId is String ? 'an empty String' : '${rawRunId.runtimeType}';
        preFetchDrops.add(
          (
            runId: entry.key,
            error: MalformedResponseException(
              message: 'Run entry ${entry.key} missing `run_id` (got $got)',
            ),
          ),
        );
        continue;
      }
      completedRunIds.add(rawRunId);
    }

    if (completedRunIds.isEmpty && preFetchDrops.isEmpty) {
      return ThreadHistory(messages: const [], documentFilter: documentFilter);
    }

    // 3. Fetch all run events in parallel (cache handles duplicates)
    final eventFutures = completedRunIds.map((runId) {
      return _fetchRunEvents(
        roomId,
        threadId,
        runId,
        cancelToken: cancelToken,
      )
          .then(
        (payload) => (
          runId: runId,
          payload: payload,
          fetchError: null as SoliplexException?,
          fetchStackTrace: null as StackTrace?,
        ),
      )
          .catchError(
        // The stack is taken here because this is the only frame that has it;
        // the replay loop logs the failure far from where it was thrown.
        (Object e, StackTrace stackTrace) {
          // Log transient failure but continue with other runs. The
          // fetchError below carries the same exception into the replay
          // loop, which mints a drop tile so the run is visibly missing
          // rather than silently absent.
          _onWarning?.call('Failed to fetch events for run $runId: $e');
          return (
            runId: runId,
            payload: _noRunData,
            // Narrowed by `test` below to the two transient types, both
            // SoliplexException subtypes.
            fetchError: e as SoliplexException,
            fetchStackTrace: stackTrace,
          );
        },
        // Only catch transient errors - show partial results for batch ops:
        // - NetworkException: network blip, retry might succeed
        // - NotFoundException: run deleted between list and fetch (race)
        // Let ApiException propagate - systemic problem (500, 429, 400)
        test: (e) => e is NetworkException || e is NotFoundException,
      );
    });

    final results = await Future.wait(eventFutures);

    // 4. Collect events in run order (results may arrive out of order),
    //    interleaving pre-fetch drops at their original creation-order
    //    position by walking the original sort once.
    final fetchByRunId = {for (final r in results) r.runId: r};
    final preFetchByRunKey = {for (final d in preFetchDrops) d.runId: d.error};
    final runsToReplay = <_ReplayRun>[];
    for (final entry in _sortRunsByCreationTime(runs)) {
      final created = _runCreated(entry.value, entry.key, threadId);
      final preFetchError = preFetchByRunKey[entry.key];
      if (preFetchError != null) {
        runsToReplay.add(
          (
            runId: entry.key,
            payload: _noRunData,
            fetchError: preFetchError,
            // Built here, not thrown, so there is no stack worth carrying.
            fetchStackTrace: null,
            created: created,
          ),
        );
        continue;
      }
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      if (value['finished'] == null) continue;
      final rawRunId = value['run_id'];
      if (rawRunId is! String) continue;
      final fetched = fetchByRunId[rawRunId];
      if (fetched == null) continue;
      runsToReplay.add(
        (
          runId: rawRunId,
          payload: fetched.payload,
          fetchError: fetched.fetchError,
          fetchStackTrace: fetched.fetchStackTrace,
          created: created,
        ),
      );
    }

    // 5. Replay events to reconstruct history (messages + AG-UI state)
    return _replayEventsToHistory(runsToReplay, threadId, documentFilter);
  }

  /// Fetches events for a single run, using cache for completed runs.
  ///
  /// Returns the run's streamed events alongside the user message that
  /// initiated it, read from `run_input` because the backend stores user input
  /// separately and never echoes it as AG-UI events.
  ///
  /// `events` is `List<Object?>` rather than `List<Map<String, dynamic>>`:
  /// shape drift on the wire (a non-Map item slipping into `events`)
  /// must reach [_replayEventsToHistory] as data, not throw at the cast
  /// site. The replay loop type-checks each item and mints a drop tile
  /// for non-Map entries.
  ///
  /// `events` not being a list at all is the one drift that cannot become a
  /// drop tile — there is no item to mint one for — so it is logged instead.
  Future<_RunPayload> _fetchRunEvents(
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

    final rawEvents = rawRun['events'];
    if (rawEvents is! List && rawEvents != null) {
      // Absent is normal for a run that streamed nothing; present-but-wrong-
      // shape erases every reply the run produced, and this is the only place
      // it is visible.
      _logger.warning(
        'replay: run $runId in thread $threadId has `events` as '
        '${rawEvents.runtimeType}, not a list; the run replays as empty.',
      );
    }
    final run = (
      events: rawEvents is List ? rawEvents : const <Object?>[],
      userMessage: _extractUserMessage(rawRun, threadId, runId),
    );
    _cacheRunEvents(cacheKey, run);
    return run;
  }

  /// The user message that initiated the run [runId], read from `run_input`.
  ///
  /// Each run's `run_input.messages` contains the full conversation context,
  /// but only the last user message initiated THIS run. Prior user messages
  /// were already processed in earlier runs.
  ///
  /// Null when the run carries no user message to rebuild. That costs more than
  /// the message itself — [_replayEventsToHistory] keys the turn's citations
  /// and message state off its id — so every shape that reaches it by drift
  /// rather than by absence is logged.
  _RunUserMessage? _extractUserMessage(
    Map<String, dynamic> rawRun,
    String threadId,
    String runId,
  ) {
    // Type-checked rather than cast: shape drift here degrades to "no user
    // message" rather than aborting the run-level fetch.
    final runInput = rawRun['run_input'];
    if (runInput is! Map<String, dynamic>) {
      // Absent is normal for a run the backend has not persisted input for;
      // present-but-wrong-shape is drift only findable here.
      if (runInput != null) {
        _logger.warning(
          'replay: run $runId in thread $threadId has `run_input` as '
          '${runInput.runtimeType}, not an object; its user message is lost, '
          'and with it the citations for that turn.',
        );
      }
      return null;
    }

    final rawMessages = runInput['messages'];
    if (rawMessages is! List) {
      if (rawMessages != null) {
        _logger.warning(
          'replay: run $runId in thread $threadId has `run_input.messages` as '
          '${rawMessages.runtimeType}, not a list; its user message is lost, '
          'and with it the citations for that turn.',
        );
      }
      return null;
    }

    // Find the last user message — the one that initiated this run.
    Map<String, dynamic>? lastUserMessage;
    for (var i = rawMessages.length - 1; i >= 0; i--) {
      final raw = rawMessages[i];
      if (raw is! Map<String, dynamic>) continue;
      final role = raw['role'];
      if ((role is String ? role : 'user') == 'user') {
        lastUserMessage = raw;
        break;
      }
    }
    if (lastUserMessage == null) {
      if (rawMessages.isNotEmpty) {
        _logger.warning(
          'replay: run $runId in thread $threadId carries '
          '${rawMessages.length} input message(s) but none from the user; '
          'the turn has no citations or message state.',
        );
      }
      return null;
    }

    // A blank id is no more usable than a missing one: the append guard below
    // reads a repeat as a continuation, so every blank-id turn in a thread
    // would collapse onto the first. Both fall back to the run's own id, which
    // the thread listing rejects unless it is a non-empty String — so two runs
    // cannot collide on it.
    final rawId = lastUserMessage['id'];
    if (rawId is! String || rawId.isEmpty) {
      _logger.warning(
        'replay: the user message initiating run $runId in thread $threadId '
        'has no usable id; keying it to the run instead.',
      );
    }
    final id = rawId is String && rawId.isNotEmpty ? rawId : 'user-$runId';
    final content = readUserMessageContent(
      lastUserMessage['content'],
      logContext: 'message $id in run $runId of thread $threadId',
    );

    return (messageId: id, parts: content.parts, text: content.text);
  }

  /// The domain message for [userMessage], stamped with [createdAt].
  ///
  /// A non-null `parts` already satisfies [TextMessage.fromParts], but that
  /// holds only by the postcondition [readUserMessageContent] documents rather
  /// than by anything a type enforces, so it is re-checked here. An escaping
  /// `ArgumentError` would cost the whole thread's history, where the one
  /// message is what is actually in doubt.
  ///
  /// Checked rather than caught: a rejection is a payload this method can
  /// render around, while anything else that factory throws is a defect, and
  /// catching would hide it for as long as it lives.
  TextMessage _hydratedUserMessage(
    _RunUserMessage userMessage,
    DateTime? createdAt,
    String threadId,
    String runId,
  ) {
    final parts = userMessage.parts;
    if (parts != null) {
      if (parts.plainText.isNotEmpty || parts.hasAttachment) {
        return TextMessage.fromParts(
          id: userMessage.messageId,
          parts: parts,
          createdAt: createdAt,
        );
      }
      _logger.error(
        'replay: the ordered content of message ${userMessage.messageId} in '
        'run $runId of thread $threadId carries neither an attachment nor any '
        'text; rendering it as an empty message.',
      );
    }
    return TextMessage.create(
      id: userMessage.messageId,
      user: ChatUser.user,
      text: userMessage.text,
      createdAt: createdAt,
    );
  }

  /// The `document_filter` from the newest run that carries one in its
  /// persisted input state. The backend returns runs in ascending creation
  /// order (`Thread.runs` is `order_by="Run.created"`), and that order is
  /// preserved through the JSON dict into [runs], so the last entry carrying
  /// the key is the newest — no dependence on any per-run `created` value.
  /// Each run stores the complete filter it was sent (the client re-asserts it
  /// every run; the backend keeps no merged state), so the newest run's value
  /// IS the current filter — there is nothing to accumulate. An explicit null
  /// on the newest carrying run means "cleared" and wins over older runs.
  /// Resilient: malformed entries are skipped. See U3.
  String? _extractLatestDocumentFilter(Map<String, dynamic> runs) {
    for (final entry in runs.entries.toList().reversed) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      final runInput = value['run_input'];
      if (runInput is! Map<String, dynamic>) continue;
      final state = runInput['state'];
      if (state is! Map<String, dynamic>) continue;
      final rag = state['rag'];
      if (rag is! Map<String, dynamic>) continue;
      if (!rag.containsKey('document_filter')) continue;
      final filter = rag['document_filter'];
      return filter is String ? filter : null;
    }
    return null;
  }

  /// Replays events to reconstruct thread history (messages + AG-UI state).
  ///
  /// Processes events per-run to properly correlate citations with user
  /// messages. Each run's citations are keyed by the user message ID that
  /// initiated that run.
  ThreadHistory _replayEventsToHistory(
    List<_ReplayRun> runsToReplay,
    String threadId,
    String? documentFilter,
  ) {
    if (runsToReplay.isEmpty) {
      return ThreadHistory(messages: const [], documentFilter: documentFilter);
    }

    var conversation = Conversation.empty(threadId: threadId);
    final extractor = CitationExtractor();
    final messageStates = <String, MessageState>{};
    // Citations accumulated per turn (keyed by the run's last user message id),
    // unioned across every run of the turn — mirroring the live path. Carries
    // cited ids and inline figures so an earlier invocation's figure survives a
    // later invocation's `searches` clear.
    final turnsByUserMessage = <String, TurnCitations>{};
    final runs = <RunEventBundle>[];
    // Text of the user messages already appended, keyed by id, so a
    // continuation run does not add its parent's message a second time. An
    // index of what this loop appended, rather than a scan of the whole
    // conversation, so it cannot be confused by an assistant message that
    // happens to share an id.
    //
    // The text is kept because a repeated id has two very different causes: a
    // continuation run re-stating the turn it continues, or one id assigned to
    // two different messages. Both drop the second message; only the first is
    // harmless, and without the text they are indistinguishable.
    final appendedUserText = <String, String>{};

    for (final (:runId, :payload, :fetchError, :fetchStackTrace, :created)
        in runsToReplay) {
      final events = payload.events;
      final userMessage = payload.userMessage;
      // Scoped to one run because each run is its own AG-UI stream. A run whose
      // events lack RUN_FINISHED and RUN_ERROR alike leaves this mid-stream,
      // and carrying that into the next run would let its terminal event commit
      // the previous run's half-streamed text under the wrong run.
      var streaming = const AwaitingText() as StreamingState;
      // Run-level fetch failure (transient HTTP error or pre-fetch
      // shape-drift on the run entry) → mint one drop tile in place so
      // the run is visibly missing from the timeline rather than
      // silently absent. Such a run carries `_noRunData`, so there are no
      // events to replay after it and no user message to append; the drop
      // tile stands alone.
      if (fetchError != null) {
        _logger.error(
          'replay: run $runId in thread $threadId could not be fetched.',
          error: fetchError,
          stackTrace: fetchStackTrace,
        );
        conversation = conversation.withAppendedMessage(
          DroppedEventMessage.create(
            id: 'dropped-$runId-fetch',
            source: DropSource.decode,
            reason: fetchError.toString(),
            runId: runId,
            createdAt: created,
          ),
        );
      }

      // Keys this turn's citations and message state below.
      final userMessageId = userMessage?.messageId;

      // The run-start event carries the server time the run began. Messages
      // without a timestamp of their own — chiefly the user message — resolve
      // to it, matching the live path; run.created is the fallback when the
      // run-start event is absent or carries no usable timestamp.
      DateTime? runStartedAt;
      for (final eventJson in events) {
        if (eventJson is! Map<String, dynamic>) continue;
        if (eventJson['type'] != 'RUN_STARTED') continue;
        final ts = eventJson['timestamp'];
        if (ts is int) {
          try {
            runStartedAt = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
          } on Object catch (error) {
            _logger.warning(
              'replay: invalid RUN_STARTED timestamp ($ts) in run $runId of '
              'thread $threadId; falling back to run.created (or none).',
              error: error,
            );
          }
        } else if (ts != null) {
          _logger.warning(
            'replay: non-int RUN_STARTED timestamp (${ts.runtimeType}) in run '
            '$runId of thread $threadId; falling back to run.created '
            '(or none).',
          );
        }
        break;
      }
      final fallbackCreated = runStartedAt ?? created;

      // The user message is appended ahead of the events it triggered, rather
      // than folded from the stream, because the backend never sends it — the
      // same shape the live path uses, where the caller seeds the message into
      // the conversation before the stream opens.
      //
      // A run that could not be fetched has no user message to append, so its
      // drop tile stands alone.
      //
      // A repeat id is normally a continuation run, whose `run_input` still
      // ends with the user message its parent already contributed; the turn
      // keeps one bubble and later runs fold their events onto it.
      if (userMessage != null) {
        final appended = appendedUserText[userMessage.messageId];
        if (appended == null) {
          appendedUserText[userMessage.messageId] = userMessage.text;
          conversation = conversation.withAppendedMessage(
            _hydratedUserMessage(userMessage, fallbackCreated, threadId, runId),
          );
        } else if (appended == userMessage.text) {
          _logger.info(
            'replay: run $runId in thread $threadId continues the turn of '
            'message ${userMessage.messageId}; not appending it twice.',
          );
        } else {
          // Same id, different message: one of the two turns is now missing
          // from the transcript, and its citations are keyed onto the other.
          _logger.error(
            'replay: run $runId in thread $threadId reuses message id '
            '${userMessage.messageId} for different text; the user message of '
            'this run is dropped from the transcript.',
          );
        }
      }

      // Per-event try/catch so one bad event can't abort replay.
      final decodedEvents = <BaseEvent>[];
      for (var i = 0; i < events.length; i++) {
        final eventJson = events[i];
        void appendDrop({
          required DropSource source,
          required Object error,
          required StackTrace stackTrace,
          required String stage,
          required Object? rawPayload,
          String? typeForLog,
        }) {
          _logger.error(
            'replay: $stage failed at events[$i] '
            '(type=$typeForLog) in run $runId of thread $threadId.',
            error: error,
            stackTrace: stackTrace,
          );
          conversation = conversation.withAppendedMessage(
            DroppedEventMessage.create(
              id: 'dropped-$runId-$i',
              source: source,
              reason: error.toString(),
              runId: runId,
              rawPayload: rawPayload,
              createdAt: fallbackCreated,
            ),
          );
        }

        if (eventJson is! Map<String, dynamic>) {
          appendDrop(
            source: DropSource.decode,
            error: FormatException(
              'Non-object item in AG-UI events: ${eventJson.runtimeType}',
            ),
            stackTrace: StackTrace.current,
            stage: 'decode',
            rawPayload: eventJson,
            typeForLog: '<non-map>',
          );
          continue;
        }

        final outcome = decodeMapSafely(eventJson);
        final type = eventJson['type'] is String
            ? eventJson['type'] as String
            : '<missing>';
        switch (outcome) {
          case DecodeFailed(:final error, :final stackTrace):
            appendDrop(
              source: DropSource.decode,
              error: error,
              stackTrace: stackTrace ?? StackTrace.current,
              stage: 'decode',
              rawPayload: eventJson,
              typeForLog: type,
            );
          case DecodedEvent(:final event):
            decodedEvents.add(event);
            try {
              final result = processEvent(
                conversation,
                streaming,
                event,
                runCreated: fallbackCreated,
              );
              conversation = result.conversation;
              streaming = result.streaming;
              // Accumulate this run's cited ids and inline figures into the
              // turn's accumulator, from whichever carrier the run recorded:
              // a terminal snapshot holds the run's complete cited set, having
              // been seeded with the run-scoped keys emptied, while a delta
              // holds one contribution and is scoped to the namespaces it
              // touched. Own fail-soft guard (log-only, never a drop tile):
              // the event already processed, and citations are a derived
              // projection.
              if (event is StateDeltaEvent && userMessageId != null) {
                try {
                  turnsByUserMessage[userMessageId] = extractor.accumulate(
                    turnsByUserMessage[userMessageId] ??
                        const TurnCitations.empty(),
                    conversation.aguiState,
                    event,
                  );
                } on Object catch (error, stackTrace) {
                  _logger.error(
                    'replay: citation accumulation failed in run $runId of '
                    'thread $threadId (${event.runtimeType}).',
                    error: error,
                    stackTrace: stackTrace,
                  );
                }
              } else if (event is StateSnapshotEvent && userMessageId != null) {
                try {
                  turnsByUserMessage[userMessageId] =
                      extractor.accumulateSnapshot(
                    turnsByUserMessage[userMessageId] ??
                        const TurnCitations.empty(),
                    conversation.aguiState,
                  );
                } on Object catch (error, stackTrace) {
                  _logger.error(
                    'replay: citation accumulation failed in run $runId of '
                    'thread $threadId (${event.runtimeType}).',
                    error: error,
                    stackTrace: stackTrace,
                  );
                }
              }
            } on Object catch (error, stackTrace) {
              appendDrop(
                source: DropSource.eventProcessing,
                error: error,
                stackTrace: stackTrace,
                stage: 'processEvent',
                rawPayload: eventJson,
                typeForLog: type,
              );
            }
        }
      }
      runs.add(RunEventBundle(runId: runId, events: decodedEvents));

      // Resolve the turn's accumulated ids against this run's end-of-turn state
      // and (re)emit its MessageState — the turn's last run wins, mirroring the
      // live path's resolve-at-every-terminal. Resolving against the run's own
      // state is what preserves a turn's inline figure bytes: `searches` is
      // cleared per run and a later run overwrites it, while `citation_index`
      // stays session-cumulative so the ids still resolve. A turn that cited
      // nothing still gets a MessageState carrying its runId.
      if (userMessageId != null) {
        var sourceReferences = const <SourceReference>[];
        try {
          sourceReferences = extractor.resolve(
            turnsByUserMessage[userMessageId] ?? const TurnCitations.empty(),
            conversation.aguiState,
            logContext: 'run $runId, thread $threadId',
          );
        } on Object catch (error, stackTrace) {
          // Fail-soft, mirroring the live orchestrator path: citations are a
          // derived projection, so a resolution failure must not abort the
          // history load. Emit the MessageState with its runId and no refs.
          _logger.error(
            'replay: citation resolution failed for run $runId in thread '
            '$threadId.',
            error: error,
            stackTrace: stackTrace,
          );
        }
        _logger.info(
          'replay: run $runId resolved ${sourceReferences.length} source(s) '
          'from ${turnsByUserMessage[userMessageId]?.ids.length ?? 0} cited '
          'id(s), '
          '${sourceReferences.where((r) => r.figures.isNotEmpty).length} '
          'with figures.',
        );
        // An id the stored state says was cited but that no carrier fed into
        // the accumulator means this build cannot read the record's carrier.
        // The counts above all derive from the accumulator, so without this the
        // shortfall reads as a turn that simply cited nothing.
        try {
          final uncredited =
              extractor.citationsInState(conversation.aguiState).ids.difference(
                    turnsByUserMessage[userMessageId]?.ids ?? const {},
                  );
          if (uncredited.isNotEmpty) {
            _logger.warning(
              'replay: run $runId of thread $threadId ended with '
              '${uncredited.length} cited id(s) present in state but never '
              'accumulated; the rendered source list is short. '
              'ids: $uncredited',
            );
          }
        } on Object catch (error, stackTrace) {
          _logger.error(
            'replay: uncredited-id check failed in run $runId of thread '
            '$threadId.',
            error: error,
            stackTrace: stackTrace,
          );
        }
        messageStates[userMessageId] = MessageState(
          userMessageId: userMessageId,
          sourceReferences: sourceReferences,
          runId: runId,
        );
      }
    }

    return ThreadHistory(
      messages: conversation.messages,
      aguiState: conversation.aguiState,
      messageStates: messageStates,
      runs: runs,
      documentFilter: documentFilter,
    );
  }

  /// Resolves a create response's server [created] to a UTC [DateTime],
  /// degrading to the client clock ([DateTime.timestamp], also UTC) when it is
  /// absent or malformed. Unlike [_runCreated] (replay, which has no acceptable
  /// client fallback for a historical run), a freshly created run/thread can
  /// safely stamp the current time rather than fail the create call.
  static DateTime _createdOrNow(dynamic created) {
    // Absent is the documented fallback; a present-but-wrong-shaped value is
    // contract drift worth a signal (same warn-on-wrong-shape as [_runCreated],
    // which differs only in resolving a bad value to null instead of `now()`).
    if (created == null) return DateTime.timestamp();
    if (created is! String) {
      _logger.warning(
        'create: non-string `created` (${created.runtimeType}); using the '
        'client clock.',
      );
      return DateTime.timestamp();
    }
    try {
      return parseTimestamp(created);
    } on FormatException catch (error) {
      _logger.warning(
        'create: malformed `created` ($created); using the client clock.',
        error: error,
      );
      return DateTime.timestamp();
    } on Object catch (error, stackTrace) {
      // parseTimestamp is documented to throw only FormatException; anything
      // else is an unexpected contract break worth a louder signal, but still
      // must not fail the create call.
      _logger.error(
        'create: unexpected error parsing `created` ($created); using the '
        'client clock.',
        error: error,
        stackTrace: stackTrace,
      );
      return DateTime.timestamp();
    }
  }

  /// Resolves a run map's `created` to a UTC [DateTime] via [parseTimestamp]
  /// (which reads a naive ISO-8601 string as UTC), or null when the field is
  /// absent. A present-but-wrong-shaped or malformed value logs a warning and
  /// resolves to null, leaving the run's replayed messages without a displayed
  /// timestamp rather than substituting a client `now()`.
  static DateTime? _runCreated(dynamic runData, String runId, String threadId) {
    if (runData is! Map<String, dynamic>) return null;
    final created = runData['created'];
    if (created == null) return null;
    if (created is! String) {
      _logger.warning(
        'replay: run $runId in thread $threadId has a non-string `created` '
        '(${created.runtimeType}); resolving to no timestamp.',
      );
      return null;
    }
    try {
      return parseTimestamp(created);
    } on FormatException catch (error) {
      // Expected shape drift: a malformed `created` string. Routine — warn
      // and resolve to no timestamp.
      _logger.warning(
        'replay: run $runId in thread $threadId has a malformed `created` '
        'timestamp; resolving to no timestamp.',
        error: error,
      );
      return null;
    } on Object catch (error, stackTrace) {
      // parseTimestamp is documented to throw only FormatException; anything
      // else is an unexpected contract break worth a louder signal. Still
      // resolve to null so one run never aborts the whole history replay.
      _logger.error(
        'replay: run $runId in thread $threadId threw unexpectedly parsing '
        '`created`; resolving to no timestamp.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Sorts runs by creation time (oldest first). Non-Map run values
  /// sort to the end; the caller filters them out before fetching.
  List<MapEntry<String, dynamic>> _sortRunsByCreationTime(
    Map<String, dynamic> runs,
  ) {
    return runs.entries.toList()
      ..sort((a, b) {
        final aData = a.value is Map<String, dynamic>
            ? a.value as Map<String, dynamic>
            : const <String, dynamic>{};
        final bData = b.value is Map<String, dynamic>
            ? b.value as Map<String, dynamic>
            : const <String, dynamic>{};
        final aCreated =
            aData['created'] is String ? aData['created'] as String : null;
        final bCreated =
            bData['created'] is String ? bData['created'] as String : null;

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
  /// - [refs]: Doc item refs to highlight. When supplied, the server highlights
  ///   exactly these items and [expand] has no effect.
  /// - [expand]: Whether the server widens the highlight from the chunk to the
  ///   section containing it, yielding more page images. Ignored when [refs] is
  ///   supplied. Always transmitted, so the value here is the value applied.
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
    List<String>? refs,
    bool expand = false,
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(chunkId, 'chunkId');

    final queryParameters = <String, String>{'expand': '$expand'};
    if (refs != null && refs.isNotEmpty) {
      queryParameters['refs'] = jsonEncode(refs);
    }

    return _transport.request<ChunkVisualization>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'chunk', chunkId],
        queryParameters: queryParameters,
      ),
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

  /// How long to wait for the installation's answer about the caller.
  ///
  /// Deliberately far below the 600-second transport default, which is sized
  /// for the streamed upload bodies that rely on it: this is a small question
  /// whose answer gates an affordance. It bounds the request only once it
  /// holds a concurrency slot, so a caller that must render before the answer
  /// arrives still needs its own in-flight state.
  static const Duration _authzTimeout = Duration(seconds: 15);

  /// Whether the signed-in user is an administrator of this installation.
  ///
  /// Installation-wide, not per room. Each call is audited server-side, so
  /// this is worth keeping for a session rather than asking per screen.
  ///
  /// Throws:
  /// - [NetworkException] if connection fails, including on [_authzTimeout]
  /// - [AuthException] if not authenticated (401)
  /// - [NotFoundException] if the server has no such endpoint (404)
  /// - [PermissionDeniedException] if the caller may not ask (403)
  /// - [ApiException] for other server errors
  /// - [MalformedResponseException] if the body is not a JSON object — a
  ///   portal or proxy answering 200 with a page is the reachable case — or if
  ///   `is_admin_user` is missing or not a bool
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<bool> getIsAdminUser({CancelToken? cancelToken}) async {
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['user', 'authz']),
      cancelToken: cancelToken,
      timeout: _authzTimeout,
    );

    final isAdmin = response['is_admin_user'];
    if (isAdmin is! bool) {
      throw const MalformedResponseException(
        message: 'user authz response has no boolean "is_admin_user"',
      );
    }
    return isAdmin;
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

    final rawSchemas = response['schemas'];
    // An absent "schemas" is a legitimate "no schemas configured" — empty map.
    if (rawSchemas == null) return {};
    if (rawSchemas is! Map<String, dynamic>) {
      throw MalformedResponseException(
        message: 'getMontySchemas: expected a map "schemas", '
            'got ${rawSchemas.runtimeType}.',
      );
    }
    return rawSchemas.map((k, v) {
      if (v is! String) {
        throw MalformedResponseException(
          message: 'getMontySchemas: expected a String value for "$k", '
              'got ${v.runtimeType}.',
        );
      }
      return MapEntry(k, v);
    });
  }

  // ============================================================
  // Uploads
  // ============================================================

  /// Lists files uploaded to a room's shared upload directory.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  ///
  /// Returns a list of [FileUpload] entries. Malformed entries in the
  /// response are logged and skipped.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] is empty
  /// - [NotFoundException] if room not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<FileUpload>> getRoomUploads(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['uploads', roomId]),
      cancelToken: cancelToken,
    );

    return _parseFileList(response, 'uploads', fileUploadFromJson);
  }

  /// Lists files uploaded to a thread within a room.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Returns a list of [FileUpload] entries. Malformed entries in the
  /// response are logged and skipped.
  ///
  /// Throws:
  /// - [ArgumentError] if [roomId] or [threadId] is empty
  /// - [NotFoundException] if room or thread not found (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<FileUpload>> getThreadUploads(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['uploads', roomId, 'thread', threadId]),
      cancelToken: cancelToken,
    );

    return _parseFileList(response, 'uploads', fileUploadFromJson);
  }

  /// Uploads a file to a room's shared upload directory.
  ///
  /// The backend stores the file at `{upload_path}/rooms/{roomId}/`.
  /// Requires admin access.
  ///
  /// [openStream] is called once per attempt and must return a fresh
  /// `Stream<List<int>>` of the file's bytes. [contentLength] is the
  /// exact byte length of those contents — used by the transport to set
  /// the request's `Content-Length` header.
  ///
  /// When [webFileBlob] is non-null, the request body becomes a
  /// [WebMultipartFileBody] instead — the web HTTP client hands the
  /// blob to the browser's native FormData/XHR pipeline so file bytes
  /// never enter the JS heap. [openStream] is then unused (the browser
  /// reads from the blob's disk-backed storage). [onProgress] receives
  /// `(sent, total)` ticks from `xhr.upload.onprogress` in that case.
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
    final uri = _urlBuilder.build(pathSegments: ['uploads', roomId]);
    if (webFileBlob != null) {
      await _transport.request<void>(
        'POST',
        uri,
        body: WebMultipartFileBody(
          fieldName: 'upload_file',
          filename: filename,
          fileBlob: webFileBlob,
          mimeType: mimeType,
          contentLength: contentLength,
          onProgress: onProgress,
        ),
        cancelToken: cancelToken,
      );
      return;
    }
    final encoded = encodeMultipartStream(
      fieldName: 'upload_file',
      filename: filename,
      openStream: openStream,
      contentLength: contentLength,
      mimeType: mimeType,
    );
    await _transport.request<void>(
      'POST',
      uri,
      body: encoded.bodyStream,
      headers: {
        'content-type': encoded.contentType,
        'content-length': '${encoded.contentLength}',
      },
      cancelToken: cancelToken,
    );
  }

  /// Uploads a file to a thread's upload directory.
  ///
  /// The backend stores the file at `{upload_path}/threads/{threadId}/`.
  /// Requires room membership and a valid thread ID.
  ///
  /// [openStream] is called once per attempt and must return a fresh
  /// `Stream<List<int>>` of the file's bytes. [contentLength] is the
  /// exact byte length of those contents — used by the transport to set
  /// the request's `Content-Length` header.
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
    final uri = _urlBuilder.build(
      pathSegments: ['uploads', roomId, 'thread', threadId],
    );
    if (webFileBlob != null) {
      await _transport.request<void>(
        'POST',
        uri,
        body: WebMultipartFileBody(
          fieldName: 'upload_file',
          filename: filename,
          fileBlob: webFileBlob,
          mimeType: mimeType,
          contentLength: contentLength,
          onProgress: onProgress,
        ),
        cancelToken: cancelToken,
      );
      return;
    }
    final encoded = encodeMultipartStream(
      fieldName: 'upload_file',
      filename: filename,
      openStream: openStream,
      contentLength: contentLength,
      mimeType: mimeType,
    );
    await _transport.request<void>(
      'POST',
      uri,
      body: encoded.bodyStream,
      headers: {
        'content-type': encoded.contentType,
        'content-length': '${encoded.contentLength}',
      },
      cancelToken: cancelToken,
    );
  }

  // ============================================================
  // Workdir files
  // ============================================================

  /// Lists files written by the agent to the run working directory.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  /// - [runId]: The run ID (must not be empty)
  ///
  /// Returns a list of [WorkdirFile] entries. Malformed entries in the
  /// response are logged and skipped.
  ///
  /// Throws:
  /// - [ArgumentError] if any parameter is empty
  /// - [NotFoundException] if the sandbox is not configured (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<WorkdirFile>> getRunWorkdirFiles(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(runId, 'runId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['workdirs', roomId, 'thread', threadId, runId],
      ),
      cancelToken: cancelToken,
    );

    return _parseFileList(response, 'files', workdirFileFromJson);
  }

  /// Downloads a single file written by an agent run to its workdir.
  ///
  /// Buffers the entire response in memory; intended for the small text /
  /// data files agents typically produce. Multi-hundred-MB downloads should
  /// use a streaming endpoint (not yet implemented).
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  /// - [runId]: The run ID (must not be empty)
  /// - [filename]: The filename within the run's workdir (must not be empty)
  ///
  /// Returns the raw file bytes.
  ///
  /// Throws:
  /// - [ArgumentError] if any parameter is empty
  /// - [NotFoundException] if the sandbox is not configured or the file does
  ///   not exist (404)
  /// - [AuthException] if not authenticated (401/403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<Uint8List> getRunWorkdirFile(
    String roomId,
    String threadId,
    String runId,
    String filename, {
    CancelToken? cancelToken,
  }) {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(runId, 'runId');
    _requireNonEmpty(filename, 'filename');

    return _transport.requestBytes(
      'GET',
      _urlBuilder.build(
        pathSegments: [
          'workdirs',
          roomId,
          'thread',
          threadId,
          'run',
          runId,
          'file',
          filename,
        ],
      ),
      cancelToken: cancelToken,
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

  /// Reads a required String [key] from a decoded JSON [response], raising a
  /// (non-retryable) [MalformedResponseException] instead of a raw `TypeError`
  /// when the field is missing, null, or not a String. [context] names the
  /// calling endpoint in the message.
  ///
  /// [MalformedResponseException] (not [FormatException]) is deliberate: these
  /// are top-level response fields whose absence makes the whole response
  /// unusable, so the failure is hard rather than skippable. Contrast the
  /// per-entry `_requireString` in `mappers.dart`, which throws
  /// [FormatException] so an enclosing loop can skip one malformed entry.
  String _requireString(
    Map<String, dynamic> response,
    String key,
    String context,
  ) {
    final value = response[key];
    if (value is String) return value;
    throw MalformedResponseException(
      message: '$context: expected a String "$key", got ${value.runtimeType}.',
    );
  }

  /// Extracts typed entries from a list field in a JSON response.
  ///
  /// Missing [jsonKey] surfaces as a warning and an empty list, so a
  /// transient server omission doesn't break callers. A non-list value
  /// indicates a schema mismatch and is raised as [UnexpectedException].
  /// Malformed per-entry rows surface as warnings and are skipped.
  List<T> _parseFileList<T>(
    Map<String, dynamic> response,
    String jsonKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = response[jsonKey];
    if (raw == null) {
      _onWarning?.call('Response missing "$jsonKey" key; treating as empty');
      return const [];
    }
    if (raw is! List) {
      throw UnexpectedException(
        message: 'Response has non-list "$jsonKey" field: ${raw.runtimeType}',
      );
    }
    if (raw.isEmpty) return const [];
    final result = <T>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        _onWarning?.call(
          'Malformed "$jsonKey" entry ignored: expected a JSON object, '
          'got ${entry.runtimeType}',
        );
        continue;
      }
      try {
        result.add(fromJson(entry));
      } on FormatException catch (e) {
        _onWarning?.call('Malformed "$jsonKey" entry ignored: $e');
      }
    }
    return result;
  }
}
