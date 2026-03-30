import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart' show SoliplexApi;

import '../auth/server_entry.dart';
import '../auth/server_manager.dart';

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

sealed class ServerRooms {}

class RoomsLoading extends ServerRooms {}

class RoomsLoaded extends ServerRooms {
  RoomsLoaded(this.rooms);
  final List<Room> rooms;
}

class RoomsFailed extends ServerRooms {
  RoomsFailed(this.error);
  final Object error;
}

/// Manages per-server room lists, fetching from all connected servers.
class LobbyState {
  LobbyState({
    required ServerManager serverManager,
    ApiResolver? apiResolver,
  })  : _serverManager = serverManager,
        _apiResolver = apiResolver ?? _defaultResolver {
    _unsubscribe = _serverManager.servers.subscribe(_onServersChanged);
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

  /// Cancel tokens keyed by serverId, one per in-flight fetch.
  final Map<String, CancelToken> _cancelTokens = {};

  /// Per-server auth session subscriptions.
  final Map<String, void Function()> _authSubscriptions = {};

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
      }
      _roomsByServer.value = updatedRooms;
      _userProfiles.value = updatedProfiles;
    }

    // Subscribe to auth changes for new servers and fetch if already connected
    final added = nextIds.difference(knownIds);
    for (final id in added) {
      final entry = servers[id]!;
      _authSubscriptions[id] = entry.auth.session.subscribe((_) {
        _onAuthChanged(id, entry);
      });
      if (entry.isConnected) {
        _fetchRooms(id, entry);
        _fetchUserProfile(id, entry);
      }
    }
  }

  void _onAuthChanged(String serverId, ServerEntry entry) {
    if (entry.isConnected) {
      _fetchRooms(serverId, entry);
      _fetchUserProfile(serverId, entry);
    } else {
      final updatedRooms = Map<String, ServerRooms>.from(_roomsByServer.value)
        ..remove(serverId);
      final updatedProfiles =
          Map<String, UserProfile?>.from(_userProfiles.value)..remove(serverId);
      _cancelTokens.remove(serverId)?.cancel('disconnected');
      _roomsByServer.value = updatedRooms;
      _userProfiles.value = updatedProfiles;
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
      serverId: RoomsLoading(),
    };

    _apiResolver(entry).getRooms(cancelToken: token).then((rooms) {
      if (token.isCancelled) return;
      _cancelTokens.remove(serverId);
      _roomsByServer.value = {
        ..._roomsByServer.value,
        serverId: RoomsLoaded(rooms),
      };
    }).catchError((Object error) {
      if (token.isCancelled) return;
      _cancelTokens.remove(serverId);
      _roomsByServer.value = {
        ..._roomsByServer.value,
        serverId: RoomsFailed(error),
      };
    });
  }

  void _fetchUserProfile(String serverId, ServerEntry entry) {
    final url = entry.serverUrl.resolve('/user_info');
    Future.sync(() => entry.httpClient.request('GET', url)).then((response) {
      if (!_authSubscriptions.containsKey(serverId)) return;
      final UserProfile? profile;
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        profile = UserProfile.fromJson(json);
      } else {
        profile = null;
      }
      _userProfiles.value = {..._userProfiles.value, serverId: profile};
    }).catchError((Object _) {
      if (!_authSubscriptions.containsKey(serverId)) return;
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
