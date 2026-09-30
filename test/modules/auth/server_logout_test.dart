import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_logout.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';

ServerManager _manager({InMemoryServerStorage? storage}) => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: storage ?? InMemoryServerStorage(),
    );

ServerEntry _signedInEntry(ServerManager m, {String? idToken = 'id-1'}) {
  final entry = m.addServer(
    serverId: 'srv',
    serverUrl: Uri.parse('https://api.example.com'),
  );
  entry.auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
      clientId: 'soliplex',
    ),
    tokens: AuthTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      idToken: idToken,
    ),
  );
  return entry;
}

/// A probe client returning a discovery document with an end_session_endpoint.
FakeHttpClient _discoveryClient() => FakeHttpClient()
  ..onRequest = (method, uri) async => HttpResponse(
        statusCode: 200,
        bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode({
          'token_endpoint': 'https://sso.example.com/token',
          'end_session_endpoint': 'https://sso.example.com/logout',
        }))),
      );

/// Calls [logoutServer] with [probe] defaulting to a discovery document on
/// web and to a client that fails any request on native.
Future<void> _logout(
  ServerEntry entry,
  ServerManager manager,
  AuthFlow flow, {
  required bool web,
  bool remove = false,
  SoliplexHttpClient? probe,
}) =>
    logoutServer(
      entry: entry,
      serverManager: manager,
      remove: remove,
      authFlow: flow,
      probeClient: probe ?? (web ? _discoveryClient() : FakeHttpClient()),
      web: web,
    );

/// A navigation failure whose text carries a token, as a platform error might.
class _NavFailure implements Exception {
  @override
  String toString() => 'navigation to ?id_token_hint=$_token failed';
}

const _token = 'eyJhbGciOiJSUzI1NiJ9.secret-id-token';

MemorySink _captureLogs() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return sink;
}

/// The single warning `soliplex.server_logout` recorded with [message].
LogRecord _warning(MemorySink sink, String message) => sink.records
    .where((r) =>
        r.loggerName == 'soliplex.server_logout' &&
        r.level == LogLevel.warning &&
        r.message.contains(message))
    .single;

void _expectEndSessionFailureLogged(MemorySink sink) {
  final record = _warning(sink, 'ending the IdP session failed');
  expect(record.attributes, {'serverId': 'srv', 'failure': '_NavFailure'});
  expect(
    [record.message, record.attributes, record.error].join(' '),
    isNot(contains(_token)),
  );
}

void main() {
  group('logoutServer native (web: false)', () {
    test('ends the IdP session before any storage write, then clears local',
        () async {
      final storage = InMemoryServerStorage();
      final manager = _manager(storage: storage);
      final entry = _signedInEntry(manager);
      await pumpEventQueue();
      // loadAll copies the store synchronously, so this is what storage held
      // at the moment endSession ran.
      late Future<Map<String, PersistedServer>> storedDuringEndSession;
      final flow = RecordingAuthFlow(
        onEndSession: () => storedDuringEndSession = storage.loadAll(),
      );

      await _logout(entry, manager, flow, web: false, remove: true);

      expect((await storedDuringEndSession)['srv'], isA<AuthenticatedServer>());
      expect(entry.auth.session.value, isA<NoSession>());
      expect(manager.servers.value, isNot(contains('srv')));
      expect(await storage.loadAll(), isNot(contains('srv')));
    });

    test('clears the local session only after endSession returns', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      bool authedDuringEndSession = false;
      final flow = RecordingAuthFlow(
        onEndSession: () => authedDuringEndSession = entry.auth.isAuthenticated,
      );

      await _logout(entry, manager, flow, web: false);

      expect(flow.endSessionCalled, isTrue);
      // Native ordering: local stays Active across the IdP round-trip, then is
      // cleared once endSession returns cleanly.
      expect(authedDuringEndSession, isTrue);
      expect(entry.auth.isAuthenticated, isFalse);
    });

    test('passes no end_session_endpoint and never pre-fetches discovery',
        () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      // A bare FakeHttpClient throws UnimplementedError on request, so a stray
      // discovery pre-fetch would surface as a thrown error here.
      final flow = RecordingAuthFlow();

      await _logout(entry, manager, flow, web: false);

      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastEndSessionEndpoint, isNull);
    });

    test('a failed endSession preserves the local session and the server',
        () async {
      final storage = InMemoryServerStorage();
      final manager = _manager(storage: storage);
      final entry = _signedInEntry(manager);
      final flow = RecordingAuthFlow(endSessionError: Exception('idp down'));

      await expectLater(
        _logout(entry, manager, flow, web: false, remove: true),
        throwsA(isA<Exception>()),
      );

      // The throw happens before the local clear, so the session and the
      // server survive.
      expect(entry.auth.isAuthenticated, isTrue);
      expect(manager.servers.value, contains('srv'));
      expect((await storage.loadAll())['srv'], isA<AuthenticatedServer>());
    });

    test('a signed-out session signs out locally without an IdP round-trip',
        () async {
      final manager = _manager();
      // requiresAuth + NoSession => not an ActiveSession.
      final entry = manager.addServer(
        serverId: 'srv',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      final flow = RecordingAuthFlow();

      await _logout(entry, manager, flow, web: false);

      expect(flow.endSessionCalled, isFalse);
      expect(entry.auth.isAuthenticated, isFalse);
    });

    test('an expired session still ends the IdP session with its id token',
        () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      entry.auth.markSessionExpired();
      final flow = RecordingAuthFlow();

      await _logout(entry, manager, flow, web: false);

      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastIdToken, 'id-1');
      expect(entry.auth.session.value, isA<NoSession>());
    });

    test('passes no hint when the session has no id token', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager, idToken: null);
      final flow = RecordingAuthFlow();
      final sink = _captureLogs();

      await _logout(entry, manager, flow, web: false);

      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastIdToken, isNull);
      expect(_warning(sink, 'Session has no id_token').attributes,
          {'serverId': 'srv'});
    });
  });

  group('logoutServer web (web: true)', () {
    test('removes the server from storage before navigating to endSession',
        () async {
      final storage = InMemoryServerStorage();
      final manager = _manager(storage: storage);
      final entry = _signedInEntry(manager);
      await pumpEventQueue();
      final release = Completer<void>();
      storage.writesHeldUntil = release.future;
      final flow = RecordingAuthFlow();

      final logout = _logout(entry, manager, flow, web: true, remove: true);
      await pumpEventQueue();

      expect(flow.endSessionCalled, isFalse);
      expect(await storage.loadAll(), contains('srv'));

      release.complete();
      await logout;

      expect(flow.endSessionCalled, isTrue);
      expect(manager.servers.value, isNot(contains('srv')));
      expect(await storage.loadAll(), isNot(contains('srv')));
    });

    test('saves the signed-out session before navigating to endSession',
        () async {
      final storage = InMemoryServerStorage();
      final manager = _manager(storage: storage);
      final entry = _signedInEntry(manager);
      await pumpEventQueue();
      final release = Completer<void>();
      storage.writesHeldUntil = release.future;
      final flow = RecordingAuthFlow();

      final logout = _logout(entry, manager, flow, web: true);
      await pumpEventQueue();

      expect(flow.endSessionCalled, isFalse);
      expect((await storage.loadAll())['srv'], isA<AuthenticatedServer>());

      release.complete();
      await logout;

      expect(flow.endSessionCalled, isTrue);
      expect(manager.servers.value, contains('srv'));
      expect((await storage.loadAll())['srv'], isA<KnownServer>());
    });

    test(
        'an expired session still ends the IdP session with its id token, at '
        'the discovered end_session_endpoint', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      entry.auth.markSessionExpired();
      final flow = RecordingAuthFlow();

      await _logout(entry, manager, flow, web: true);

      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastIdToken, 'id-1');
      expect(flow.lastEndSessionEndpoint, 'https://sso.example.com/logout');
      expect(entry.auth.session.value, isA<NoSession>());
    });

    test('an endSession failure after the local clear completes normally',
        () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      final flow = RecordingAuthFlow(endSessionError: _NavFailure());
      final sink = _captureLogs();

      await _logout(entry, manager, flow, web: true, remove: true);

      expect(flow.endSessionCalled, isTrue);
      expect(entry.auth.session.value, isA<NoSession>());
      expect(manager.servers.value, isNot(contains('srv')));
      _expectEndSessionFailureLogged(sink);
    });

    test('an empty id token sends no id_token_hint', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager, idToken: '');
      final flow = RecordingAuthFlow();

      await _logout(entry, manager, flow, web: true);

      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastIdToken, isNull);
    });

    test('clears local even when the provider has no end_session_endpoint',
        () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      // Discovery succeeds but publishes no end_session_endpoint.
      final probeClient = FakeHttpClient()
        ..onRequest = (method, uri) async => HttpResponse(
              statusCode: 200,
              bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode({
                'token_endpoint': 'https://sso.example.com/token',
              }))),
            );
      final flow = RecordingAuthFlow();
      final sink = _captureLogs();

      await _logout(entry, manager, flow, web: true, probe: probeClient);

      expect(
        _warning(sink, 'no end_session_endpoint').attributes,
        {'serverId': 'srv'},
      );
      // RP-initiated logout can't end the IdP session without an endpoint, but
      // web still clears local (the documented weaker invariant) and still
      // drives endSession with a null endpoint.
      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastEndSessionEndpoint, isNull);
      expect(entry.auth.isAuthenticated, isFalse);
    });

    test('a discovery-fetch failure preserves the session and skips endSession',
        () async {
      final storage = InMemoryServerStorage();
      final manager = _manager(storage: storage);
      final entry = _signedInEntry(manager);
      final probeClient = FakeHttpClient()
        ..onRequest = (method, uri) async => throw Exception('discovery down');
      final flow = RecordingAuthFlow();

      await expectLater(
        _logout(entry, manager, flow,
            web: true, remove: true, probe: probeClient),
        throwsA(isA<Exception>()),
      );

      // Degrading to endSessionEndpoint: null would clear local while the IdP
      // session stays alive, so a discovery failure must keep the session and
      // the server.
      expect(flow.endSessionCalled, isFalse);
      expect(entry.auth.isAuthenticated, isTrue);
      expect(manager.servers.value, contains('srv'));
      expect((await storage.loadAll())['srv'], isA<AuthenticatedServer>());
    });
  });

  group('describeLogoutFailure', () {
    const generic = 'Sign-out failed. Please try again.';

    test('a cancelled AuthException says sign-out was cancelled', () {
      expect(
        describeLogoutFailure(
          const AuthException(_token, kind: AuthFailureKind.cancelled),
        ),
        'Sign-out was cancelled.',
      );
    });

    test('any other AuthException is a generic failure', () {
      expect(
        describeLogoutFailure(
          const AuthException(_token, kind: AuthFailureKind.unknown),
        ),
        generic,
      );
      expect(
        describeLogoutFailure(
          const AuthException(_token, kind: AuthFailureKind.network),
        ),
        generic,
      );
    });

    test('a NetworkException says the identity provider was unreachable', () {
      expect(
        describeLogoutFailure(const NetworkException(message: _token)),
        "Couldn't reach the identity provider. Check your connection and "
        'try again.',
      );
    });

    test("a FormatException says the provider's settings were unreadable", () {
      expect(
        describeLogoutFailure(const FormatException(_token)),
        "The identity provider's sign-out settings couldn't be read. Please "
        'try again.',
      );
    });

    test('anything else is a generic failure', () {
      expect(describeLogoutFailure(Exception(_token)), generic);
    });
  });
}
