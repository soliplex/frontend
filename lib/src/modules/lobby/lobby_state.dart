import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthException,
        NotFoundException,
        PermissionDeniedException,
        SoliplexApi;

import '../../core/activity_read.dart';
import '../../core/util/debouncer.dart';
import '../auth/auth_tokens.dart';
import '../auth/selected_server_storage.dart';
import '../auth/server_entry.dart';
import '../auth/server_manager.dart';
import '../room/run_registry.dart';
import 'lobby_read_markers.dart';
import 'lobby_sort_mode.dart';
import 'lobby_view_mode.dart';

typedef ApiResolver = SoliplexApi Function(ServerEntry entry);

class UserProfile {
  const UserProfile({
    required this.givenName,
    required this.familyName,
    required this.email,
    required this.preferredUsername,
  });

  final String givenName;
  final String familyName;
  final String email;
  final String preferredUsername;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        givenName: json['given_name'] as String? ?? '',
        familyName: json['family_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        preferredUsername: json['preferred_username'] as String? ?? '',
      );
}

sealed class ServerRooms {
  const ServerRooms();
}

final class RoomsLoading extends ServerRooms {
  const RoomsLoading();
}

final class RoomsLoaded extends ServerRooms {
  RoomsLoaded(List<Room> rooms) : rooms = List.unmodifiable(rooms);
  final List<Room> rooms;
}

final class RoomsFailed extends ServerRooms {
  const RoomsFailed(this.error);
  final Object error;
}

/// The server's session has expired. Tokens are preserved (for a silent
/// refresh attempt later), but the user must re-authenticate to see
/// rooms. The lobby renders an inline "sign in again" affordance.
final class RoomsExpired extends ServerRooms {
  const RoomsExpired();
}

/// The user has signed out of the server (no tokens remain). The server
/// stays listed so the single-server lobby can offer an inline "sign in"
/// affordance instead of a blank pane.
final class RoomsSignedOut extends ServerRooms {
  const RoomsSignedOut();
}

/// Manages per-server room lists, fetching from all connected servers.
class LobbyState {
  LobbyState({
    required ServerManager serverManager,
    ApiResolver? apiResolver,
    RunRegistry? registry,
    RoomReadMarkers? readMarkers,
  })  : _serverManager = serverManager,
        _apiResolver = apiResolver ?? _defaultResolver,
        _registry = registry,
        _readMarkers = readMarkers ?? RoomReadMarkers() {
    _unsubscribe = _serverManager.servers.subscribe(_onServersChanged);
    unawaited(_loadViewMode());
    unawaited(_loadSortMode());
    unawaited(_readMarkers.ensureLoaded());
    unawaited(_loadSelectedServer());
    _watchRunCompletions();
  }

  final ServerManager _serverManager;
  final ApiResolver _apiResolver;
  final RunRegistry? _registry;

  /// Shared in-memory read-marker model. A room is unread when [roomActivity]
  /// reports activity newer than this marker. Stamped by the room screen on
  /// leave; the lobby watches it so a just-read room clears immediately.
  final RoomReadMarkers _readMarkers;

  late final void Function() _unsubscribe;

  /// Snapshot of the registry's active run keys, to detect active→terminal
  /// transitions. Seeded before subscribing so the immediate first emission is
  /// a no-op diff.
  Set<ThreadKey> _previousActiveKeys = const {};

  /// Disposer for the run-completion subscription that refreshes room activity.
  void Function()? _runCompletionUnsub;

  /// Coalesces a burst of run completions into a single activity refresh.
  final Debouncer _activityRefresh =
      Debouncer(const Duration(milliseconds: 300));

  final Signal<Map<String, ServerRooms>> _roomsByServer =
      Signal<Map<String, ServerRooms>>({});
  ReadonlySignal<Map<String, ServerRooms>> get roomsByServer => _roomsByServer;

  final Signal<Map<String, UserProfile?>> _userProfiles =
      Signal<Map<String, UserProfile?>>({});
  ReadonlySignal<Map<String, UserProfile?>> get userProfiles => _userProfiles;

  /// Preferred room layout. Starts at [LobbyViewMode.list]; replaced by the
  /// persisted preference (or its [LobbyViewMode.list] fallback) once
  /// [_loadViewMode] resolves.
  final Signal<LobbyViewMode> _viewMode = Signal(LobbyViewMode.list);
  ReadonlySignal<LobbyViewMode> get viewMode => _viewMode;

  Future<void> _loadViewMode() async {
    try {
      _viewMode.value = await LobbyViewModeStorage.load();
    } catch (error, st) {
      // Keep the default; a missing preference is not worth blocking on, but
      // a systematic storage failure should still leave a trace.
      dev.log(
        'Failed to load lobby view mode',
        error: error,
        stackTrace: st,
        level: 900,
      );
    }
  }

  /// Updates the room layout and persists the choice for next launch.
  void setViewMode(LobbyViewMode mode) {
    if (mode == _viewMode.value) return;
    _viewMode.value = mode;
    unawaited(
      LobbyViewModeStorage.save(mode).catchError((Object error, StackTrace st) {
        // The in-memory choice already took effect; only persistence failed.
        // The next launch falls back to the default, which the user can
        // re-select — but log so a silent storage failure is debuggable.
        dev.log(
          'Failed to persist lobby view mode',
          error: error,
          stackTrace: st,
          level: 900,
        );
      }),
    );
  }

  /// How rooms are ordered in the main pane. Starts at [LobbySortMode.none];
  /// replaced by the persisted preference once [_loadSortMode] resolves.
  final Signal<LobbySortMode> _sortMode = Signal(LobbySortMode.none);
  ReadonlySignal<LobbySortMode> get sortMode => _sortMode;

  Future<void> _loadSortMode() async {
    try {
      _sortMode.value = await LobbySortModeStorage.load();
      // Kick off the activity fetch once the persisted mode is known. (The
      // fetch is eager regardless of mode; this just runs it at launch.)
      _reconcileActivity();
    } catch (error, st) {
      dev.log(
        'Failed to load lobby sort mode',
        error: error,
        stackTrace: st,
        level: 900,
      );
    }
  }

  /// Updates the room ordering and persists the choice for next launch.
  /// Activity timestamps are already fetched eagerly on server selection (see
  /// [_reconcileActivity]); this only changes the ordering. The
  /// [_reconcileActivity] call is a safety net for the rare case where the
  /// fetch has not run yet.
  void setSortMode(LobbySortMode mode) {
    if (mode == _sortMode.value) return;
    _sortMode.value = mode;
    _reconcileActivity();
    unawaited(
      LobbySortModeStorage.save(mode).catchError((Object error, StackTrace st) {
        dev.log(
          'Failed to persist lobby sort mode',
          error: error,
          stackTrace: st,
          level: 900,
        );
      }),
    );
  }

  /// Last-activity timestamp per room, keyed by (serverId, roomId).
  /// A present-but-null value means "fetched, room has no activity"; an absent
  /// key means "not fetched yet". Used only to order [LobbySortMode]
  /// .recentActivity; rooms without a timestamp sort last.
  final Signal<Map<RoomActivityKey, DateTime?>> _roomActivity =
      Signal<Map<RoomActivityKey, DateTime?>>({});
  ReadonlySignal<Map<RoomActivityKey, DateTime?>> get roomActivity =>
      _roomActivity;

  /// Per-room "last seen" timestamps, keyed by (serverId, roomId). A room is
  /// *unread* when [roomActivity] reports a last-activity time newer than its
  /// marker (or newer than the epoch, when never opened). Persisted per-device;
  /// there is no server-side read state and no unread count.
  ReadonlySignal<Map<RoomActivityKey, DateTime>> get readMarkers =>
      _readMarkers.markers;

  /// True while activity for the selected server is being fetched.
  final Signal<bool> _activityLoading = Signal(false);
  ReadonlySignal<bool> get activityLoading => _activityLoading;

  /// Cancels an in-flight activity fetch when the selection changes or the
  /// state is disposed.
  CancelToken? _activityToken;

  /// Server whose activity batch is currently in flight, or `null` when none
  /// is. Lets [_reconcileActivity] coalesce repeat calls for the same server
  /// instead of cancelling and restarting the request.
  String? _activityFetchServerId;

  /// Resets activity-fetch state to a clean idle baseline: cancels any in-flight
  /// request and clears the loading flag.
  void _cancelActivityFetch() {
    _activityToken?.cancel('activity reconcile');
    _activityToken = null;
    _activityFetchServerId = null;
    _activityLoading.value = false;
  }

  /// Loads activity timestamps for the selected server's rooms in a single
  /// batch request. Fetched eagerly (the room cards display the relative time
  /// regardless of sort order) and reused for [LobbySortMode.recentActivity]
  /// ordering. No-op before a server is selected or before that server's rooms
  /// have loaded. Results are merged into [_roomActivity] keyed by
  /// (serverId, roomId), so switching servers reuses prior fetches.
  void _reconcileActivity() {
    final serverId = _selectedServerId.value;

    // A batch for this server is already in flight: it owns the token and the
    // spinner, so coalesce — return without touching either.
    if (serverId != null && _activityFetchServerId == serverId) return;

    // Otherwise we're (re)deciding. Cancel any stale fetch (a different server,
    // or none) and reset to a clean baseline.
    _cancelActivityFetch();

    if (serverId == null) return;
    final entry = _serverManager.servers.value[serverId];
    if (entry == null) return;
    final rooms = _roomsByServer.value[serverId];
    if (rooms is! RoomsLoaded) return;

    final missing = rooms.rooms
        .where((r) => !_roomActivity.value
            .containsKey((serverId: serverId, roomId: r.id)))
        .toList();
    if (missing.isEmpty) return;

    final token = CancelToken();
    _activityToken = token;
    _activityFetchServerId = serverId;
    _activityLoading.value = true;

    _apiResolver(entry).getRoomsStats(cancelToken: token).then((stats) {
      if (token.isCancelled) return;
      _activityToken = null;
      _activityFetchServerId = null;
      _activityLoading.value = false;
      // Null-fill the requested rooms, then overlay the batch — in one update,
      // after the network yield (seeding nulls before the await would flash
      // every room to "no activity" and re-sort when results land). A room the
      // batch omits (authz skew) keeps a null entry rather than staying absent;
      // otherwise it would re-trigger the batch on every reconcile.
      final next = {..._roomActivity.value};
      for (final room in missing) {
        next[(serverId: serverId, roomId: room.id)] =
            stats[room.id]?.lastActivity;
      }
      _roomActivity.value = next;
    }).catchError((Object error, StackTrace st) {
      if (token.isCancelled) return;
      _activityToken = null;
      _activityFetchServerId = null;
      _activityLoading.value = false;
      if (error is AuthException) {
        // Funnel to the per-server auth funnel; _onAuthChanged paints
        // RoomsExpired and re-auth refetches via _fetchRooms. Nothing to cache
        // here.
        entry.auth.markSessionExpired();
        return;
      }
      if (error is PermissionDeniedException || error is NotFoundException) {
        // Stable per-server states — denied authz (403), or a pre-stats backend
        // (404). They won't change between reconciles, so degrade to "no
        // activity" by null-filling the requested rooms; this also keeps them
        // out of the "missing" set so a later reconcile doesn't re-fire a
        // request that can't succeed. Recovery comes via refresh()/re-auth,
        // which invalidates this server's slice in _fetchRooms.
        final next = {..._roomActivity.value};
        for (final room in missing) {
          next[(serverId: serverId, roomId: room.id)] = null;
        }
        _roomActivity.value = next;
        return;
      }
      // A genuine, possibly-transient failure (network, 5xx, decode, programmer
      // error). Log at error level and leave the rooms absent so the next
      // reconcile retries, rather than freezing the lobby on "no activity" with
      // no recovery cue.
      dev.log(
        'Failed to fetch room activity for $serverId',
        error: error,
        stackTrace: st,
        level: 1000,
      );
    });
  }

  /// Drops the cached activity slice for [serverId] (cancelling an in-flight
  /// fetch for it) so the next [_reconcileActivity] re-fetches instead of being
  /// short-circuited by the "already fetched" guard.
  void _invalidateActivity(String serverId) {
    if (_activityFetchServerId == serverId) _cancelActivityFetch();
    if (_roomActivity.value.keys.any((k) => k.serverId == serverId)) {
      _roomActivity.value = {..._roomActivity.value}
        ..removeWhere((k, _) => k.serverId == serverId);
    }
  }

  /// Forces a re-fetch of the selected server's room-activity batch, bypassing
  /// the [_reconcileActivity] "already fetched" cache so a room whose activity
  /// advanced (e.g. a background run just finished) can light its unread dot.
  /// No-op before a server is selected.
  void refreshActivity() {
    final serverId = _selectedServerId.value;
    if (serverId == null) return;
    _invalidateActivity(serverId);
    _reconcileActivity();
  }

  /// Refreshes the selected server's activity whenever a run on it finishes, so
  /// a background reply that lands while the user sits in the lobby lights the
  /// room's unread dot. The lobby otherwise fetches activity only on load and
  /// selection, so a completion here would go unnoticed until re-entry.
  /// Debounced so a burst of completions makes one request; reads the current
  /// selected server on each emission so it survives server switches. No-op
  /// without a registry (tests omit it).
  void _watchRunCompletions() {
    final registry = _registry;
    if (registry == null) return;
    _previousActiveKeys = registry.activeKeys.value;
    _runCompletionUnsub = registry.activeKeys.subscribe((keys) {
      final serverId = _selectedServerId.value;
      final completed = serverId != null &&
          _previousActiveKeys
              .difference(keys)
              .any((k) => k.serverId == serverId);
      _previousActiveKeys = keys;
      if (completed) _activityRefresh.run(refreshActivity);
    });
  }

  /// Free-text room-name filter. Ephemeral — intentionally not persisted,
  /// so each lobby visit starts unfiltered.
  final Signal<String> _searchQuery = Signal('');
  ReadonlySignal<String> get searchQuery => _searchQuery;

  void setSearchQuery(String query) => _searchQuery.value = query;

  /// The server whose rooms are shown in the main pane. `null` when no
  /// server is available — before the persisted selection resolves on
  /// launch, or after the last server is removed. The selection is
  /// persisted across launches.
  final Signal<String?> _selectedServerId = Signal<String?>(null);
  ReadonlySignal<String?> get selectedServerId => _selectedServerId;

  /// Set once [_loadSelectedServer] has resolved. Until then the persisted
  /// load owns the initial selection, so [_reconcileSelection] must not
  /// race ahead and auto-pick the first server (which would shadow a
  /// still-loading persisted choice).
  bool _selectionInitialized = false;

  /// Restores the persisted selection if it still maps to a known server,
  /// else falls back to the first available server (or `null` when there
  /// are none).
  Future<void> _loadSelectedServer() async {
    String? persisted;
    try {
      persisted = await SelectedServerStorage.load();
    } catch (error, st) {
      dev.log(
        'Failed to load selected server',
        error: error,
        stackTrace: st,
        level: 900,
      );
    }
    final servers = _serverManager.servers.value;
    final restored = (persisted != null && servers.containsKey(persisted))
        ? persisted
        : (servers.isNotEmpty ? servers.keys.first : null);
    _selectionInitialized = true;
    if (restored != _selectedServerId.value) {
      _selectedServerId.value = restored;
      _reconcileActivity();
    }
  }

  /// Selects [serverId] as the viewed server and persists the choice.
  void selectServer(String serverId) {
    if (serverId == _selectedServerId.value) return;
    _selectedServerId.value = serverId;
    _persistSelection(serverId);
    _reconcileActivity();
  }

  /// Keeps the selection valid as the server set changes: an explicit,
  /// still-present selection is left alone; otherwise it falls back to the
  /// first server (or `null`). No-op until the persisted load has resolved.
  void _reconcileSelection(Map<String, ServerEntry> servers) {
    if (!_selectionInitialized) return;
    final current = _selectedServerId.value;
    if (current != null && servers.containsKey(current)) return;
    final next = servers.isEmpty ? null : servers.keys.first;
    if (next != current) {
      _selectedServerId.value = next;
      _persistSelection(next);
      _reconcileActivity();
    }
  }

  void _persistSelection(String? serverId) {
    unawaited(SelectedServerStorage.save(serverId));
  }

  /// Cancel tokens keyed by serverId, one per in-flight fetch.
  final Map<String, CancelToken> _cancelTokens = {};

  /// Per-server auth session subscriptions.
  final Map<String, void Function()> _authSubscriptions = {};

  /// Last-seen session state per server. Used to gate refetch on
  /// transitions INTO [ActiveSession] while suppressing
  /// [ActiveSession] → [ActiveSession] token rotation.
  final Map<String, SessionState> _lastSessionState = {};

  static SoliplexApi _defaultResolver(ServerEntry entry) =>
      entry.connection.api;

  void _onServersChanged(Map<String, ServerEntry> servers) {
    final knownIds = Set<String>.from(_authSubscriptions.keys);
    final nextIds = Set<String>.from(servers.keys);

    // Remove servers that are gone
    final removed = knownIds.difference(nextIds);
    if (removed.isNotEmpty) {
      final updatedRooms = Map<String, ServerRooms>.from(_roomsByServer.value);
      final updatedProfiles =
          Map<String, UserProfile?>.from(_userProfiles.value);
      for (final id in removed) {
        updatedRooms.remove(id);
        updatedProfiles.remove(id);
        _cancelTokens.remove(id)?.cancel('server removed');
        _authSubscriptions.remove(id)?.call();
        _lastSessionState.remove(id);
        // Drop a stuck in-flight activity fetch for a removed server; otherwise
        // _activityFetchServerId would block a future fetch if the id returns.
        if (_activityFetchServerId == id) _cancelActivityFetch();
      }
      _roomsByServer.value = updatedRooms;
      _userProfiles.value = updatedProfiles;
      if (_roomActivity.value.keys.any((k) => removed.contains(k.serverId))) {
        _roomActivity.value = {..._roomActivity.value}
          ..removeWhere((k, _) => removed.contains(k.serverId));
      }
    }

    // Subscribe to auth changes for new servers and fetch if already connected
    final added = nextIds.difference(knownIds);
    for (final id in added) {
      final entry = servers[id]!;
      // Seed before subscribing: the signals library fires the
      // callback synchronously with the current value. The seed
      // lets [_onAuthChanged] see `previous == current` on that
      // immediate fire so the transition gate does not misread it
      // as a fresh entry into ActiveSession. (The non-connected
      // switch branch still runs and paints `RoomsExpired` for a
      // pre-expired server, which is the desired behavior.)
      _lastSessionState[id] = entry.auth.session.value;
      _authSubscriptions[id] = entry.auth.session.subscribe((_) {
        _onAuthChanged(id, entry);
      });
      if (entry.isConnected) {
        _fetchRooms(id, entry);
        _fetchUserProfile(id, entry);
      }
    }

    _reconcileSelection(servers);
  }

  void _onAuthChanged(String serverId, ServerEntry entry) {
    final previous = _lastSessionState[serverId];
    final current = entry.auth.session.value;
    _lastSessionState[serverId] = current;

    if (entry.isConnected) {
      // Refetch only on transitions INTO ActiveSession (silent
      // recovery from a prior ExpiredSession/NoSession). Active →
      // Active is token rotation: the user, server, rooms list, and
      // profile are unchanged, and refetching on every rotation
      // would race the proactive refresh threshold and produce a
      // self-amplifying refresh→fetch→refresh loop whenever the
      // IdP issues access tokens shorter than that threshold.
      if (current is ActiveSession && previous is! ActiveSession) {
        _fetchRooms(serverId, entry);
        _fetchUserProfile(serverId, entry);
      }
      return;
    }
    _cancelTokens.remove(serverId)?.cancel('disconnected');
    switch (current) {
      case ExpiredSession():
        // Keep the row visible with an inline "sign in again" affordance.
        // The previously-known profile is dropped so a re-auth as a
        // different identity does not briefly render the prior user's
        // name.
        _roomsByServer.value = {
          ..._roomsByServer.value,
          serverId: const RoomsExpired(),
        };
        _userProfiles.value = {..._userProfiles.value, serverId: null};
      case NoSession():
        // Signed out: keep the row with an inline "sign in" affordance so
        // the single-server lobby shows a recoverable state rather than a
        // blank pane. The profile is dropped so a re-auth as a different
        // identity does not briefly render the prior user's name.
        _roomsByServer.value = {
          ..._roomsByServer.value,
          serverId: const RoomsSignedOut(),
        };
        _userProfiles.value = {..._userProfiles.value, serverId: null};
      case ActiveSession():
        assert(false, 'ActiveSession reached the !isConnected branch');
    }
  }

  void _fetchRooms(String serverId, ServerEntry entry) {
    // Cancel any in-flight request for this server
    _cancelTokens.remove(serverId)?.cancel('re-fetch');

    final token = CancelToken();
    _cancelTokens[serverId] = token;

    // Mark as loading
    _roomsByServer.value = {
      ..._roomsByServer.value,
      serverId: const RoomsLoading(),
    };

    _apiResolver(entry).getRooms(cancelToken: token).then((rooms) {
      if (token.isCancelled) return;
      _cancelTokens.remove(serverId);
      _roomsByServer.value = {
        ..._roomsByServer.value,
        serverId: RoomsLoaded(rooms),
      };
      // A fresh room list invalidates cached activity for this server (rooms
      // may have been added); drop those entries so recency refetches.
      _invalidateActivity(serverId);
      if (serverId == _selectedServerId.value) _reconcileActivity();
    }).catchError((Object error, StackTrace st) {
      if (token.isCancelled) return;
      _cancelTokens.remove(serverId);
      if (error is AuthException) {
        // Funnel to the per-server auth funnel. _onAuthChanged observes
        // the ExpiredSession transition and writes RoomsExpired so the
        // lobby keeps the row with an inline "sign in again" affordance.
        entry.auth.markSessionExpired();
        return;
      }
      if (error is! PermissionDeniedException) {
        // PermissionDeniedException is rendered inline by the lobby
        // section; everything else (network, 5xx, decode, programmer
        // errors) would otherwise be stringified into the UI with no
        // backing log.
        dev.log(
          'Failed to fetch rooms for $serverId',
          error: error,
          stackTrace: st,
          level: 1000,
        );
      }
      _roomsByServer.value = {
        ..._roomsByServer.value,
        serverId: RoomsFailed(error),
      };
    });
  }

  void _fetchUserProfile(String serverId, ServerEntry entry) {
    final url = entry.serverUrl.resolve('/api/user_info');
    Future.sync(() => entry.httpClient.request('GET', url)).then((response) {
      if (!_authSubscriptions.containsKey(serverId)) return;
      // `entry.httpClient` is the raw decorator chain (no HttpTransport),
      // so a 401 comes back as a response, not as a thrown AuthException
      // — funnel it explicitly. RefreshingHttpClient has already tried
      // refresh-and-retry by the time we see this status.
      if (response.statusCode == 401) {
        entry.auth.markSessionExpired();
        return;
      }
      final UserProfile? profile;
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        profile = UserProfile.fromJson(json);
      } else {
        dev.log(
          'Profile fetch returned ${response.statusCode} for $serverId',
          level: 900,
        );
        profile = null;
      }
      _userProfiles.value = {..._userProfiles.value, serverId: profile};
    }).catchError((Object error, StackTrace st) {
      if (!_authSubscriptions.containsKey(serverId)) return;
      if (error is AuthException) {
        entry.auth.markSessionExpired();
        return;
      }
      // Profile is optional sidebar metadata; silent null is the correct
      // UI disposition for PermissionDeniedException and other failures.
      // Log everything else so 5xx / decode / programmer errors stay
      // debuggable — there is no surface in the UI for them otherwise.
      if (error is! PermissionDeniedException) {
        dev.log(
          'Failed to fetch user profile for $serverId',
          error: error,
          stackTrace: st,
          level: 900,
        );
      }
      _userProfiles.value = {..._userProfiles.value, serverId: null};
    });
  }

  /// Manually re-fetches rooms and profile for the given server.
  void refresh(String serverId) {
    final servers = _serverManager.servers.value;
    final entry = servers[serverId];
    if (entry == null) {
      throw StateError('No server entry for "$serverId"');
    }
    _fetchRooms(serverId, entry);
    _fetchUserProfile(serverId, entry);
  }

  void dispose() {
    _unsubscribe();
    _runCompletionUnsub?.call();
    _activityRefresh.cancel();
    _cancelActivityFetch();
    for (final unsub in _authSubscriptions.values) {
      unsub();
    }
    _authSubscriptions.clear();
    for (final token in _cancelTokens.values) {
      token.cancel('disposed');
    }
    _cancelTokens.clear();
  }
}
