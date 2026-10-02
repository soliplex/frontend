import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_failure_description.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/connection_probe.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/selected_server_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

const _provider = AuthProviderConfig(
  id: 'idp-1',
  name: 'Test IdP',
  serverUrl: 'https://auth.example.com',
  clientId: 'test-client',
  scope: 'openid email profile',
);

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

ConnectFlow _createFlow({
  required FakeAuthFlow authFlow,
  InactivityLogoutFlagStorage? inactivityLogoutFlags,
  ServerManager? serverManager,
  DiscoverProviders? discover,
  void Function(Uri serverUrl)? onServerConnected,
  PreAuthStateStorage? preAuthStateStorage,
  ReturnTarget? returnTarget,
}) =>
    ConnectFlow(
      serverManager: serverManager ?? _createManager(),
      probeClient: FakeHttpClient(),
      discover: discover ?? (_, __) async => [_provider],
      authFlow: authFlow,
      inactivityLogoutFlags:
          inactivityLogoutFlags ?? InMemoryInactivityLogoutFlagStorage(),
      preAuthStateStorage: preAuthStateStorage ?? InMemoryPreAuthStateStorage(),
      onServerConnected: onServerConnected,
      returnTarget: returnTarget,
    );

AuthResult _successResult() => AuthResult(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

/// A fork's flag store that throws [failure] instead of degrading the way
/// `LocalInactivityLogoutFlagStorage` does.
/// [gate], when set, holds the failure until it completes.
class _ThrowingFlagStorage extends InMemoryInactivityLogoutFlagStorage {
  Completer<void>? gate;
  Object failure = Exception('flag store unavailable');

  @override
  Future<bool> isMarked(String serverId) async {
    await gate?.future;
    throw failure;
  }
}

Matcher get _connectError =>
    isA<UrlInput>().having((s) => s.message, 'message', isA<ConnectError>());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectFlow — return target', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    const server = 'https://server.example.com';

    test('saves the return page for its own server', () async {
      final storage = InMemoryPreAuthStateStorage();
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..throwRedirectInitiated = true,
        preAuthStateStorage: storage,
        returnTarget: (serverId: server, path: '/room/a/b'),
      );

      await flow.connect(server);
      await pumpEventQueue();

      expect(storage.saved!.frontendReturnTo, '/room/a/b');
    });

    test('saves no return page for a different server', () async {
      final storage = InMemoryPreAuthStateStorage();
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..throwRedirectInitiated = true,
        preAuthStateStorage: storage,
        returnTarget: (
          serverId: 'https://other.example.com',
          path: '/room/a/b'
        ),
      );

      await flow.connect(server);
      await pumpEventQueue();

      expect(storage.saved, isNotNull);
      expect(storage.saved!.frontendReturnTo, isNull);
    });

    test('keeps the return page across a reset and a retry', () async {
      final storage = InMemoryPreAuthStateStorage();
      final authFlow = FakeAuthFlow()
        ..nextError = const AuthException(
          'cancelled',
          kind: AuthFailureKind.cancelled,
        );
      final flow = _createFlow(
        authFlow: authFlow,
        preAuthStateStorage: storage,
        returnTarget: (serverId: server, path: '/room/a/b'),
      );

      await flow.connect(server);
      await pumpEventQueue();
      flow.reset();
      authFlow.throwRedirectInitiated = true;
      await flow.connect(server);
      await pumpEventQueue();

      expect(storage.saved!.frontendReturnTo, '/room/a/b');
    });

    for (final path in ['https://evil.example/steal', '/lobby?server=%FF']) {
      test('drops the unsafe return page $path, without logging it', () async {
        final sink = MemorySink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));
        final storage = InMemoryPreAuthStateStorage();
        final flow = _createFlow(
          authFlow: FakeAuthFlow()..throwRedirectInitiated = true,
          preAuthStateStorage: storage,
          returnTarget: (serverId: server, path: path),
        );

        await flow.connect(server);
        await pumpEventQueue();

        expect(storage.saved!.frontendReturnTo, isNull);
        final record = sink.records
            .where((r) =>
                r.loggerName == 'soliplex.connect_flow' &&
                r.level == LogLevel.warning)
            .single;
        expect(record.message,
            'Dropped a return page that is not a safe in-app path');
        expect(record.toString(), isNot(contains('evil.example')));
        expect(record.toString(), isNot(contains('%FF')));
      });
    }
  });

  group('ConnectFlow._authenticate — forceLoginPrompt plumbing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('passes forceLoginPrompt=true when the inactivity flag is marked',
        () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(authFlow.lastForceLoginPrompt, isTrue);
    });

    test('passes forceLoginPrompt=false when no flag is set', () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(authFlow.lastForceLoginPrompt, isFalse);
    });

    test('isMarked does not clear the flag on its own', () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      // The web flow throws AuthRedirectInitiated before any clear can
      // happen, so the flag must still be set when the browser returns.
      expect(await flags.isMarked('https://server.example.com'), isTrue);
    });

    test('successful authentication clears the flag', () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..nextResult = _successResult();
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(authFlow.lastForceLoginPrompt, isTrue);
      expect(await flags.isMarked('https://server.example.com'), isFalse);
    });

    test('cancelled IdP challenge keeps the flag set for the next retry',
        () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()
        ..nextError = const AuthException(
          'User cancelled',
          kind: AuthFailureKind.cancelled,
        );
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      // The cancel keeps the flag set so a retry also forces prompt=login
      // — otherwise an attacker could cancel once and then sign in via
      // silent SSO.
      expect(await flags.isMarked('https://server.example.com'), isTrue);
    });
  });

  group('ConnectFlow — selected-server persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists the connected server after OIDC success', () async {
      final manager = _createManager();
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        serverManager: manager,
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(
        await SelectedServerStorage.load(),
        manager.servers.value.keys.single,
      );
    });

    test('persists the connected server when no auth is required', () async {
      final manager = _createManager();
      final flow = _createFlow(
        authFlow: FakeAuthFlow(),
        serverManager: manager,
        discover: (_, __) async => [],
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(
        await SelectedServerStorage.load(),
        manager.servers.value.keys.single,
      );
    });
  });

  group('ConnectFlow — onServerConnected', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fires once with the server URL after an OIDC login', () async {
      final manager = _createManager();
      Uri? connected;
      var calls = 0;
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        serverManager: manager,
        onServerConnected: (url) {
          connected = url;
          calls++;
        },
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(calls, 1);
      expect(
        connected.toString(),
        manager.servers.value.values.single.serverUrl.toString(),
      );
    });

    test('fires when a no-auth server is added', () async {
      var calls = 0;
      final flow = _createFlow(
        authFlow: FakeAuthFlow(),
        discover: (_, __) async => [],
        onServerConnected: (_) => calls++,
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(calls, 1);
    });
  });

  group('ConnectFlow._authenticate — storage failures', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('a throwing inactivity-flag store ends at an error', () async {
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        inactivityLogoutFlags: _ThrowingFlagStorage(),
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(flow.state.value, _connectError);
    });

    test('an Error during sign-in ends at an error and logs only its type',
        () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final flow = _createFlow(authFlow: FakeAuthFlow());

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(flow.state.value, _connectError);
      final record = sink.records
          .where((r) =>
              r.loggerName == 'soliplex.connect_flow' &&
              r.level == LogLevel.error)
          .single;
      expect(record.error, isNull);
      expect(record.attributes['failure'], isA<String>());
      expect(record.toString(), isNot(contains('set nextResult')));
    });

    test('an Exception during sign-in keeps its text in the record', () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        preAuthStateStorage: InMemoryPreAuthStateStorage(failSave: true),
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      final record = sink.records
          .where((r) =>
              r.loggerName == 'soliplex.connect_flow' &&
              r.level == LogLevel.error)
          .single;
      expect(record.error.toString(), contains('store unavailable'));
    });

    test('a throw that is not an Error keeps its text in the record', () async {
      // The shape of a web storage failure: a JS DOMException is neither a
      // Dart Exception nor an Error.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        inactivityLogoutFlags: _ThrowingFlagStorage()
          ..failure = 'QuotaExceededError: storage is full',
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(flow.state.value, _connectError);
      final record = sink.records
          .where((r) =>
              r.loggerName == 'soliplex.connect_flow' &&
              r.level == LogLevel.error)
          .single;
      expect(record.error, 'QuotaExceededError: storage is full');
    });

    test('a sign-in reset while its flag check fails stays reset', () async {
      final flags = _ThrowingFlagStorage()..gate = Completer<void>();
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        inactivityLogoutFlags: flags,
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();
      expect(flow.state.value, isA<Authenticating>());

      flow.reset();
      flags.gate!.complete();
      await pumpEventQueue();

      expect(
        flow.state.value,
        isA<UrlInput>().having((s) => s.message, 'message', isNull),
      );
    });

    test('a failed pre-auth save ends at an error, not the spinner', () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        preAuthStateStorage: InMemoryPreAuthStateStorage(failSave: true),
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(flow.state.value, _connectError);
      expect(
        sink.records.where((r) =>
            r.loggerName == 'soliplex.connect_flow' &&
            r.level == LogLevel.error),
        hasLength(1),
      );
    });

    test('a failed clear after a failed save still ends at an error', () async {
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        preAuthStateStorage:
            InMemoryPreAuthStateStorage(failSave: true, failClear: true),
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(flow.state.value, _connectError);
    });

    test('a failed clear after an IdP rejection still shows its message',
        () async {
      final flow = _createFlow(
        authFlow: FakeAuthFlow()
          ..nextError = const AuthException(
            'denied',
            kind: AuthFailureKind.idpRejected,
            oauthError: 'access_denied',
          ),
        preAuthStateStorage: InMemoryPreAuthStateStorage(failClear: true),
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(
        flow.state.value,
        isA<UrlInput>().having(
          (s) => s.message?.text,
          'message',
          describeAuthFailure(
            kind: AuthFailureKind.idpRejected,
            oauthError: 'access_denied',
            serverUrl: 'https://server.example.com',
          ),
        ),
      );
    });

    test('a failed post-login clear still connects', () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final manager = _createManager();
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        serverManager: manager,
        preAuthStateStorage: InMemoryPreAuthStateStorage(failClear: true),
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(flow.state.value, isA<Connected>());
      expect(manager.servers.value, isNotEmpty);
      expect(
        sink.records.where((r) =>
            r.loggerName == 'soliplex.pre_auth_state' &&
            r.level == LogLevel.warning),
        hasLength(1),
      );
    });
  });
}
