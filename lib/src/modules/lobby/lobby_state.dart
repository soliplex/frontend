import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show AuthException, PermissionDeniedException, SoliplexApi;

import '../auth/auth_tokens.dart';
import '../auth/server_entry.dart';
import '../auth/server_manager.dart';
import 'lobby_view_mode.dart';
import 'selected_server_storage.dart';

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
  })  : _serverManager = serverManager,
        _apiResolver = apiResolver ?? _defaultResolver {
    _unsubscribe = _serverManager.servers.subscribe(_onServersChanged);
    unawaited(_loadViewMode());
    unawaited(_loadSelectedServer());
  }

  final ServerManager _serverManager;
  final ApiResolver _apiResolver;
  late final void Function() _unsubscribe;

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
    }
  }

  /// Selects [serverId] as the viewed server and persists the choice.
  void selectServer(String serverId) {
    if (serverId == _selectedServerId.value) return;
    _selectedServerId.value = serverId;
    _persistSelection(serverId);
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
    }
  }

  void _persistSelection(String? serverId) {
    unawaited(
      SelectedServerStorage.save(serverId)
          .catchError((Object e, StackTrace st) {
        dev.log(
          'Failed to persist selected server',
          error: e,
          stackTrace: st,
          level: 900,
        );
      }),
    );
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
      }
      _roomsByServer.value = updatedRooms;
      _userProfiles.value = updatedProfiles;
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
