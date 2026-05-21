import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  group('LobbyState', () {
    group('room fetching on init', () {
      test('fetches rooms from all connected servers', () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeApi = FakeSoliplexApi();
        const room = Room(id: 'room-1', name: 'Test Room');
        fakeApi.nextRooms = [room];

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        // Wait for async fetch to complete
        await Future<void>.delayed(Duration.zero);

        final rooms = state.roomsByServer.value;
        expect(rooms, hasLength(1));
        expect(rooms['local'], isA<RoomsLoaded>());
        expect((rooms['local'] as RoomsLoaded).rooms, [room]);

        state.dispose();
      });

      test('starts with RoomsLoading while fetch is in flight', () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeApi = FakeSoliplexApi();
        // Never resolves synchronously — we check the in-flight state
        fakeApi.nextRooms = [];

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        // Before awaiting, state should be loading
        final rooms = state.roomsByServer.value;
        expect(rooms['local'], isA<RoomsLoading>());

        await Future<void>.delayed(Duration.zero);
        state.dispose();
      });

      test('skips servers that are not connected', () async {
        final manager = _createManager();
        // requiresAuth: true with no login → not connected
        manager.addServer(
          serverId: 'auth-server',
          serverUrl: Uri.parse('https://api.example.com'),
          requiresAuth: true,
        );

        final fakeApi = FakeSoliplexApi();
        fakeApi.nextRooms = [];

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        await Future<void>.delayed(Duration.zero);

        expect(state.roomsByServer.value, isEmpty);

        state.dispose();
      });
    });

    group('error handling', () {
      test('sets RoomsFailed when fetch errors', () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeApi = FakeSoliplexApi();
        final error = Exception('network error');
        fakeApi.nextError = error;

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        await Future<void>.delayed(Duration.zero);

        final rooms = state.roomsByServer.value;
        expect(rooms['local'], isA<RoomsFailed>());
        expect((rooms['local'] as RoomsFailed).error, error);

        state.dispose();
      });

      test(
        'PermissionDeniedException on rooms fetch produces RoomsFailed '
        'and does NOT funnel to markSessionExpired',
        () async {
          // A 403 means the user is authenticated but lacks access;
          // re-auth wouldn't help, so the lobby renders an inline
          // permission message instead of flipping the session to
          // ExpiredSession. A future refactor that lumps
          // PermissionDeniedException under AuthException (or routes
          // it through the auth funnel) would silently break this
          // contract — this test pins it.
          final manager = _createManager();
          final entry = manager.addServer(
            serverId: 'auth-server',
            serverUrl: Uri.parse('https://api.example.com'),
          );
          entry.auth.login(
            provider: const OidcProvider(
              discoveryUrl: 'https://sso/.well-known/openid-configuration',
              clientId: 'c',
            ),
            tokens: AuthTokens(
              accessToken: 'a',
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

          final fakeApi = FakeSoliplexApi();
          final error = const PermissionDeniedException(
            message: 'Forbidden',
            statusCode: 403,
          );
          fakeApi.nextError = error;

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );

          await Future<void>.delayed(Duration.zero);

          // Session must stay ActiveSession; 403 is not an auth failure.
          expect(entry.auth.session.value, isA<ActiveSession>());
          // Section is preserved and surfaces the 403 inline.
          final rooms = state.roomsByServer.value;
          expect(rooms['auth-server'], isA<RoomsFailed>());
          expect((rooms['auth-server']! as RoomsFailed).error, same(error));

          state.dispose();
        },
      );

      test(
        'AuthException on rooms fetch funnels to markSessionExpired '
        'and section becomes RoomsExpired (kept visible for sign-in)',
        () async {
          // The lobby keeps an expired server's row visible with an
          // inline "sign in again" affordance so the user can recover
          // without leaving the lobby. The profile is dropped so a
          // re-auth as a different identity doesn't briefly show the
          // previous user's name.
          final manager = _createManager();
          final entry = manager.addServer(
            serverId: 'auth-server',
            serverUrl: Uri.parse('https://api.example.com'),
          );
          entry.auth.login(
            provider: const OidcProvider(
              discoveryUrl: 'https://sso/.well-known/openid-configuration',
              clientId: 'c',
            ),
            tokens: AuthTokens(
              accessToken: 'a',
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

          final fakeApi = FakeSoliplexApi();
          fakeApi.nextError = const AuthException(
            message: 'Unauthorized',
            statusCode: 401,
          );

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );

          await Future<void>.delayed(Duration.zero);

          // Session flips to ExpiredSession; tokens preserved for a
          // future silent refresh attempt.
          expect(entry.auth.session.value, isA<ExpiredSession>());
          // Section is kept visible with the RoomsExpired marker.
          expect(state.roomsByServer.value['auth-server'], isA<RoomsExpired>());
          // Profile entry is present but null: the key is preserved so
          // the sidebar still iterates it, but stale identity data is
          // cleared.
          expect(
            state.userProfiles.value.containsKey('auth-server'),
            isTrue,
          );
          expect(state.userProfiles.value['auth-server'], isNull);

          state.dispose();
        },
      );

      test(
        'ExpiredSession → ActiveSession refetches rooms and profile',
        () async {
          // The user clicks "Sign in" on the expired card, the new
          // ActiveSession arrives, and the lobby must transition the
          // section out of RoomsExpired back into RoomsLoaded.
          final manager = _createManager();
          final entry = manager.addServer(
            serverId: 'auth-server',
            serverUrl: Uri.parse('https://api.example.com'),
          );
          const provider = OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          );
          entry.auth.login(
            provider: provider,
            tokens: AuthTokens(
              accessToken: 'a',
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

          final fakeApi = FakeSoliplexApi();
          // First fetch on initial login fails with 401.
          fakeApi.nextError = const AuthException(
            message: 'Unauthorized',
            statusCode: 401,
          );

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );
          await Future<void>.delayed(Duration.zero);
          expect(state.roomsByServer.value['auth-server'], isA<RoomsExpired>());

          // Re-sign-in: clear the error, queue a successful rooms list,
          // and flip the session back to ActiveSession.
          fakeApi.nextError = null;
          fakeApi.nextRooms = const <Room>[];
          entry.auth.login(
            provider: provider,
            tokens: AuthTokens(
              accessToken: 'a2',
              refreshToken: 'r2',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          expect(state.roomsByServer.value['auth-server'], isA<RoomsLoaded>());

          state.dispose();
        },
      );

      test(
        'NoSession (logout) prunes the section',
        () async {
          // A true sign-out should not leave a stale "session expired"
          // row in the lobby. Pruning the section is the right disposition
          // because there are no tokens to recover from.
          final manager = _createManager();
          final entry = manager.addServer(
            serverId: 'auth-server',
            serverUrl: Uri.parse('https://api.example.com'),
          );
          entry.auth.login(
            provider: const OidcProvider(
              discoveryUrl: 'https://sso/.well-known/openid-configuration',
              clientId: 'c',
            ),
            tokens: AuthTokens(
              accessToken: 'a',
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

          final fakeApi = FakeSoliplexApi();
          fakeApi.nextRooms = const <Room>[];

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );
          await Future<void>.delayed(Duration.zero);
          expect(state.roomsByServer.value['auth-server'], isA<RoomsLoaded>());

          entry.auth.logout();
          await Future<void>.delayed(Duration.zero);

          expect(state.roomsByServer.value.containsKey('auth-server'), isFalse);
          expect(state.userProfiles.value.containsKey('auth-server'), isFalse);

          state.dispose();
        },
      );
    });

    group('server removal', () {
      test('removes rooms when server is removed', () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeApi = FakeSoliplexApi();
        fakeApi.nextRooms = [];

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        await Future<void>.delayed(Duration.zero);
        expect(state.roomsByServer.value, contains('local'));

        manager.removeServer('local');

        expect(state.roomsByServer.value, isNot(contains('local')));

        state.dispose();
      });
    });

    group('server addition after init', () {
      test('fetches rooms when a new server is added', () async {
        final manager = _createManager();

        final fakeApi = FakeSoliplexApi();
        const room = Room(id: 'room-2', name: 'New Room');
        fakeApi.nextRooms = [room];

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        // No servers yet
        expect(state.roomsByServer.value, isEmpty);

        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        await Future<void>.delayed(Duration.zero);

        final rooms = state.roomsByServer.value;
        expect(rooms, contains('local'));
        expect(rooms['local'], isA<RoomsLoaded>());

        state.dispose();
      });
    });

    group('auth state changes', () {
      test('fetches rooms and profile after login', () async {
        final manager = _createManager();
        final fakeApi = FakeSoliplexApi();
        fakeApi.nextRooms = [const Room(id: 'r1', name: 'Room 1')];

        // Add server that requires auth (not connected yet)
        final entry = manager.addServer(
          serverId: 'auth-server',
          serverUrl: Uri.parse('https://api.example.com'),
        );

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );
        await Future<void>.delayed(Duration.zero);

        // Not connected yet — no rooms fetched
        expect(state.roomsByServer.value, isEmpty);

        // Simulate login
        entry.auth.login(
          provider: const OidcProvider(
            discoveryUrl:
                'https://auth.example.com/.well-known/openid-configuration',
            clientId: 'test',
          ),
          tokens: AuthTokens(
            accessToken: 'access',
            refreshToken: 'refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Now connected — rooms should be fetched
        expect(state.roomsByServer.value['auth-server'], isA<RoomsLoaded>());
        final loaded = state.roomsByServer.value['auth-server']! as RoomsLoaded;
        expect(loaded.rooms, hasLength(1));

        state.dispose();
      });
    });

    group('refresh', () {
      test('re-fetches rooms for a specific server', () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeApi = FakeSoliplexApi();
        fakeApi.nextRooms = [];

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );

        await Future<void>.delayed(Duration.zero);

        const refreshedRoom = Room(id: 'room-refreshed', name: 'Refreshed');
        fakeApi.nextRooms = [refreshedRoom];

        state.refresh('local');
        await Future<void>.delayed(Duration.zero);

        final rooms = state.roomsByServer.value;
        expect(rooms['local'], isA<RoomsLoaded>());
        expect((rooms['local'] as RoomsLoaded).rooms, [refreshedRoom]);

        state.dispose();
      });

      test('throws StateError when server not found', () async {
        final manager = _createManager();
        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => FakeSoliplexApi(),
        );

        expect(() => state.refresh('nonexistent'), throwsStateError);

        state.dispose();
      });
    });

    group('user profile fetching', () {
      test('fetches user profile for connected servers', () async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeClient = entry.httpClient as FakeHttpClient;
        final profileJson = jsonEncode({
          'given_name': 'Ada',
          'family_name': 'Lovelace',
          'email': 'ada@example.com',
          'preferred_username': 'ada',
        });
        fakeClient.onRequest = (method, uri) async => HttpResponse(
              statusCode: 200,
              bodyBytes: Uint8List.fromList(utf8.encode(profileJson)),
            );

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => FakeSoliplexApi()..nextRooms = [],
        );

        await Future<void>.delayed(Duration.zero);

        final profiles = state.userProfiles.value;
        expect(profiles, contains('local'));
        final profile = profiles['local'];
        expect(profile, isNotNull);
        expect(profile!.givenName, 'Ada');
        expect(profile.familyName, 'Lovelace');
        expect(profile.email, 'ada@example.com');
        expect(profile.preferredUsername, 'ada');

        state.dispose();
      });

      test('sets null profile when /user_info returns 404', () async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeClient = entry.httpClient as FakeHttpClient;
        fakeClient.onRequest = (method, uri) async => HttpResponse(
              statusCode: 404,
              bodyBytes: Uint8List(0),
            );

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => FakeSoliplexApi()..nextRooms = [],
        );

        await Future<void>.delayed(Duration.zero);

        final profiles = state.userProfiles.value;
        expect(profiles, contains('local'));
        expect(profiles['local'], isNull);

        state.dispose();
      });

      test('removes profile when server is removed', () async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeClient = entry.httpClient as FakeHttpClient;
        fakeClient.onRequest = (method, uri) async => HttpResponse(
              statusCode: 200,
              bodyBytes: Uint8List.fromList(
                utf8.encode(jsonEncode({
                  'given_name': 'Ada',
                  'family_name': 'Lovelace',
                  'email': 'ada@example.com',
                  'preferred_username': 'ada',
                })),
              ),
            );

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => FakeSoliplexApi()..nextRooms = [],
        );

        await Future<void>.delayed(Duration.zero);
        expect(state.userProfiles.value, contains('local'));

        manager.removeServer('local');

        expect(state.userProfiles.value, isNot(contains('local')));

        state.dispose();
      });
    });

    group('dispose', () {
      test('cancels in-flight fetches on dispose', () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        // Use a completer to control when the fetch resolves
        final completer = Completer<List<Room>>();
        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => _CompleterApi(completer),
        );

        // Dispose before the fetch resolves
        state.dispose();

        // Complete after dispose — should not update state
        completer.complete([]);
        await Future<void>.delayed(Duration.zero);

        // No exception means cancellation was handled gracefully
      });
    });
  });
}

/// A [SoliplexApi] backed by a [Completer] for controlling fetch timing.
class _CompleterApi extends FakeSoliplexApi {
  _CompleterApi(this._completer);

  final Completer<List<Room>> _completer;

  @override
  Future<List<Room>> getRooms({CancelToken? cancelToken}) => _completer.future;
}
