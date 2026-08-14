import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/application/run_fold_observer.dart';
import 'package:soliplex_client/src/application/thread_history_replay.dart';
import 'package:soliplex_client/src/domain/backend_version_info.dart';
import 'package:soliplex_client/src/domain/chunk_visualization.dart';
import 'package:soliplex_client/src/domain/feedback_type.dart';
import 'package:soliplex_client/src/domain/file_upload.dart';
import 'package:soliplex_client/src/domain/quiz.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/room_stats.dart';
import 'package:soliplex_client/src/domain/run_feedback.dart';
import 'package:soliplex_client/src/domain/run_info.dart';
import 'package:soliplex_client/src/domain/run_usage.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_info.dart';
import 'package:soliplex_client/src/domain/thread_page.dart';
import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/multipart_encoder.dart';
import 'package:soliplex_client/src/http/web_multipart_file_body.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex_client.api');

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
  /// The reconstructed user message and tool results ride the same entry
  /// rather than a parallel map: a cache hit returns before [_fetchRunEvents]
  /// ever sees `run_input` again, so what is kept anywhere else would be lost
  /// the second time a thread is opened in one session. That also means an
  /// entry retains its message's image bytes until it is evicted — past the
  /// close of the thread it belongs to — and eviction counts entries, not
  /// bytes.
  final _runEventsCache = <String, RunPayload>{};

  String _runCacheKey(String threadId, String runId) => '$threadId:$runId';

  /// Adds to cache with LRU eviction.
  void _cacheRunEvents(String key, RunPayload run) {
    // Remove if exists (to update position for LRU)
    _runEventsCache.remove(key);

    // Evict oldest entries if at capacity
    while (_runEventsCache.length >= _maxCacheSize) {
      _runEventsCache.remove(_runEventsCache.keys.first);
    }

    _runEventsCache[key] = run;
  }

  /// Gets from cache and updates LRU position.
  RunPayload? _getCachedRunEvents(String key) {
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
      } catch (e, st) {
        _logger.warning(
          'Malformed document ignored',
          attributes: {'documentId': entry.key, 'failure': describeFailure(e)},
          stackTrace: st,
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

  /// Lists one page of the user's threads across every room they can see.
  ///
  /// Unlike [getThreads], which is scoped to a single room, this spans the
  /// whole server so a client can show one aggregated list. Threads come
  /// back with each room's threads contiguous — rooms ordered by their
  /// latest activity, threads alphabetically within a room — so a caller
  /// can start a new section whenever [ThreadInfo.roomId] changes instead
  /// of regrouping the page itself.
  ///
  /// Parameters:
  /// - [limit]: page size (must be positive)
  /// - [offset]: how many threads to skip (must not be negative)
  ///
  /// Throws:
  /// - [ArgumentError] if [limit] is not positive or [offset] is negative
  /// - [AuthException] if not authenticated (401/403)
  /// - [NotFoundException] if the endpoint is absent (pre-paging backend,
  ///   404) — callers should treat this as "this server cannot aggregate
  ///   threads" rather than as a transport failure
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<ThreadPage> getAllThreads({
    int limit = 50,
    int offset = 0,
    CancelToken? cancelToken,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['agui', 'threads'],
        queryParameters: {'limit': '$limit', 'offset': '$offset'},
      ),
      cancelToken: cancelToken,
    );

    try {
      return threadPageFromJson(response);
    } on SoliplexException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw MalformedResponseException(
        message: 'getAllThreads: malformed thread page: $error',
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
      } catch (e, st) {
        skipped++;
        _logger.warning(
          'Malformed room stats ignored',
          attributes: {'roomId': entry.key, 'failure': describeFailure(e)},
          stackTrace: st,
        );
      }
    }
    if (skipped > 0 && stats.isEmpty) {
      // Every entry failing on a non-empty response is a systemic break (the
      // payload shape changed), not a single bad room — surface it loudly. The
      // caller can't tell this apart from "no activity", so it would otherwise
      // be invisible.
      _logger.error(
        'All $skipped room stats entries were malformed; '
        'returning no activity',
      );
    } else if (skipped > 0) {
      // Partial failure: tie the scattered per-entry warnings together so a
      // subset regression (e.g. a renamed field on some rooms) reads as one
      // signal rather than isolated noise.
      _logger.warning(
        '$skipped of ${response.length} room stats entries were malformed',
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

  /// Returns what [runId] cost, or null when the backend holds no usage
  /// record for it.
  ///
  /// The same record the thread listing carries per run, fetched alone for
  /// the run just driven — the listing is not re-read after a run, and the
  /// full run detail would bring every event with it. Null is an answer,
  /// not a failure: a run that errored before its first request recorded
  /// nothing, and the previous run's reading still stands. A run that made a
  /// request answers with a record instead, whose
  /// [RunUsage.finalInputTokens] is null when the model never answered. A JSON
  /// object without the backend's counts reads the same way: a record with no
  /// count.
  ///
  /// Throws:
  /// - [ArgumentError] if any ID is empty
  /// - [NotFoundException] if the room, thread or run is not found (404)
  /// - [AuthException] if not authenticated (401)
  /// - [PermissionDeniedException] if the room is not permitted (403)
  /// - [MalformedResponseException] if the body is not a JSON object
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<RunUsage?> getRunUsage(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(runId, 'runId');

    return _transport.request<RunUsage?>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'agui', threadId, runId, 'usage'],
      ),
      cancelToken: cancelToken,
      fromJson: (json) => runUsageFromJson(runId, json),
    );
  }

  // ============================================================
  // Feedback
  // ============================================================

  /// How long [getRunFeedback] waits before reporting the note unreadable.
  ///
  /// It bounds the request only once it holds a concurrency slot, and applies
  /// per phase — connect, then body — and again on the retry after a token
  /// refresh. So it shortens the common slow answer; it is not a ceiling on
  /// the caller's total wait.
  static const Duration _feedbackReadTimeout = Duration(seconds: 15);

  /// Fetches the feedback record on file for a run.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  /// - [runId]: The run ID (must not be empty)
  ///
  /// Returns null when the backend answers a JSON `null` or an empty body,
  /// which is how it reports a run with no feedback record. A run with no
  /// record is not guaranteed to reach that path: an installation that reports
  /// absence some other way — a 404, or a 500 — throws instead, so a caller
  /// that must distinguish absence from unreadability has to treat a throw as
  /// unreadable rather than as absence.
  ///
  /// Throws:
  /// - [ArgumentError] if any ID is empty
  /// - [AuthException] if not authenticated (401)
  /// - [PermissionDeniedException] if authenticated but not permitted (403)
  /// - [NotFoundException] if the room, thread or run is unknown (404)
  /// - [NetworkException] if connection fails, including on
  ///   [_feedbackReadTimeout]
  /// - [MalformedResponseException] if the body is not a feedback record
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<RunFeedback?> getRunFeedback(
    String roomId,
    String threadId,
    String runId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(runId, 'runId');

    return _transport.request<RunFeedback?>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'agui', threadId, runId, 'feedback'],
      ),
      cancelToken: cancelToken,
      // Far below the transport default: this read gates a modal, and a caller
      // waiting on it can offer nothing but a spinner. Failing is recoverable —
      // the caller reports the note as unread — so a shorter wait is the safer
      // trade here. The write keeps the default, since a POST that timed out
      // may still have landed.
      timeout: _feedbackReadTimeout,
      fromJson: runFeedbackFromJson,
    );
  }

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
  /// - [MalformedResponseException] if the thread, its `runs`, or a run's
  ///   payload has an unexpected shape
  /// - [CancelledException] if cancelled via [cancelToken]
  ///
  /// [observer] is told each run whose events were read, each of its events,
  /// and how it ended, as the replay folds them. How a run ended is told once
  /// the next run whose events were read starts, or the history ends: only
  /// then is it known whether it waited on a client tool.
  Future<ThreadHistory> getThreadHistory(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
    RunFoldObserver? observer,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    // Get thread to list runs
    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(pathSegments: ['rooms', roomId, 'agui', threadId]),
      cancelToken: cancelToken,
    );

    Future<FetchedRun> fetch(String runId) {
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
            payload: noRunData,
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
    }

    return assembleThreadHistory(
      response,
      threadId,
      fetch,
      observer: observer,
    );
  }

  /// Fetches events for a single run, using cache for completed runs.
  ///
  /// Returns the run's streamed events alongside the user message that
  /// initiated it and the tool results that end its input, read from
  /// `run_input` because the backend stores user input separately and never
  /// echoes it as AG-UI events.
  Future<RunPayload> _fetchRunEvents(
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

    final run = runPayloadFromJson(rawRun, threadId, runId);
    _cacheRunEvents(cacheKey, run);
    return run;
  }

  /// Resolves a create response's server [created] to a UTC [DateTime],
  /// degrading to the client clock ([DateTime.timestamp], also UTC) when it is
  /// absent or malformed. Unlike `_runCreated` in thread_history_replay.dart
  /// (replay, which has no acceptable client fallback for a historical run), a
  /// freshly created run/thread can safely stamp the current time rather than
  /// fail the create call.
  static DateTime _createdOrNow(dynamic created) {
    // Absent is the documented fallback; a present-but-wrong-shaped value is
    // contract drift worth a signal (same warn-on-wrong-shape as `_runCreated`
    // in thread_history_replay.dart, which differs only in resolving a bad
    // value to null instead of `now()`).
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
    } on FormatException catch (error, stackTrace) {
      // The message and the error carry only the `created` string, the
      // error's with a `Z` appended when it names no zone. The backend stamps
      // it, it is no secret, and it is what makes the record actionable.
      _logger.warning(
        'create: malformed `created` ($created); using the client clock.',
        error: error,
        stackTrace: stackTrace,
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
    String? database,
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(chunkId, 'chunkId');

    final queryParameters = <String, String>{'expand': '$expand'};
    if (refs != null && refs.isNotEmpty) {
      queryParameters['refs'] = jsonEncode(refs);
    }
    // Names the database the chunk came from, as its citation reports it.
    // Without it the backend asks every covered database in turn and the
    // first holding the id answers — which, since chunk ids repeat between
    // copies of a database, may not be the cited one.
    if (database != null && database.isNotEmpty) {
      queryParameters['database'] = database;
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

  /// Lists the files the agent left at the top level of the thread's sandbox
  /// workspace. The workspace persists across the thread's runs, so the list
  /// is the thread's, not any one run's.
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  ///
  /// Returns a list of [WorkdirFile] entries. Malformed entries in the
  /// response are logged and skipped.
  ///
  /// Throws:
  /// - [ArgumentError] if any parameter is empty
  /// - [NotFoundException] (404) if the server keeps no workspaces, serves
  ///   none, or knows no such thread
  /// - [AuthException] if not authenticated (401)
  /// - [PermissionDeniedException] if access is denied (403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<List<WorkdirFile>> getThreadWorkdirFiles(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');

    final response = await _transport.request<Map<String, dynamic>>(
      'GET',
      _urlBuilder.build(
        pathSegments: ['workdirs', roomId, 'thread', threadId],
      ),
      cancelToken: cancelToken,
    );

    return _parseFileList(response, 'files', workdirFileFromJson);
  }

  /// Downloads one file from the thread's sandbox workspace.
  ///
  /// Buffers the entire response in memory; intended for the small text /
  /// data files agents typically produce. Multi-hundred-MB downloads should
  /// use a streaming endpoint (not yet implemented).
  ///
  /// Parameters:
  /// - [roomId]: The room ID (must not be empty)
  /// - [threadId]: The thread ID (must not be empty)
  /// - [filename]: A name from [getThreadWorkdirFiles] (must not be empty)
  ///
  /// Returns the raw file bytes.
  ///
  /// Throws:
  /// - [ArgumentError] if any parameter is empty
  /// - [NotFoundException] (404) if the workspace is not served or holds no
  ///   regular file by that name
  /// - [AuthException] if not authenticated (401)
  /// - [PermissionDeniedException] if access is denied (403)
  /// - [NetworkException] if connection fails
  /// - [ApiException] for other server errors
  /// - [CancelledException] if cancelled via [cancelToken]
  Future<Uint8List> getThreadWorkdirFile(
    String roomId,
    String threadId,
    String filename, {
    CancelToken? cancelToken,
  }) {
    _requireNonEmpty(roomId, 'roomId');
    _requireNonEmpty(threadId, 'threadId');
    _requireNonEmpty(filename, 'filename');

    return _transport.requestBytes(
      'GET',
      _urlBuilder.build(
        pathSegments: [
          'workdirs',
          roomId,
          'thread',
          threadId,
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
