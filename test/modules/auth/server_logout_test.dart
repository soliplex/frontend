import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_logout.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

ServerManager _manager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

ServerEntry _signedInEntry(ServerManager m) {
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

/// A non-[Exception] throwable (an Error), to exercise the generic branch of
/// [friendlyLogoutError].
class _LogoutBoom extends Error {}

/// A concrete [SoliplexException] (the base is abstract).
class _ClientFailure extends SoliplexException {
  const _ClientFailure(String message) : super(message: message);
}

void main() {
  group('logoutServer native (web: false)', () {
    test('clears the local session only after endSession returns', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      bool authedDuringEndSession = false;
      final flow = RecordingAuthFlow(
        onEndSession: () => authedDuringEndSession = entry.auth.isAuthenticated,
      );

      await logoutServer(
        entry: entry,
        authFlow: flow,
        probeClient: FakeHttpClient(),
        web: false,
      );

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

      await logoutServer(
        entry: entry,
        authFlow: flow,
        probeClient: FakeHttpClient(),
        web: false,
      );

      expect(flow.endSessionCalled, isTrue);
      expect(flow.lastEndSessionEndpoint, isNull);
    });

    test('a failed endSession preserves the local session', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      final flow = RecordingAuthFlow(endSessionError: Exception('idp down'));

      await expectLater(
        logoutServer(
          entry: entry,
          authFlow: flow,
          probeClient: FakeHttpClient(),
          web: false,
        ),
        throwsA(isA<Exception>()),
      );

      // The throw happens before the local clear, so the session survives.
      expect(entry.auth.isAuthenticated, isTrue);
    });

    test('a non-active session signs out locally without an IdP round-trip',
        () async {
      final manager = _manager();
      // requiresAuth + NoSession => not an ActiveSession.
      final entry = manager.addServer(
        serverId: 'srv',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      final flow = RecordingAuthFlow();

      await logoutServer(
        entry: entry,
        authFlow: flow,
        probeClient: FakeHttpClient(),
        web: false,
      );

      expect(flow.endSessionCalled, isFalse);
      expect(entry.auth.isAuthenticated, isFalse);
    });
  });

  group('logoutServer web (web: true)', () {
    test('clears the local session before navigating to endSession', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      bool authedDuringEndSession = true;
      final flow = RecordingAuthFlow(
        onEndSession: () => authedDuringEndSession = entry.auth.isAuthenticated,
      );

      await logoutServer(
        entry: entry,
        authFlow: flow,
        probeClient: _discoveryClient(),
        web: true,
      );

      expect(flow.endSessionCalled, isTrue);
      // Web ordering (inverse of native): local is cleared before the
      // full-page navigation, so it must not survive the unload race.
      expect(authedDuringEndSession, isFalse);
      expect(entry.auth.isAuthenticated, isFalse);
    });

    test('passes the discovered end_session_endpoint to endSession', () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      final flow = RecordingAuthFlow();

      await logoutServer(
        entry: entry,
        authFlow: flow,
        probeClient: _discoveryClient(),
        web: true,
      );

      expect(flow.lastEndSessionEndpoint, 'https://sso.example.com/logout');
    });

    test('a discovery-fetch failure preserves the session and skips endSession',
        () async {
      final manager = _manager();
      final entry = _signedInEntry(manager);
      final probeClient = FakeHttpClient()
        ..onRequest = (method, uri) async => throw Exception('discovery down');
      final flow = RecordingAuthFlow();

      await expectLater(
        logoutServer(
          entry: entry,
          authFlow: flow,
          probeClient: probeClient,
          web: true,
        ),
        throwsA(isA<Exception>()),
      );

      // Degrading to endSessionEndpoint: null would clear local while the IdP
      // session stays alive, so a discovery failure must keep the session.
      expect(flow.endSessionCalled, isFalse);
      expect(entry.auth.isAuthenticated, isTrue);
    });
  });

  group('friendlyLogoutError', () {
    test('PlatformException uses its message, falling back to the code', () {
      expect(
        friendlyLogoutError(
          PlatformException(code: 'no_browser', message: 'No browser found'),
        ),
        'No browser found',
      );
      expect(
        friendlyLogoutError(PlatformException(code: 'cancelled')),
        'cancelled',
      );
    });

    test('SoliplexException uses its message', () {
      expect(friendlyLogoutError(const _ClientFailure('token revoked')),
          'token revoked');
    });

    test('a plain Exception is stripped of its "Exception: " prefix', () {
      expect(friendlyLogoutError(Exception('network unreachable')),
          'network unreachable');
    });

    test('a non-Exception Error renders a generic message with no type name',
        () {
      final message = friendlyLogoutError(_LogoutBoom());
      expect(message, 'Sign-out failed. Please try again.');
      // No minified/raw runtime type name leaks (e.g. "(_LogoutBoom)").
      expect(message, isNot(matches(RegExp(r'\(\w{3,}\)'))));
    });

    test('an over-long message is truncated to 200 chars with an ellipsis', () {
      final message = friendlyLogoutError(Exception('a' * 250));
      expect(message.length, 200);
      expect(message.endsWith('…'), isTrue);
    });
  });
}
