import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/selected_server_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/core/activity_read.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

      test(
          'does not fetch for a not-connected server, but marks it '
          'RoomsSignedOut', () async {
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

        // No fetch happens, but the row carries a sign-in affordance rather
        // than being absent, so a selected not-connected server is
        // recoverable instead of blank.
        expect(state.roomsByServer.value['auth-server'], isA<RoomsSignedOut>());
        expect(fakeApi.getRoomsCallCount, 0);

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
          // Silent-recovery path: any in-flight HTTP request through
          // RefreshingHttpClient can succeed in refreshing tokens for a
          // server whose row currently shows RoomsExpired. When that
          // happens the lobby observes ExpiredSession → ActiveSession
          // and must transition the row out of RoomsExpired back into
          // RoomsLoaded. Pins the contract: refetch on transitions
          // INTO ActiveSession, never on Active → Active rotation.
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

          // Silent recovery: clear the error, queue a successful rooms
          // list, and flip the session back to ActiveSession.
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
        'cascading AuthException on silent recovery settles in ExpiredSession',
        () async {
          // Pin the no-oscillation contract: if a silent-recovery
          // refetch ALSO returns 401 (backend revoked the grant before
          // the frontend learned), the lobby must settle in
          // RoomsExpired rather than flip into a self-amplifying
          // Active↔Expired loop. The no-op-on-already-expired guard in
          // `markSessionExpired` plus the transition gate (only refetch
          // on entries INTO ActiveSession) jointly prevent the loop.
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
          fakeApi.nextError = const AuthException(
            message: 'Unauthorized',
            statusCode: 401,
          );

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );
          await Future<void>.delayed(Duration.zero);
          expect(entry.auth.session.value, isA<ExpiredSession>());
          expect(state.roomsByServer.value['auth-server'], isA<RoomsExpired>());

          // Silent recovery: tokens refresh successfully → ActiveSession,
          // but the refetch immediately returns 401 because the grant
          // was revoked server-side.
          // (Keep nextError set so the second getRooms also fails.)
          entry.auth.login(
            provider: provider,
            tokens: AuthTokens(
              accessToken: 'a2',
              refreshToken: 'r2',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          expect(
            entry.auth.session.value,
            isA<ExpiredSession>(),
            reason: 'Cascaded 401 must funnel back to ExpiredSession, not '
                'leave the session Active.',
          );
          expect(
            state.roomsByServer.value['auth-server'],
            isA<RoomsExpired>(),
            reason: 'The row stays in RoomsExpired; no flicker to '
                'RoomsLoaded/RoomsFailed.',
          );

          state.dispose();
        },
      );

      test(
        'NoSession (logout) marks the section RoomsSignedOut and drops '
        'the profile',
        () async {
          // The single-server lobby shows the selected server's section
          // alone, so a logged-out server keeps a RoomsSignedOut row with a
          // sign-in affordance instead of a blank pane. The profile is
          // dropped so a re-auth as a different identity does not flash the
          // prior user's name.
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

          expect(
              state.roomsByServer.value['auth-server'], isA<RoomsSignedOut>());
          expect(state.userProfiles.value['auth-server'], isNull);

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
        // Exactly one fetch: the transition gate (only refetch on
        // entries INTO ActiveSession) suppresses the subscribe
        // immediate-fire because this requiresAuth=false server's
        // session stays `NoSession`.
        expect(fakeApi.getRoomsCallCount, 1);

        state.dispose();
      });

      test(
          'seed-before-subscribe suppresses duplicate fetch when an '
          'already-ActiveSession server is added', () async {
        // The signals library fires subscribe callbacks synchronously
        // with the current value. If `_lastSessionState` weren't seeded
        // before subscribing, the immediate-fire would see
        // `previous = null, current = ActiveSession` and the transition
        // gate would misread it as a fresh entry — triggering a second
        // fetch on top of the explicit one in `_onServersChanged`.
        final manager = _createManager();
        final fakeApi = FakeSoliplexApi();
        fakeApi.nextRooms = [const Room(id: 'r1', name: 'Room 1')];

        final entry = manager.addServer(
          serverId: 'auth-server',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        // Log in BEFORE constructing LobbyState so the subscribe
        // immediate-fire sees ActiveSession.
        entry.auth.login(
          provider: const OidcProvider(
            discoveryUrl:
                'https://auth.example.com/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );
        await Future<void>.delayed(Duration.zero);

        expect(state.roomsByServer.value['auth-server'], isA<RoomsLoaded>());
        expect(fakeApi.getRoomsCallCount, 1);

        state.dispose();
      });
    });

    group('auth state changes', () {
      test('fetches rooms and profile after login', () async {
        // NoSession → ActiveSession must trigger a fetch. Pins the
        // transition-INTO-ActiveSession contract independently of
        // which screen happens to be mounted when the transition
        // occurs.
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

        // Not connected yet — signed-out affordance shown, no rooms fetched.
        expect(state.roomsByServer.value['auth-server'], isA<RoomsSignedOut>());

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

    group('token rotation', () {
      test(
        'writing a fresh ActiveSession for an already-connected server '
        'does NOT trigger a new rooms fetch',
        () async {
          // `TokenRefreshService` writes a new `ActiveSession` to
          // `auth.session` after every successful refresh. The user,
          // server, rooms list, and profile are unchanged across a
          // rotation, so the lobby must treat it as a no-op. Without
          // this guard, an IdP that issues access tokens shorter than
          // the refresh threshold creates a self-amplifying
          // refresh→fetch→refresh loop while the lobby is mounted.
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
              accessToken: 'access-1',
              refreshToken: 'refresh-1',
              expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            ),
          );

          final fakeApi = FakeSoliplexApi();
          fakeApi.nextRooms = const <Room>[];

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );
          await Future<void>.delayed(Duration.zero);

          // Initial fetch already ran via _onServersChanged.
          expect(fakeApi.getRoomsCallCount, 1);

          // Simulate a token refresh: same provider, new tokens.
          entry.auth.login(
            provider: provider,
            tokens: AuthTokens(
              accessToken: 'access-2',
              refreshToken: 'refresh-2',
              expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          entry.auth.login(
            provider: provider,
            tokens: AuthTokens(
              accessToken: 'access-3',
              refreshToken: 'refresh-3',
              expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          expect(fakeApi.getRoomsCallCount, 1);

          state.dispose();
        },
      );

      test(
        'ActiveSession → ExpiredSession while RoomsLoaded flips to '
        'RoomsExpired and drops the profile',
        () async {
          // The common bad-day path: a real fetch returns 401, the
          // funnel calls `markSessionExpired`, and the lobby must
          // replace the live rooms list with `RoomsExpired` (the
          // inline "sign in again" affordance) and drop the previously
          // rendered user name.
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
          final fakeApi = FakeSoliplexApi();
          fakeApi.nextRooms = [const Room(id: 'r1', name: 'Room 1')];

          final state = LobbyState(
            serverManager: manager,
            apiResolver: (_) => fakeApi,
          );
          await Future<void>.delayed(Duration.zero);

          expect(state.roomsByServer.value['auth-server'], isA<RoomsLoaded>());
          expect(state.userProfiles.value['auth-server'], isNotNull);

          entry.auth.markSessionExpired();
          await Future<void>.delayed(Duration.zero);

          expect(state.roomsByServer.value['auth-server'], isA<RoomsExpired>());
          expect(state.userProfiles.value['auth-server'], isNull);

          state.dispose();
        },
      );
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

      test('401 from /user_info funnels through markSessionExpired', () async {
        // entry.httpClient is the raw decorator chain (no HttpTransport),
        // so a 401 surfaces as a response — not as a thrown
        // AuthException. The success arm must funnel explicitly.
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'auth-server',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        entry.auth.login(
          provider: const OidcProvider(
            discoveryUrl:
                'https://auth.example.com/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        final fakeClient = entry.httpClient as FakeHttpClient;
        fakeClient.onRequest = (method, uri) async => HttpResponse(
              statusCode: 401,
              bodyBytes: Uint8List(0),
            );

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => FakeSoliplexApi()..nextRooms = [],
        );

        await Future<void>.delayed(Duration.zero);

        expect(entry.auth.session.value, isA<ExpiredSession>());

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

    group('searchQuery', () {
      test('defaults to empty and is updated by setSearchQuery', () {
        final state = LobbyState(serverManager: _createManager());
        expect(state.searchQuery.value, '');

        state.setSearchQuery('design');
        expect(state.searchQuery.value, 'design');

        state.dispose();
      });
    });

    group('selectedServerId', () {
      ServerManager managerWith(List<String> ids) {
        final manager = _createManager();
        for (final id in ids) {
          manager.addServer(
            serverId: id,
            serverUrl: Uri.parse('http://$id:8000'),
            requiresAuth: false,
          );
        }
        return manager;
      }

      LobbyState stateFor(ServerManager manager) => LobbyState(
            serverManager: manager,
            apiResolver: (_) => FakeSoliplexApi()..nextRooms = [],
          );

      test('defaults to the first server once loaded', () async {
        final state = stateFor(managerWith(['a', 'b']));
        await Future<void>.delayed(Duration.zero);
        expect(state.selectedServerId.value, 'a');
        state.dispose();
      });

      test('restores the persisted selection when it still exists', () async {
        SharedPreferences.setMockInitialValues({
          'soliplex_lobby_selected_server': 'b',
        });
        final state = stateFor(managerWith(['a', 'b']));
        await Future<void>.delayed(Duration.zero);
        expect(state.selectedServerId.value, 'b');
        state.dispose();
      });

      test('falls back to first when the persisted selection is gone',
          () async {
        SharedPreferences.setMockInitialValues({
          'soliplex_lobby_selected_server': 'gone',
        });
        final state = stateFor(managerWith(['a', 'b']));
        await Future<void>.delayed(Duration.zero);
        expect(state.selectedServerId.value, 'a');
        state.dispose();
      });

      test('selectServer updates the signal and persists the choice', () async {
        final state = stateFor(managerWith(['a', 'b']));
        await Future<void>.delayed(Duration.zero);

        state.selectServer('b');
        expect(state.selectedServerId.value, 'b');
        await Future<void>.delayed(Duration.zero);
        expect(await SelectedServerStorage.load(), 'b');

        state.dispose();
      });

      test(
          'falls back to the first remaining server when the selected '
          'one is removed', () async {
        final manager = managerWith(['a', 'b']);
        final state = stateFor(manager);
        await Future<void>.delayed(Duration.zero);
        state.selectServer('a');

        manager.removeServer('a');
        await Future<void>.delayed(Duration.zero);

        expect(state.selectedServerId.value, 'b');
        state.dispose();
      });

      test('does not persist a fallback over the still-loading selection',
          () async {
        // _onServersChanged fires synchronously when LobbyState subscribes
        // (the servers are already present), before the async persisted
        // load resolves. Without the _selectionInitialized guard,
        // _reconcileSelection picks the first server and persists it,
        // clobbering the stored 'b'. The settled signal value can survive
        // that race, so the storage read is the assertion with teeth.
        SharedPreferences.setMockInitialValues({
          'soliplex_lobby_selected_server': 'b',
        });
        final state = stateFor(managerWith(['a', 'b']));
        await Future<void>.delayed(Duration.zero);

        expect(state.selectedServerId.value, 'b');
        expect(await SelectedServerStorage.load(), 'b');
        state.dispose();
      });

      test('keeps an explicit selection when another server is added',
          () async {
        final manager = managerWith(['a', 'b']);
        final state = stateFor(manager);
        await Future<void>.delayed(Duration.zero);
        state.selectServer('b');

        manager.addServer(
          serverId: 'c',
          serverUrl: Uri.parse('http://c:8000'),
          requiresAuth: false,
        );
        await Future<void>.delayed(Duration.zero);

        // Adding a server reconciles the selection, but a still-present
        // explicit choice must be left alone, not yanked back to first.
        expect(state.selectedServerId.value, 'b');
        state.dispose();
      });

      test('clears the selection and storage when the only server is removed',
          () async {
        SharedPreferences.setMockInitialValues({
          'soliplex_lobby_selected_server': 'only',
        });
        final manager = managerWith(['only']);
        final state = stateFor(manager);
        await Future<void>.delayed(Duration.zero);
        expect(state.selectedServerId.value, 'only');

        manager.removeServer('only');
        await Future<void>.delayed(Duration.zero);

        // No servers left: the selection clears and the stale pointer is
        // removed from storage so the next launch starts clean.
        expect(state.selectedServerId.value, isNull);
        expect(await SelectedServerStorage.load(), isNull);
        state.dispose();
      });
    });

    group('refreshActivity', () {
      test('re-fetches the selected server\'s activity even when cached',
          () async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'local',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        final fakeApi = FakeSoliplexApi()
          ..nextRooms = [const Room(id: 'room-1', name: 'Test Room')]
          ..roomsStats = {
            'room-1': RoomStats(lastActivity: DateTime.utc(2026, 6, 1)),
          };

        final state = LobbyState(
          serverManager: manager,
          apiResolver: (_) => fakeApi,
        );
        await pumpEventQueue();

        // Activity is fetched once on load and cached.
        expect(fakeApi.getRoomsStatsCallCount, 1);
        const key = (serverId: 'local', roomId: 'room-1');
        expect(state.roomActivity.value[key], DateTime.utc(2026, 6, 1));

        // A background run advances the room's activity server-side.
        fakeApi.roomsStats = {
          'room-1': RoomStats(lastActivity: DateTime.utc(2026, 6, 2)),
        };

        // A plain reconcile would no-op because the activity is already
        // cached; refreshActivity forces the re-fetch so the lobby learns of
        // the new activity and can light the unread dot.
        state.refreshActivity();
        await pumpEventQueue();

        expect(fakeApi.getRoomsStatsCallCount, 2);
        expect(state.roomActivity.value[key], DateTime.utc(2026, 6, 2));

        state.dispose();
      });
    });

    group('mark as read', () {
      const provider = OidcProvider(
        discoveryUrl: 'https://sso/.well-known/openid-configuration',
        clientId: 'c',
      );

      void loginAs(ServerEntry entry, String sub) => entry.auth.login(
            provider: provider,
            tokens: AuthTokens(
              accessToken: testAccessToken(sub: sub),
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      test('markRoomRead stamps under the signed-in user and projects it back',
          () {
        withClock(Clock.fixed(DateTime.utc(2026, 6, 1)), () {
          final manager = _createManager();
          loginAs(
            manager.addServer(
                serverId: 'srvA', serverUrl: Uri.parse('http://a.test')),
            'alice',
          );
          final state = LobbyState(serverManager: manager);

          state.markRoomRead('srvA', 'roomA');

          expect(
            state.roomReadMarkers.value[(serverId: 'srvA', roomId: 'roomA')],
            DateTime.utc(2026, 6, 1),
          );
          state.dispose();
        });
      });

      test('markServerRead stamps under the signed-in user', () {
        withClock(Clock.fixed(DateTime.utc(2026, 6, 1)), () {
          final manager = _createManager();
          loginAs(
            manager.addServer(
                serverId: 'srvA', serverUrl: Uri.parse('http://a.test')),
            'alice',
          );
          final state = LobbyState(serverManager: manager);

          state.markServerRead('srvA');

          expect(
            state.serverReadMarkers.value['srvA'],
            DateTime.utc(2026, 6, 1),
          );
          state.dispose();
        });
      });

      test(
          'projects each server to its own user, hiding another user\'s marker',
          () async {
        final t = DateTime.utc(2026, 6, 1);
        final manager = _createManager();
        loginAs(
          manager.addServer(
              serverId: 'srvA', serverUrl: Uri.parse('http://a.test')),
          'alice',
        );
        loginAs(
          manager.addServer(
              serverId: 'srvB', serverUrl: Uri.parse('http://b.test')),
          'bob',
        );

        final room = RoomReadMarkers();
        room.markRead(
            serverId: 'srvA',
            userId: testIdentityFor('alice'),
            roomId: 'r1',
            at: t);
        // A stale marker from a user who is NOT srvA's current user: must be
        // hidden by the per-server projection.
        room.markRead(
            serverId: 'srvA',
            userId: testIdentityFor('bob'),
            roomId: 'rStale',
            at: t);
        room.markRead(
            serverId: 'srvB',
            userId: testIdentityFor('bob'),
            roomId: 'r2',
            at: t);
        final server = ServerReadMarkers();
        server.markRead(
            serverId: 'srvA', userId: testIdentityFor('alice'), at: t);
        server.markRead(
            serverId: 'srvB', userId: testIdentityFor('bob'), at: t);

        final state = LobbyState(
          serverManager: manager,
          roomReadMarkers: room,
          serverReadMarkers: server,
        );
        await pumpEventQueue();

        expect(state.roomReadMarkers.value, {
          (serverId: 'srvA', roomId: 'r1'): t,
          (serverId: 'srvB', roomId: 'r2'): t,
        });
        expect(state.serverReadMarkers.value, {'srvA': t, 'srvB': t});
        state.dispose();
      });

      test('a live sign-in loads and projects that user\'s persisted markers',
          () async {
        final t = DateTime.utc(2026, 6, 1);
        // Bob has read state persisted from a previous session.
        await LobbyReadMarkerStorage.saveServer(
            serverId: 'srvA',
            userId: testIdentityFor('bob'),
            markers: {'r1': t});

        final manager = _createManager();
        final entry = manager.addServer(
            serverId: 'srvA', serverUrl: Uri.parse('http://a.test'));
        final state = LobbyState(serverManager: manager);
        await pumpEventQueue();
        // Signed out: no user resolves, so nothing projects.
        expect(state.roomReadMarkers.value, isEmpty);

        loginAs(entry, 'bob');
        await pumpEventQueue();

        // The auth change loads Bob's blob and re-runs the projection (his
        // currentUserId is a tracked dependency), surfacing his marker.
        expect(
            state.roomReadMarkers.value[(serverId: 'srvA', roomId: 'r1')], t);
        state.dispose();
      });
    });
  });

  group('isActivityUnread', () {
    final seen = DateTime.utc(2026, 6, 1, 12);

    test('no known activity is never unread', () {
      expect(isActivityUnread(null, null), isFalse);
      expect(isActivityUnread(null, seen), isFalse);
    });

    test('activity with no read marker is unread', () {
      expect(isActivityUnread(seen, null), isTrue);
    });

    test('activity newer than the marker is unread', () {
      expect(
        isActivityUnread(seen.add(const Duration(seconds: 1)), seen),
        isTrue,
      );
    });

    test('activity older than the marker is read', () {
      expect(
        isActivityUnread(seen.subtract(const Duration(seconds: 1)), seen),
        isFalse,
      );
    });

    test('activity exactly at the marker is read (strict isAfter boundary)',
        () {
      // A read marker is stamped at "now", which is >= any activity it has
      // seen, so an exact tie must read as seen, not unread.
      expect(isActivityUnread(seen, seen), isFalse);
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
