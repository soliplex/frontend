import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadKey;
import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthException,
        CancelToken,
        MalformedResponseException,
        PermissionDeniedException,
        RagDocument,
        ReconnectFailed,
        ReconnectStatus,
        Reconnected,
        Reconnecting,
        Room,
        SourceReferenceFormatting,
        buildDocumentFilter;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../core/util/debouncer.dart';
import '../../../core/routes.dart';
import '../../auth/return_to_storage.dart';
import '../../auth/server_entry.dart';
import '../../lobby/lobby_read_markers.dart';
import '../anchor_tracker.dart';
import '../room_run_activity.dart';
import '../room_unread.dart';
import '../thread_read_markers.dart';
import '../unread_boundary.dart';
import '../document_selections.dart';
import '../pick_file.dart';
import '../agent_runtime_manager.dart';
import '../room_state.dart';
import '../run_registry.dart';
import '../thread_list_state.dart';
import '../thread_view_state.dart';
import '../compute_display_messages.dart';
import '../workdir_controller.dart';
import 'approval_handler.dart';
import 'chat_input.dart';
import 'chunk_visualization_page.dart';
import 'document_picker.dart';
import 'error_retry_panel.dart';
import 'message_timeline.dart';
import 'async_action_dialog.dart';
import 'room_rail.dart';
import 'room_welcome.dart';
import 'thread_sidebar.dart';
import '../../auth/auth_tokens.dart';
import 'upload_event_banner.dart';
import '../upload_tracker.dart';
import '../upload_tracker_registry.dart';
import 'package:soliplex_design/soliplex_design.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.room_screen');

const double _sidebarWidth = 300;

/// Caps the conversation column (message timeline + chat input) so it stays
/// readable and centered on ultrawide displays instead of stretching edge to
/// edge. Below this width the content fills the available space.
const double _maxContentWidth = SoliplexBreakpoints.desktop;

/// Builds the label for the file indicator chip in the room header.
///
/// Shows separate counts for room and thread uploads. At least one
/// count must be positive.
String uploadChipLabel(int roomCount, int threadCount) {
  assert(roomCount > 0 || threadCount > 0);
  if (roomCount > 0 && threadCount > 0) {
    return '$roomCount room \u00b7 $threadCount thread';
  }
  if (roomCount > 0) return '$roomCount room';
  return '$threadCount thread';
}

/// Resolves a display identity from an OIDC `/api/user_info` payload, trying
/// the most specific label first: the full name (`given_name` + `family_name`),
/// then `preferred_username`, then `email`, falling back to a generic
/// "Signed in" when the payload carries no usable label. The returned email is
/// null when absent so the rail's account header can omit the secondary line.
RoomAccount accountFromJson(Map<String, dynamic> json) {
  // Read each claim independently: a non-string value is treated as absent so
  // one malformed field can't discard its valid siblings.
  String claim(String key) {
    final value = json[key];
    return value is String ? value : '';
  }

  final given = claim('given_name');
  final family = claim('family_name');
  final preferred = claim('preferred_username').trim();
  final email = claim('email').trim();
  final full = '$given $family'.trim();
  final hasName = full.isNotEmpty || preferred.isNotEmpty;
  final name = [full, preferred, email]
      .firstWhere((s) => s.isNotEmpty, orElse: () => signedInLabel);
  // Omit the email line when the email is doubling as the name, so the header
  // doesn't render the same string twice.
  return (name: name, email: hasName && email.isNotEmpty ? email : null);
}

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.threadId,
    required this.runtimeManager,
    required this.registry,
    required this.uploadRegistry,
    this.enableDocumentFilter = false,
    required this.documentSelections,
    this.readMarkers,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;
  final AgentRuntimeManager runtimeManager;
  final RunRegistry registry;
  final UploadTrackerRegistry uploadRegistry;
  final bool enableDocumentFilter;
  final DocumentSelections documentSelections;

  /// Shared in-memory room read markers, also watched by the lobby. Stamping a
  /// room read here is visible to the lobby immediately, with no storage race.
  /// Null in tests, where each screen gets its own isolated store.
  final RoomReadMarkers? readMarkers;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late RoomState _state;
  late WorkdirController _workdirs;
  void Function()? _autoSelectUnsub;
  final _chatController = TextEditingController();
  final _chatFocusNode = FocusNode();
  bool _filesExpanded = false;

  /// The current server's rooms for the rail; `null` while loading.
  List<Room>? _serverRooms;
  Object? _serverRoomsError;
  CancelToken? _roomsCancelToken;

  /// Last-activity per room id for the current server (from the room stats
  /// batch). Absent/empty when stats are unavailable — which simply shows no
  /// unread dots (graceful on a pre-stats backend). Drives [_unreadRoomIds]
  /// together with [_readMarkers].
  Map<String, DateTime?> _roomActivity = const {};
  CancelToken? _activityCancelToken;

  /// Shared in-memory model of per-`(serverId, roomId)` "last seen" markers,
  /// also watched by the lobby. A room is unread when its last-activity is
  /// newer than its marker; opening a room here stamps "now", clearing its dot
  /// here and — immediately, no storage race — in the lobby.
  late final RoomReadMarkers _readMarkers;

  /// Per-`(serverId, roomId, threadId)` "last seen" markers for threads,
  /// device-local. A thread is unread when its [ThreadInfo.lastActivity] is
  /// newer than its marker; opening a thread stamps "now". Distinct store from
  /// the room markers (different granularity), but the same pattern.
  Map<ThreadActivityKey, DateTime> _threadReadMarkers = const {};

  /// Recreated on room change so a fresh room starts with no frozen boundary
  /// (the divider never carries over from the previous room) and a transient
  /// disk-load failure is retried on the next room rather than disabling the
  /// divider for the rest of the screen's life.
  late AnchorTracker _anchorTracker;

  /// Disposer for the active thread's message subscription that advances the
  /// anchor. Re-wired on thread switch, cancelled on dispose.
  void Function()? _anchorAdvanceUnsub;

  /// Disposer for the thread-list subscription that keeps the room read marker
  /// in sync with thread-unread state. Re-wired on room change, cancelled on
  /// dispose.
  void Function()? _roomReadUnsub;

  /// Snapshot of the registry's active run keys, to detect active→terminal
  /// transitions for the rail's room-activity dots. Seeded before subscribing.
  Set<ThreadKey> _previousActiveKeys = const {};

  /// Disposer for the registry subscription that refetches room activity when a
  /// run on this server finishes (so a background reply lights another room's
  /// rail dot). Cancelled on dispose.
  void Function()? _serverActivityUnsub;

  /// Coalesces bursts of run completions into a single room-activity refetch.
  final Debouncer _roomActivityRefresh =
      Debouncer(const Duration(milliseconds: 300));

  /// Best-effort account identity for the rail's footer menu; `null` until
  /// resolved (or when the server is unauthenticated / the fetch fails).
  RoomAccount? _account;

  /// Bumped on each account fetch so a slow in-flight request for a previous
  /// server can't write its identity onto the current one. The raw
  /// `/api/user_info` request can't be cancelled, so we guard the result
  /// against the latest generation instead.
  int _accountFetchGeneration = 0;

  /// Whether [_threadReadMarkers] holds a change not yet written to disk.
  /// Survives a failed write so the next stamp retries it instead of losing it.
  bool _threadMarkersDirty = false;

  /// Guards [_flushThreadReadMarkers] so only one write runs at a time.
  bool _flushingThreadMarkers = false;

  bool get _filterEnabled => widget.enableDocumentFilter;

  /// Whether the room exposes any filterable documents/datasets. Resolved
  /// asynchronously by [_refreshFilterableDocuments]; starts `false` so the
  /// filter button pops in once a non-empty corpus is confirmed rather than
  /// flashing and disappearing for empty rooms.
  bool _hasFilterableDocuments = false;

  /// Set when the document fetch fails. We can't tell whether the room has a
  /// corpus, so the filter button stays visible to avoid stripping the
  /// affordance on a transient network error — the picker handles its own
  /// retry.
  bool _filterDocsLoadFailed = false;

  CancelToken? _filterDocsCancelToken;

  /// Show the filter button only when filtering is enabled and there is
  /// something to filter (or we failed to find out).
  bool get _showDocumentFilter =>
      _filterEnabled && (_hasFilterableDocuments || _filterDocsLoadFailed);

  DocumentSelections get _documentSelections => widget.documentSelections;

  Set<RagDocument> get _selectedDocuments => _filterEnabled
      ? _documentSelections.get(widget.roomId, widget.threadId)
      : const {};

  void _updateSelection(Set<RagDocument> selection) {
    setState(() {
      _documentSelections.set(widget.roomId, widget.threadId, selection);
    });
  }

  /// Fetches the room's document corpus to decide whether the filter button
  /// should be shown. No-op when filtering is disabled. Cancels any in-flight
  /// fetch so a room switch can't apply a stale result.
  void _refreshFilterableDocuments() {
    if (!_filterEnabled) return;
    _filterDocsCancelToken?.cancel('refresh');
    final token = CancelToken();
    _filterDocsCancelToken = token;
    widget.serverEntry.connection.api
        .getDocuments(widget.roomId, cancelToken: token)
        .then((docs) {
      if (!mounted || token != _filterDocsCancelToken) return;
      setState(() {
        _hasFilterableDocuments = docs.isNotEmpty;
        _filterDocsLoadFailed = false;
      });
    }).catchError((Object error, StackTrace stackTrace) {
      if (!mounted || token != _filterDocsCancelToken) return;
      _logger.error(
        'Failed to load filterable documents',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() => _filterDocsLoadFailed = true);
    });
  }

  /// Fetches the current server's room list for the rail. Cancels any
  /// in-flight fetch so a server switch can't apply a stale result.
  void _fetchServerRooms() {
    final entry = widget.serverEntry;
    _roomsCancelToken?.cancel('refresh');
    final token = CancelToken();
    _roomsCancelToken = token;
    // Assigned directly (not via setState): this runs from initState too, and
    // the async callbacks below trigger the rebuild once a result lands.
    _serverRooms = null;
    _serverRoomsError = null;
    entry.connection.api.getRooms(cancelToken: token).then((rooms) {
      if (!mounted || token != _roomsCancelToken) return;
      setState(() => _serverRooms = rooms);
    }).catchError((Object error, StackTrace stackTrace) {
      if (error is AuthException) {
        // The captured entry's session has expired; funnel it so the route
        // guard redirects to login even if we have since switched servers.
        // Leaving the loading state means no error banner flashes first.
        entry.auth.markSessionExpired();
        return;
      }
      if (!mounted || token != _roomsCancelToken) return;
      // A PermissionDeniedException (403) is an expected steady state — the
      // server denies access and re-auth won't help — and the rail surfaces it
      // inline, so keep it below the severe channel reserved for genuine
      // failures. Still log it at debug so a misconfigured ACL leaves a trace.
      if (error is PermissionDeniedException) {
        _logger.debug('Rooms fetch denied (403)');
      } else {
        _logger.error(
          'Failed to load server rooms',
          error: error,
          stackTrace: stackTrace,
        );
      }
      setState(() => _serverRoomsError = error);
    });
  }

  /// Fetches last-activity for the current server's rooms in one batch so the
  /// rail can mark rooms with unseen activity as unread. Mirrors the lobby's
  /// fetch. Degrades to no dots on any failure (e.g. a pre-stats backend 404).
  void _fetchRoomActivity() {
    _activityCancelToken?.cancel('refresh');
    final token = CancelToken();
    _activityCancelToken = token;
    widget.serverEntry.connection.api
        .getRoomsStats(cancelToken: token)
        .then((stats) {
      if (!mounted || token != _activityCancelToken) return;
      setState(() {
        _roomActivity = {
          for (final entry in stats.entries)
            entry.key: entry.value.lastActivity,
        };
      });
      // Room activity is a recompute input that arrives on its own schedule;
      // re-evaluate the room read state now that the stamp guard has it.
      _recomputeRoomRead();
    }).catchError((Object error, StackTrace stackTrace) {
      if (!mounted || token != _activityCancelToken) return;
      _logger.warning(
        'Failed to load room activity; unread dots disabled',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() => _roomActivity = const {});
    });
  }

  /// Loads the shared read markers once, then re-evaluates the room read state
  /// in case the thread list arrived before them.
  Future<void> _loadReadMarkers() async {
    await _readMarkers.ensureLoaded();
    if (mounted) _recomputeRoomRead();
  }

  /// Stamps [roomId] on the current server read as of now. Uses "now" (not the
  /// cached activity time) so the marker is at or after any observed activity,
  /// even if the activity batch is stale or pending. Only [_recomputeRoomRead]
  /// calls this, and only once no thread is unread. The shared store both
  /// persists and notifies its watchers (this build and the lobby's).
  void _markRoomRead(String roomId) {
    _readMarkers.markRead(
      (serverId: widget.serverEntry.serverId, roomId: roomId),
      clock.now().toUtc(),
    );
  }

  /// Marks the room being left read when none of its threads remains unread,
  /// stamping the room-level marker the lobby reads (it has no per-thread
  /// data). The per-thread leave stamp doesn't reach the lobby: only this
  /// marker does, and the in-room recompute can leave it behind activity the
  /// thread list hasn't surfaced yet — a message the user just sent, or a reply
  /// that landed as they left. Skips the stamp while any other thread is still
  /// unread so the room correctly stays unread. Safe from the dispose path: the
  /// store update is just a signal write, not setState.
  void _markRoomReadOnLeave({
    required String serverId,
    required String roomId,
    required String? leavingThreadId,
  }) {
    final status = _state.threadList.threads.value;
    if (status is! ThreadsLoaded) return;
    final stillUnread = unreadThreadIds(
      status.threads,
      _threadReadMarkers,
      serverId: serverId,
      roomId: roomId,
      selectedThreadId: leavingThreadId,
    ).isNotEmpty;
    if (stillUnread) return;
    _readMarkers.markRead(
      (serverId: serverId, roomId: roomId),
      clock.now().toUtc(),
    );
  }

  /// Marks the room read only when no thread is unread. While any thread is
  /// unread, the marker is left untouched so the room stays unread (the lobby
  /// comparison `roomActivity > roomMarker` then reports it). Stamps only on a
  /// genuine unread→read transition to avoid re-persisting on every update.
  void _recomputeRoomRead() {
    final status = _state.threadList.threads.value;
    if (status is! ThreadsLoaded) return;
    final key = (serverId: widget.serverEntry.serverId, roomId: widget.roomId);
    // Judge "mark read" from the thread list's own latest activity, not the
    // separately-fetched room-activity batch: when the batch refreshes before
    // the thread list does, a stale list must not mark the room read over a
    // thread about to surface as unread.
    if (shouldMarkRoomRead(
      status.threads,
      _threadReadMarkers,
      _readMarkers.value[key],
      serverId: widget.serverEntry.serverId,
      roomId: widget.roomId,
      selectedThreadId: widget.threadId,
    )) {
      _markRoomRead(widget.roomId);
    }
  }

  /// Subscribes the room read marker to thread-list changes. The subscription
  /// fires immediately with the current value, so this also performs the
  /// initial recompute.
  void _watchRoomRead() {
    _roomReadUnsub?.call();
    _roomReadUnsub = _state.threadList.threads.subscribe((_) {
      if (mounted) _recomputeRoomRead();
    });
  }

  /// Refetches the server's room-activity batch whenever a run on this server
  /// reaches a terminal state. The room-activity stats are otherwise only
  /// fetched on mount and server change, so a background run finishing in a
  /// room you've left would not surface on the rail until you re-entered it or
  /// opened the lobby. Debounced so a burst of completions makes one request.
  /// Survives in-server room switches (subscribed once, reads the current
  /// server id on each emission).
  void _watchServerActivity() {
    _previousActiveKeys = widget.registry.activeKeys.value;
    _serverActivityUnsub = widget.registry.activeKeys.subscribe((keys) {
      if (!mounted) return;
      final completed = serverRunCompleted(
        _previousActiveKeys,
        keys,
        serverId: widget.serverEntry.serverId,
      );
      _previousActiveKeys = keys;
      if (completed) {
        _roomActivityRefresh.run(_fetchRoomActivity);
      }
    });
  }

  /// Ids of the current server's rooms with unread activity, for the rail.
  ///
  /// Other rooms come from the room-activity batch. The open room is judged
  /// from its own thread-unread set instead: the batch counts the user's own
  /// just-seen reply (lighting a false dot for the room they're sitting in),
  /// whereas the thread-unread set excludes the open thread and surfaces only a
  /// genuinely unread sibling thread. Empty when activity is unavailable.
  Set<String> get _unreadRoomIds {
    final ids = unreadRoomIds(
      _roomActivity,
      _readMarkers.value,
      serverId: widget.serverEntry.serverId,
      currentRoomId: widget.roomId,
    );
    final openRoomUnread = _unreadThreadIds(
      _state.threadList.threads.value,
      _state.activeThreadView?.threadId,
    ).isNotEmpty;
    return openRoomUnread ? {...ids, widget.roomId} : ids;
  }

  /// Loads the thread read markers from disk, merging under any already set
  /// in-memory (an early [_markThreadRead] on mount).
  Future<void> _loadThreadReadMarkers() async {
    try {
      final loaded = await ThreadReadMarkerStorage.load();
      if (!mounted) return;
      setState(() => _threadReadMarkers = {...loaded, ..._threadReadMarkers});
      // Markers just loaded; re-evaluate the room read state in case the thread
      // list arrived before them.
      _recomputeRoomRead();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to load thread read markers',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Marks [threadId] on the current room as read as of now, clearing its
  /// unread dot. No-op when [threadId] is null (no thread open yet).
  void _markThreadRead(String? threadId) {
    if (threadId == null) return;
    _stampThreadRead((
      serverId: widget.serverEntry.serverId,
      roomId: widget.roomId,
      threadId: threadId,
    ));
  }

  /// Stamps [key]'s read marker to now and rebuilds for the cleared dot. When
  /// [recompute] is true (the default) it also re-evaluates the room rollup;
  /// callers that stamp before the room's thread list and coordinates line up
  /// pass false and let a later recompute on matching state do the rollup.
  void _stampThreadRead(ThreadActivityKey key, {bool recompute = true}) {
    setState(() {
      _threadReadMarkers = {..._threadReadMarkers, key: clock.now().toUtc()};
    });
    _persistThreadReadMarkers();
    if (recompute) _recomputeRoomRead();
  }

  /// Serializes thread-read-marker writes so only one is ever in flight:
  /// overlapping saves (rapid thread switches, or a switch immediately followed
  /// by dispose) race on the shared store, and a stale snapshot could otherwise
  /// land last and drop a just-stamped marker. Mirrors [AnchorTracker]'s flush.
  void _persistThreadReadMarkers() {
    _threadMarkersDirty = true;
    unawaited(_flushThreadReadMarkers());
  }

  Future<void> _flushThreadReadMarkers() async {
    if (_flushingThreadMarkers) return;
    _flushingThreadMarkers = true;
    try {
      while (_threadMarkersDirty) {
        _threadMarkersDirty = false;
        try {
          // Reads the latest map each pass; stamps replace [_threadReadMarkers]
          // rather than mutating it, so the newest snapshot always wins.
          await ThreadReadMarkerStorage.save(_threadReadMarkers);
        } catch (error, stackTrace) {
          // Keep the change pending so the next stamp retries it.
          _threadMarkersDirty = true;
          _logger.warning(
            'Failed to persist thread read markers',
            error: error,
            stackTrace: stackTrace,
          );
          return;
        }
      }
    } finally {
      _flushingThreadMarkers = false;
    }
  }

  /// Stamps the thread that was open before this update as read. Activity that
  /// arrives while a thread is open advances its `lastActivity` past the
  /// open-time marker; without this the thread would surface a false unread dot
  /// the moment it's deselected. Uses [oldWidget]'s coordinates because [widget]
  /// has already advanced to the new thread or room before this runs.
  ///
  /// Skips the room rollup: on a thread switch the incoming thread's open-stamp
  /// recomputes it, and on a room switch `_state` is rebuilt and `_watchRoomRead`
  /// recomputes it — both against a thread list whose coordinates match.
  void _markPreviousThreadRead(RoomScreen oldWidget) {
    final threadId = oldWidget.threadId;
    if (threadId == null) return;
    _stampThreadRead(
      (
        serverId: oldWidget.serverEntry.serverId,
        roomId: oldWidget.roomId,
        threadId: threadId,
      ),
      recompute: false,
    );
  }

  /// Snapshots the previous anchor for [threadId] (frozen for the divider) and
  /// wires a subscription that advances the stored anchor to the last real
  /// message id as messages arrive. Must run after `selectThread([threadId])`.
  void _beginUnreadTracking(String threadId) {
    _anchorAdvanceUnsub?.call();
    _anchorAdvanceUnsub = null;

    _anchorTracker.beginThread((
      serverId: widget.serverEntry.serverId,
      roomId: widget.roomId,
      threadId: threadId,
    ));

    final view = _state.activeThreadView;
    if (view == null || view.threadId != threadId) return;

    _anchorAdvanceUnsub = view.messages.subscribe((status) {
      if (!mounted) return;
      if (status is! MessagesLoaded) return;
      _anchorTracker.advance(lastRealMessageId(status.messages));
    });
  }

  /// Ids of the room's threads with activity newer than the user last saw.
  /// The selected thread is excluded — you're looking at it, so it reads as
  /// read even if its activity advances while open.
  Set<String> _unreadThreadIds(
    ThreadListStatus status,
    String? selectedThreadId,
  ) {
    if (status is! ThreadsLoaded) return const {};
    return unreadThreadIds(
      status.threads,
      _threadReadMarkers,
      serverId: widget.serverEntry.serverId,
      roomId: widget.roomId,
      selectedThreadId: selectedThreadId,
    );
  }

  /// Best-effort fetch of the signed-in identity for the rail's account menu.
  /// No-op (and clears the cached account) when the server is unauthenticated;
  /// a failure falls back to the generic "Signed in" label.
  //
  // TODO: The fetch + parse here duplicate the lobby's `_fetchUserProfile` /
  // `UserProfile.fromJson` against the same `/api/user_info` endpoint. Collapse
  // them into one shared `fetchUserInfo(ServerEntry)` helper. The room can't
  // reuse the lobby's cache because `LobbyState` is screen-scoped.
  void _fetchAccount() {
    final entry = widget.serverEntry;
    // Direct assignments here (not setState): this may run from initState
    // before the first build, and the async callbacks below trigger the
    // rebuild once a result lands. Clearing eagerly drops the previous
    // server's identity instead of letting it linger through the switch.
    _account = null;
    final generation = ++_accountFetchGeneration;
    if (!entry.requiresAuth || entry.auth.session.value is! ActiveSession) {
      return;
    }
    final url = entry.serverUrl.resolve('/api/user_info');
    Future.sync(() => entry.httpClient.request('GET', url)).then((response) {
      // entry.httpClient is the raw decorator chain (no HttpTransport), so a
      // 401 arrives as a response rather than a thrown AuthException — funnel
      // it to the session explicitly. The captured entry's session is expired
      // even if we have since switched servers, so this fires regardless of
      // the staleness guard below.
      if (response.statusCode == 401) {
        entry.auth.markSessionExpired();
        return;
      }
      if (!mounted || generation != _accountFetchGeneration) return;
      if (response.statusCode != 200) {
        // A 403 is the expected steady state for a permission-restricted
        // profile endpoint, so log it below the warning channel reserved for
        // genuine 5xx / decode failures — debuggable without crying wolf.
        final message = 'Account profile fetch returned ${response.statusCode}';
        if (response.statusCode == 403) {
          _logger.debug(message);
        } else {
          _logger.warning(message);
        }
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        // A 200 whose body isn't a JSON object is a backend/proxy contract
        // break (an HTML error page, a bare array), distinct from a network
        // drop — log it on its own so it isn't read as "no profile".
        _logger.warning(
          'Account profile response was not a JSON object (status 200)',
        );
        return;
      }
      setState(() => _account = accountFromJson(decoded));
    }).catchError((Object error, StackTrace stackTrace) {
      if (error is AuthException) {
        entry.auth.markSessionExpired();
        return;
      }
      _logger.warning(
        'Failed to load account profile',
        error: error,
        stackTrace: stackTrace,
      );
    });
  }

  Future<void> _openDocumentPicker() async {
    final roomId = widget.roomId;
    final threadId = widget.threadId;
    final result = await showDocumentPicker(
      context: context,
      fetchDocuments: () =>
          widget.serverEntry.connection.api.getDocuments(roomId),
      selected: _documentSelections.get(roomId, threadId),
    );
    if (result != null && mounted) {
      setState(() {
        _documentSelections.set(roomId, threadId, result);
      });
    }
  }

  // TODO: If a selected document is deleted server-side before send,
  // the backend silently returns empty results. Consider reconciling
  // selections against the fetched document list.
  Map<String, dynamic>? _buildStateOverlay() {
    if (!_filterEnabled) return null;
    final selected = _selectedDocuments;
    return {
      'rag': <String, dynamic>{
        'document_filter':
            selected.isEmpty ? null : buildDocumentFilter(selected.toList()),
      },
    };
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _readMarkers = widget.readMarkers ?? RoomReadMarkers();
    _state = _createRoomState();
    _workdirs = _createWorkdirController();
    _refreshFilterableDocuments();
    _fetchServerRooms();
    _fetchRoomActivity();
    unawaited(_loadReadMarkers());
    unawaited(_loadThreadReadMarkers());
    _anchorTracker = _createAnchorTracker();
    // Keep the room's unread dot derived from its threads: watch the thread
    // list and mark the room read only once no thread is unread.
    _watchRoomRead();
    // Refetch the server's room-activity batch when any run on this server
    // finishes, so a background reply lights another room's rail dot even while
    // you stay in the current room.
    _watchServerActivity();
    _markThreadRead(widget.threadId);
    _fetchAccount();
    if (widget.threadId != null) {
      _state.selectThread(widget.threadId!);
      _beginUnreadTracking(widget.threadId!);
    } else {
      _autoSelectFirstThread();
    }
    unawaited(_restorePersistedComposer());
  }

  /// Restores a composer draft that was persisted across an
  /// auth-failure redirect for this `(serverId, roomId)`. No-op if
  /// the controller already has text (user typed something since
  /// mount, or another restoration path already populated it).
  ///
  /// Storage failures are logged at SEVERE and swallowed; an empty
  /// composer is the safe fallback.
  Future<void> _restorePersistedComposer() async {
    try {
      final text = await ReturnToStorage.loadComposer(
        serverId: widget.serverEntry.serverId,
        roomId: widget.roomId,
      );
      if (!mounted || text == null) return;
      if (_chatController.text.isNotEmpty) return;
      _chatController.text = text;
      _chatController.selection =
          TextSelection.collapsed(offset: _chatController.text.length);
      // One-shot: clear once restored so subsequent mounts of the same
      // room don't re-pre-fill the box with stale content.
      await ReturnToStorage.clearComposer(
        serverId: widget.serverEntry.serverId,
        roomId: widget.roomId,
      );
    } catch (e, st) {
      _logger.error(
        'Failed to restore persisted composer draft',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void didUpdateWidget(RoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverChanged =
        widget.serverEntry.serverId != oldWidget.serverEntry.serverId;
    final roomChanged = widget.roomId != oldWidget.roomId || serverChanged;
    if (roomChanged || widget.threadId != oldWidget.threadId) {
      _markPreviousThreadRead(oldWidget);
    }
    if (roomChanged) {
      // Mark the room being left read (under its own coordinates) before its
      // _state is torn down, so the lobby agrees the user caught up there.
      _markRoomReadOnLeave(
        serverId: oldWidget.serverEntry.serverId,
        roomId: oldWidget.roomId,
        leavingThreadId: oldWidget.threadId,
      );
      _cancelAutoSelect();
      _roomReadUnsub?.call();
      _roomReadUnsub = null;
      _anchorAdvanceUnsub?.call();
      _anchorAdvanceUnsub = null;
      _state.dispose();
      unawaited(_anchorTracker.dispose());
      _chatController.clear();
      _state = _createRoomState();
      _workdirs = _createWorkdirController();
      _anchorTracker = _createAnchorTracker();
      _hasFilterableDocuments = false;
      _filterDocsLoadFailed = false;
      _refreshFilterableDocuments();
      _watchRoomRead();
      _markThreadRead(widget.threadId);
      // Room list, account identity, and room-activity stats are all
      // server-scoped: refetch only on a server change, not on every in-server
      // room switch (which would otherwise flash the rail back to a spinner and
      // fire redundant requests). The room's unread dot is kept in sync by
      // _watchRoomRead above, which re-subscribes to the new room's thread list.
      if (serverChanged) {
        _fetchServerRooms();
        _fetchRoomActivity();
        _fetchAccount();
      }
      if (widget.threadId != null) {
        _state.selectThread(widget.threadId!);
        _beginUnreadTracking(widget.threadId!);
      } else {
        _autoSelectFirstThread();
      }
    } else if (widget.threadId != oldWidget.threadId) {
      if (widget.threadId != null) {
        _cancelAutoSelect();
        _chatController.clear();
        _workdirs.clearCache();
        _markThreadRead(widget.threadId);
        if (_filterEnabled && oldWidget.threadId == null) {
          _documentSelections.migrateToThread(widget.roomId, widget.threadId!);
        }
        _state.selectThread(widget.threadId!);
        _beginUnreadTracking(widget.threadId!);
        setState(() {});
      } else {
        _autoSelectFirstThread();
      }
    }
  }

  void _autoSelectFirstThread() {
    final current = _state.threadList.threads.value;
    if (current is ThreadsLoaded && current.threads.isNotEmpty) {
      _navigateToThread(current.threads.first.id, replace: true);
      return;
    }

    final targetState = _state;
    _autoSelectUnsub = _state.threadList.threads.subscribe((status) {
      if (!mounted || targetState != _state) return;
      if (status is ThreadsLoaded && status.threads.isNotEmpty) {
        _cancelAutoSelect();
        _navigateToThread(status.threads.first.id, replace: true);
      }
    });
  }

  RoomState _createRoomState() => RoomState(
        serverEntry: widget.serverEntry,
        roomId: widget.roomId,
        runtimeManager: widget.runtimeManager,
        registry: widget.registry,
        uploadRegistry: widget.uploadRegistry,
        onNavigateToThread: (id) => _navigateToThread(id),
      );

  WorkdirController _createWorkdirController() => WorkdirController(
        api: widget.serverEntry.connection.api,
        roomId: widget.roomId,
      );

  AnchorTracker _createAnchorTracker() {
    final tracker = AnchorTracker();
    unawaited(tracker.loadFromDisk().then((_) {
      if (mounted) setState(() {});
    }));
    return tracker;
  }

  void _navigateToThread(String? threadId, {bool replace = false}) {
    if (!mounted) return;
    final alias = widget.serverEntry.alias;
    final roomId = widget.roomId;
    final path = threadId != null
        ? AppRoutes.thread(alias, roomId, threadId)
        : AppRoutes.room(alias, roomId);
    if (replace || widget.threadId == null) {
      context.replace(path);
    } else {
      context.go(path);
    }
  }

  void _cancelAutoSelect() {
    _autoSelectUnsub?.call();
    _autoSelectUnsub = null;
  }

  @override
  void dispose() {
    // Stamp the open thread read on the way out, as the deselect path does:
    // the user has seen this thread's activity, so it must not surface a false
    // unread dot when they return. Save-only — no setState while disposing.
    final threadId = widget.threadId;
    if (threadId != null) {
      _threadReadMarkers = {
        ..._threadReadMarkers,
        (
          serverId: widget.serverEntry.serverId,
          roomId: widget.roomId,
          threadId: threadId,
        ): clock.now().toUtc(),
      };
      _persistThreadReadMarkers();
    }
    // Bring the room-level marker up to now too, so the lobby reflects that the
    // user caught up here. Reads _state before it is disposed below.
    _markRoomReadOnLeave(
      serverId: widget.serverEntry.serverId,
      roomId: widget.roomId,
      leavingThreadId: threadId,
    );
    _cancelAutoSelect();
    _anchorAdvanceUnsub?.call();
    _roomReadUnsub?.call();
    _serverActivityUnsub?.call();
    _roomActivityRefresh.cancel();
    _filterDocsCancelToken?.cancel('disposed');
    _roomsCancelToken?.cancel('disposed');
    _activityCancelToken?.cancel('disposed');
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _state.dispose();
    unawaited(_anchorTracker.dispose());
    _chatController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (_chatFocusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    _chatFocusNode.requestFocus();
    return false;
  }

  void _onBackToLobby() => context.go(AppRoutes.lobby);

  /// Drives the user back through sign-in for this server, returning to the
  /// current room/thread afterward. Reached only if an [AuthException]
  /// surfaces in an error panel despite the funnel-to-redirect path.
  void _onReauthenticate() {
    final alias = widget.serverEntry.alias;
    final roomId = widget.roomId;
    final threadId = widget.threadId;
    final returnTo = threadId != null
        ? AppRoutes.thread(alias, roomId, threadId)
        : AppRoutes.room(alias, roomId);
    context.go(
      AppRoutes.homeWithUrl(
        widget.serverEntry.serverUrl.toString(),
        returnTo: returnTo,
      ),
    );
  }

  void _onNetworkInspector() => context.push(AppRoutes.networkInspector);

  void _onVersions() => context.push(AppRoutes.versions);

  void _onRoomInfo() {
    context.push(
      AppRoutes.roomInfo(widget.serverEntry.alias, widget.roomId),
    );
  }

  Future<List<PickedFile>> _pickWithErrorSurfacing(
    Future<PickFilesResult?> Function() pick, {
    String? threadId,
  }) async {
    final PickFilesResult? result;
    try {
      result = await pick();
    } on PickFilePickerException catch (e, st) {
      if (!mounted) return const [];
      _logger.error(
        'Pick failed',
        error: e.cause,
        stackTrace: st,
      );
      _state.uploadTracker.recordClientError(
        roomId: widget.roomId,
        threadId: threadId,
        filename: '(unknown)',
        message: pickerErrorMessage(e.cause),
      );
      return const [];
    }
    if (result == null || !mounted) return const [];
    for (final itemError in result.errors) {
      _logger.error(
        'Pick failed for ${itemError.filename}',
        error: itemError.cause,
      );
      _state.uploadTracker.recordClientError(
        roomId: widget.roomId,
        threadId: threadId,
        filename: itemError.filename,
        message: pickerErrorMessage(itemError.cause),
      );
    }
    return result.files;
  }

  void _enqueueUploadsToThread(String threadId, List<PickedFile> files) {
    for (final file in files) {
      _state.uploadTracker.uploadToThread(
        roomId: widget.roomId,
        threadId: threadId,
        filename: file.name,
        openStream: file.openStream,
        contentLength: file.size,
        mimeType: file.mimeType,
        webFileBlob: file.webFileBlob,
      );
    }
  }

  Future<void> _pickAndUploadToThread(
    String threadId,
    Future<PickFilesResult?> Function() pick,
  ) async {
    final files = await _pickWithErrorSurfacing(pick, threadId: threadId);
    if (!mounted) return;
    _enqueueUploadsToThread(threadId, files);
  }

  Future<void> _pickAndUploadToNewThread(
    Future<PickFilesResult?> Function() pick,
  ) async {
    // Read errors before thread creation attach to the room scope
    // since there's no thread yet to route them to.
    final files = await _pickWithErrorSurfacing(pick);
    if (files.isEmpty || !mounted) return;

    final threadId = await _state.createThread();
    if (threadId == null || !mounted) return;

    _enqueueUploadsToThread(threadId, files);
  }

  void _onThreadSelected(String threadId) {
    context.go(
      AppRoutes.thread(widget.serverEntry.alias, widget.roomId, threadId),
    );
  }

  void _onQuizTapped(String quizId) {
    context.go(
      AppRoutes.quiz(widget.serverEntry.alias, widget.roomId, quizId),
    );
  }

  Future<void> _showRenameDialog(String threadId, String currentName) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RenameDialog(
        initialName: currentName,
        onAction: (name) => _state.threadList.renameThread(threadId, name),
      ),
    );
  }

  Future<void> _showDeleteDialog(String threadId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AsyncActionDialog(
        title: 'Delete Thread',
        contentBuilder: (_) =>
            const Text('Delete this thread? This cannot be undone.'),
        actionLabel: 'Delete',
        isDestructive: true,
        onAction: () => _state.deleteThread(threadId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the rail's room dots when a read marker is stamped (here or by
    // the lobby). Marker writes go through the shared store, not setState.
    _readMarkers.markers.watch(context);
    final threadListStatus = _state.threadList.threads.watch(context);
    final selectedThreadId = _state.activeThreadView?.threadId;
    final unreadThreadIds =
        _unreadThreadIds(threadListStatus, selectedThreadId);
    final roomStatus = _state.room.watch(context);
    final room = roomStatus is RoomLoaded ? roomStatus.room : null;
    final roomName = room?.name ?? widget.roomId;

    return Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= SoliplexBreakpoints.tablet;
          final sidebar = ThreadSidebar(
            threadListStatus: threadListStatus,
            selectedThreadId: selectedThreadId,
            onThreadSelected: _onThreadSelected,
            onBackToLobby: _onBackToLobby,
            onCreateThread: _state.createThread,
            onRetryThreads: () => _state.threadList.refresh(),
            onReauthenticate: _onReauthenticate,
            quizzes: room?.quizzes ?? const {},
            onQuizTapped: _onQuizTapped,
            onRenameThread: _showRenameDialog,
            onDeleteThread: _showDeleteDialog,
            runningThreadIds: _state.runningThreadIds,
            unreadThreadIds: unreadThreadIds,
          );
          final content = _buildContent(room);

          if (isWide) {
            return Scaffold(
              body: Row(
                children: [
                  SizedBox(width: RoomRail.width, child: _buildRail()),
                  const VerticalDivider(width: 1),
                  SizedBox(width: _sidebarWidth, child: sidebar),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: Text(roomName),
            ),
            drawer: Drawer(
              child: Builder(
                builder: (drawerContext) => SafeArea(
                  // Both panels fold into the drawer on narrow viewports: the
                  // rooms rail on the left, the thread list filling the rest.
                  child: Row(
                    children: [
                      SizedBox(
                        width: RoomRail.width,
                        child: _buildRail(
                          onNavigate: () => Navigator.pop(drawerContext),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: ThreadSidebar(
                          threadListStatus: threadListStatus,
                          selectedThreadId: selectedThreadId,
                          onThreadSelected: (threadId) {
                            Navigator.pop(drawerContext);
                            _onThreadSelected(threadId);
                          },
                          onBackToLobby: _onBackToLobby,
                          onCreateThread: () {
                            Navigator.pop(drawerContext);
                            _state.createThread();
                          },
                          runningThreadIds: _state.runningThreadIds,
                          unreadThreadIds: unreadThreadIds,
                          onRetryThreads: () => _state.threadList.refresh(),
                          onReauthenticate: _onReauthenticate,
                          quizzes: room?.quizzes ?? const {},
                          onQuizTapped: _onQuizTapped,
                          onRenameThread: (id, name) {
                            Navigator.pop(drawerContext);
                            _showRenameDialog(id, name);
                          },
                          onDeleteThread: (id) {
                            Navigator.pop(drawerContext);
                            _showDeleteDialog(id);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            body: content,
          );
        },
      ),
    );
  }

  /// Builds the always-visible rooms rail. [onNavigate] (the drawer pop) runs
  /// before any navigation when the rail lives inside the narrow drawer.
  Widget _buildRail({VoidCallback? onNavigate}) {
    return RoomRail(
      rooms: _serverRooms,
      roomsError: _serverRoomsError,
      onRetryRooms: () => setState(_fetchServerRooms),
      unreadRoomIds: _unreadRoomIds,
      selectedRoomId: widget.roomId,
      onSelectRoom: (roomId) {
        onNavigate?.call();
        if (roomId == widget.roomId) return;
        context.go(AppRoutes.room(widget.serverEntry.alias, roomId));
      },
      entry: widget.serverEntry,
      account: _account,
      onNetworkInspector: () {
        onNavigate?.call();
        _onNetworkInspector();
      },
      onVersions: () {
        onNavigate?.call();
        _onVersions();
      },
    );
  }

  void _restoreUnsentText(String? unsentText) {
    if (unsentText == null || _chatController.text.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatController.text = unsentText;
      _chatController.selection =
          TextSelection.collapsed(offset: _chatController.text.length);
    });
  }

  Widget _buildContent(Room? room) {
    final threadView = _state.activeThreadView;
    final attachEnabled = room?.enableAttachments ?? false;
    final messagesStatus = threadView?.messages.watch(context);

    final UploadsStatus roomStatus = attachEnabled
        ? _state.uploadTracker.roomUploads(widget.roomId).watch(context)
        : const UploadsLoaded(<DisplayUpload>[]);
    final threadId = threadView?.threadId;
    final UploadsStatus threadStatus = attachEnabled && threadId != null
        ? _state.uploadTracker
            .threadUploads(widget.roomId, threadId)
            .watch(context)
        : const UploadsLoaded(<DisplayUpload>[]);

    final body = threadView == null || messagesStatus == null
        ? _buildNoThreadBody(room)
        : _buildThreadBody(threadView, room, messagesStatus);

    return Column(
      children: [
        _buildRoomHeader(room, roomStatus, threadStatus),
        if (_filesExpanded) _buildFilePanel(roomStatus, threadStatus),
        Expanded(child: _capWidth(body)),
        _capWidth(_buildChatInput(threadView, room, messagesStatus)),
      ],
    );
  }

  /// Centers [child] within [_maxContentWidth] so the conversation column does
  /// not stretch across ultrawide displays. A no-op on narrower viewports,
  /// where the child already fits inside the cap.
  Widget _capWidth(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: child,
        ),
      );

  Widget _buildRoomHeader(
    Room? room,
    UploadsStatus roomStatus,
    UploadsStatus threadStatus,
  ) {
    final theme = Theme.of(context);
    final roomName = room?.name ?? widget.roomId;
    final documentsButton =
        _buildDocumentsButton(roomStatus, threadStatus, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s4, vertical: SoliplexSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Expanded (not Flexible + Spacer): the title eats the leading
          // space and pins the trailing buttons to the right edge. A Flexible
          // beside a Spacer would split the free space and leave the buttons
          // stranded mid-row.
          Expanded(
            child: Text(
              roomName,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (documentsButton != null) documentsButton,
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Room info',
            onPressed: _onRoomInfo,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// The top-right documents button: a simple icon toggle for the attached-
  /// files panel. Returns null to hide it when both scopes are Loaded-empty.
  /// The icon reflects upload state (spinner while in flight, error glyph on
  /// failure); the file count appears in the tooltip once both scopes load.
  Widget? _buildDocumentsButton(
    UploadsStatus roomStatus,
    UploadsStatus threadStatus,
    ThemeData theme,
  ) {
    final roomFiles = _uploadsOrNull(roomStatus);
    final threadFiles = _uploadsOrNull(threadStatus);

    final anyLoading =
        roomStatus is UploadsLoading || threadStatus is UploadsLoading;
    final anyFailed =
        roomStatus is UploadsFailed || threadStatus is UploadsFailed;

    if (!_scopeRendersContent(roomStatus) &&
        !_scopeRendersContent(threadStatus)) {
      return null;
    }

    final all = [...?roomFiles, ...?threadFiles];
    final anyPending = all.any((e) => e is PendingUpload);
    final anyUploadFailed = all.any((e) => e is FailedUpload);
    final isError = anyFailed || anyUploadFailed;

    final Widget icon;
    if (anyLoading || anyPending) {
      icon = const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (isError) {
      icon = Icon(Icons.error_outline, color: theme.colorScheme.error);
    } else {
      icon = const Icon(Icons.folder_outlined);
    }

    final label = (roomFiles != null && threadFiles != null)
        ? uploadChipLabel(roomFiles.length, threadFiles.length)
        : 'Attached files';

    return IconButton(
      icon: icon,
      isSelected: _filesExpanded,
      tooltip: label,
      onPressed: () => setState(() => _filesExpanded = !_filesExpanded),
    );
  }

  List<DisplayUpload>? _uploadsOrNull(UploadsStatus s) =>
      s is UploadsLoaded ? s.uploads : null;

  bool _scopeRendersContent(UploadsStatus s) => switch (s) {
        UploadsLoading() => true,
        UploadsLoaded(uploads: final u) => u.isNotEmpty,
        UploadsFailed() => true,
      };

  Widget _buildFilePanel(
    UploadsStatus roomStatus,
    UploadsStatus threadStatus,
  ) {
    final theme = Theme.of(context);
    final roomFiles = _uploadsOrNull(roomStatus);
    final threadFiles = _uploadsOrNull(threadStatus);
    final bothEmpty = (roomFiles?.isEmpty ?? true) &&
        (threadFiles?.isEmpty ?? true) &&
        roomStatus is UploadsLoaded &&
        threadStatus is UploadsLoaded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SoliplexSpacing.s2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
        // Cap the popover height so a large file list scrolls inside
        // the panel instead of pushing the chat input off-screen.
        // 40% of the viewport leaves room for the message timeline
        // and the input bar.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          // Right padding reserves space for the overlay scrollbar so
          // it doesn't sit on top of trailing close buttons (cancel /
          // dismiss) on file rows.
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: SoliplexSpacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bothEmpty)
                  Text(
                    'No files attached.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  )
                else ...[
                  _buildScopeSection('Room', roomStatus, theme),
                  // The divider sits between two visible sections. A
                  // scope is "visible" when it's Loading or Failed
                  // (those render a section row), or Loaded with at
                  // least one file.
                  if (_scopeRendersContent(roomStatus) &&
                      _scopeRendersContent(threadStatus))
                    const Divider(height: 12),
                  _buildScopeSection('Thread', threadStatus, theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScopeSection(
    String label,
    UploadsStatus status,
    ThemeData theme,
  ) {
    return switch (status) {
      UploadsLoading() => Row(
          children: [
            _sectionLabel(label, theme),
            const SizedBox(width: SoliplexSpacing.s2),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      UploadsLoaded(uploads: final list) when list.isEmpty => const SizedBox(),
      UploadsLoaded(uploads: final list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionLabel(label, theme),
            for (final entry in list) _buildFileRow(entry),
          ],
        ),
      UploadsFailed(error: final error) => Row(
          children: [
            _sectionLabel(label, theme),
            const SizedBox(width: SoliplexSpacing.s2),
            Expanded(
              child: Text(
                'Failed to load: ${uploadErrorMessage(error)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
    };
  }

  Widget _sectionLabel(String label, ThemeData theme) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFileRow(DisplayUpload entry) {
    final theme = Theme.of(context);
    final isFailed = entry is FailedUpload;
    final (icon, color, errorMessage) = switch (entry) {
      PersistedUpload() => (
          Icons.check_circle_outline,
          context.success,
          null,
        ),
      PendingUpload() => (null, theme.colorScheme.primary, null),
      FailedUpload(message: final m) => (
          Icons.error_outline,
          theme.colorScheme.onErrorContainer,
          m,
        ),
    };

    final (closeTooltip, closeAction) = switch (entry) {
      PendingUpload(:final id) => (
          'Cancel upload',
          () => _state.uploadTracker.cancelUpload(id)
        ),
      FailedUpload(:final id) => (
          'Dismiss',
          () => _state.uploadTracker.dismissFailed(id)
        ),
      _ => (null, null),
    };
    final closeColor = isFailed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.outline;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      padding: isFailed
          ? const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1)
          : const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s1, vertical: SoliplexSpacing.s1),
      decoration: isFailed
          ? BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(soliplexRadii.sm),
            )
          : null,
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 16, color: color)
          else
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
                value: switch (entry) {
                  PendingUpload(:final progress) => progress,
                  _ => null,
                },
              ),
            ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.filename,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isFailed ? theme.colorScheme.onErrorContainer : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (errorMessage != null)
                  Text(
                    errorMessage,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (closeAction != null)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: closeColor,
              tooltip: closeTooltip,
              onPressed: closeAction,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildNoThreadBody(Room? room) {
    final roomError = _state.lastError.watch(context);
    final sessionState = _state.sessionState.watch(context);
    _restoreUnsentText(roomError?.unsentText);

    return Column(
      children: [
        Expanded(
          child: RoomWelcome(
            room: room,
            onSuggestionTapped: sessionState != null
                ? null
                : (suggestion) => _state.sendToNewThread(
                      suggestion,
                      stateOverlay: _buildStateOverlay(),
                    ),
            onQuizTapped: _onQuizTapped,
            fallback: const Center(child: Text('Select a thread')),
          ),
        ),
        if (roomError != null)
          _SendErrorBanner(
            error: roomError,
            onDismiss: _state.clearError,
          ),
        if (room?.enableAttachments ?? false)
          UploadEventBanner(
            tracker: _state.uploadTracker,
            roomId: widget.roomId,
            threadId: null,
          ),
      ],
    );
  }

  Widget _buildThreadBody(
    ThreadViewState threadView,
    Room? room,
    ThreadViewStatus status,
  ) {
    final streaming = threadView.streamingState.watch(context);
    final sendError = threadView.lastSendError.watch(context);
    final reconnectStatus = threadView.reconnectStatus.watch(context);
    final attachEnabled = room?.enableAttachments ?? false;

    _restoreUnsentText(sendError?.unsentText);

    return Stack(
      children: [
        ApprovalHandler(
          pendingApproval: threadView.pendingApproval,
          onRespond: threadView.respondToApproval,
        ),
        Column(
          children: [
            if (reconnectStatus is Reconnecting ||
                reconnectStatus is Reconnected)
              _ReconnectBanner(
                status: reconnectStatus!,
                onDismiss: threadView.dismissReconnectStatus,
              ),
            Expanded(
              child: switch (status) {
                MessagesLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                MessagesFailed(:final error) => ErrorRetryPanel(
                    title: error is MalformedResponseException
                        ? "Couldn't display thread history"
                        : 'Failed to load messages',
                    error: error,
                    // Shape-drift is a backend bug — retry won't help, so
                    // hide the button rather than misleading the user.
                    onRetry: error is MalformedResponseException
                        ? null
                        : threadView.refresh,
                    onReauthenticate: _onReauthenticate,
                  ),
                MessagesLoaded(:final messages, :final messageStates) =>
                  computeDisplayMessages(messages, streaming).isEmpty
                      ? RoomWelcome(
                          room: room,
                          onSuggestionTapped: (suggestion) =>
                              threadView.sendMessage(
                            suggestion,
                            _state.runtime,
                            stateOverlay: _buildStateOverlay(),
                          ),
                          onQuizTapped: _onQuizTapped,
                          fallback: _threadEmptyFallback(context),
                        )
                      : MessageTimeline(
                          key: ValueKey(threadView.threadId),
                          roomId: widget.roomId,
                          messages: messages,
                          messageStates: messageStates,
                          streamingState: streaming,
                          unreadBoundary: _anchorTracker.boundary,
                          executionTrackers: threadView.executionTrackers,
                          onFeedbackSubmit: threadView.submitFeedback,
                          onInspect: (runId) => context.push(
                            AppRoutes.networkInspectorForRun(runId),
                          ),
                          onShowChunkVisualization: (ref) =>
                              ChunkVisualizationPage.show(
                            context: context,
                            api: widget.serverEntry.connection.api,
                            roomId: widget.roomId,
                            chunkId: ref.chunkId,
                            documentTitle: ref.displayTitle,
                            pageNumbers: ref.pageNumbers,
                          ),
                          onFetchWorkdirFiles: (runId) =>
                              _workdirs.fetchFiles(threadView.threadId, runId),
                          onDownloadWorkdirFile: (runId, file) =>
                              _workdirs.download(
                            threadView.threadId,
                            runId,
                            file,
                          ),
                          onPreviewWorkdirFile: (runId, file) =>
                              _workdirs.fetchBytes(
                            threadView.threadId,
                            runId,
                            file,
                          ),
                        ),
              },
            ),
            if (sendError != null)
              _SendErrorBanner(
                error: sendError,
                onDismiss: () => threadView.clearSendError(),
              ),
            if (attachEnabled)
              UploadEventBanner(
                tracker: _state.uploadTracker,
                roomId: widget.roomId,
                threadId: threadView.threadId,
              ),
          ],
        ),
      ],
    );
  }

  /// Renders the single ChatInput at the bottom of the room layout. Dispatches
  /// callbacks based on whether a [threadView] is active. Using one widget for
  /// both states keeps the [EditableText] element stable across the
  /// welcome → thread transition; see issue #212.
  Widget _buildChatInput(
    ThreadViewState? threadView,
    Room? room,
    ThreadViewStatus? status,
  ) {
    final attachEnabled = room?.enableAttachments ?? false;
    VoidCallback? attachCallback(Future<PickFilesResult?> Function() pick) {
      if (!attachEnabled) return null;
      return threadView != null
          ? () => _pickAndUploadToThread(threadView.threadId, pick)
          : () => _pickAndUploadToNewThread(pick);
    }

    return ChatInput(
      onSend: (text) {
        if (threadView != null) {
          threadView.sendMessage(
            text,
            _state.runtime,
            stateOverlay: _buildStateOverlay(),
          );
        } else {
          _state.sendToNewThread(text, stateOverlay: _buildStateOverlay());
        }
      },
      onCancel: threadView != null ? threadView.cancelRun : _state.cancelSpawn,
      sessionState: threadView?.sessionState ?? _state.sessionState,
      cancelEnabled: threadView?.isCancellable,
      controller: _chatController,
      focusNode: _chatFocusNode,
      enabled: threadView == null || status is MessagesLoaded,
      selectedDocuments: _selectedDocuments,
      onFilterTap: _showDocumentFilter ? _openDocumentPicker : null,
      onDocumentRemoved: _filterEnabled
          ? (doc) => _updateSelection(Set.of(_selectedDocuments)..remove(doc))
          : null,
      onAttachFile: attachCallback(pickFiles),
      onAttachFolder: attachCallback(pickFolder),
    );
  }

  static Widget _threadEmptyFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48,
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'Type a message to get started',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _SendErrorBanner extends StatelessWidget {
  const _SendErrorBanner({required this.error, required this.onDismiss});

  final SendError error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              error.error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Banner for in-flight SSE reconnect lifecycle states.
///
/// Renders [Reconnecting] and [Reconnected] only. Callers must filter
/// out [ReconnectFailed] (which surfaces through the send-error
/// banner) before passing a status to this widget.
class _ReconnectBanner extends StatefulWidget {
  const _ReconnectBanner({required this.status, required this.onDismiss});

  final ReconnectStatus status;
  final VoidCallback onDismiss;

  @override
  State<_ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends State<_ReconnectBanner> {
  Timer? _autoDismiss;

  @override
  void didUpdateWidget(covariant _ReconnectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.runtimeType != widget.status.runtimeType) {
      _autoDismiss?.cancel();
      _autoDismiss = null;
      _scheduleAutoDismissIfNeeded();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleAutoDismissIfNeeded();
  }

  void _scheduleAutoDismissIfNeeded() {
    if (widget.status is Reconnected) {
      _autoDismiss = Timer(
        const Duration(seconds: 4),
        () {
          if (!mounted) return;
          widget.onDismiss();
        },
      );
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, label) = switch (widget.status) {
      Reconnecting(:final attempt) => (
          const _SpinnerIcon(),
          'Reconnecting… (attempt $attempt)',
        ),
      Reconnected() => (
          Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
          'Reconnected.',
        ),
      // Filtered at call site, but exhaustive here so a future
      // ReconnectStatus subclass forces a build break instead of
      // silently rendering an empty banner.
      ReconnectFailed() => (const SizedBox.shrink(), ''),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      color: scheme.secondaryContainer,
      child: Row(
        children: [
          icon,
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _SpinnerIcon extends StatelessWidget {
  const _SpinnerIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 14,
      width: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
      ),
    );
  }
}
