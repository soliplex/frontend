import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';

import '../../helpers/fakes.dart';

const _provider = OidcProvider(
  discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
  clientId: 'test-client',
);

AuthTokens _tokens({Duration expiresIn = const Duration(hours: 1)}) {
  return AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().add(expiresIn),
  );
}

void main() {
  late FakeTokenRefreshService refreshService;
  late AuthSession session;

  setUp(() {
    refreshService = FakeTokenRefreshService();
    session = AuthSession(refreshService: refreshService);
  });

  group('initial state', () {
    test('is NoSession', () {
      expect(session.session.value, isA<NoSession>());
    });

    test('accessToken is null', () {
      expect(session.accessToken, isNull);
    });

    test('isAuthenticated is false', () {
      expect(session.isAuthenticated, isFalse);
    });
  });

  group('login', () {
    test('transitions to ActiveSession', () {
      final tokens = _tokens();
      session.login(provider: _provider, tokens: tokens);

      expect(session.session.value, isA<ActiveSession>());
      expect(session.isAuthenticated, isTrue);
    });

    test('accessToken returns the token', () {
      final tokens = _tokens();
      session.login(provider: _provider, tokens: tokens);

      expect(session.accessToken, 'access');
    });
  });

  group('logout', () {
    test('transitions to NoSession', () {
      session.login(provider: _provider, tokens: _tokens());
      session.logout();

      expect(session.session.value, isA<NoSession>());
      expect(session.isAuthenticated, isFalse);
      expect(session.accessToken, isNull);
    });
  });

  group('needsRefresh', () {
    test('false when not authenticated', () {
      expect(session.needsRefresh, isFalse);
    });

    test('false when tokens are fresh', () {
      session.login(provider: _provider, tokens: _tokens());
      expect(session.needsRefresh, isFalse);
    });

    test('true when tokens are expiring soon', () {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );
      expect(session.needsRefresh, isTrue);
    });
  });

  group('tryRefresh', () {
    test('success updates tokens', () async {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      refreshService.nextResult = TokenRefreshSuccess(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final result = await session.tryRefresh();

      expect(result, isTrue);
      expect(session.accessToken, 'new-access');
      final active = session.session.value as ActiveSession;
      expect(active.tokens.refreshToken, 'new-refresh');
    });

    test('invalidGrant logs out', () async {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      refreshService.nextResult = const TokenRefreshFailure(
        TokenRefreshFailureReason.invalidGrant,
      );

      final result = await session.tryRefresh();

      expect(result, isFalse);
      expect(session.isAuthenticated, isFalse);
    });

    test('other failure keeps session', () async {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      refreshService.nextResult = const TokenRefreshFailure(
        TokenRefreshFailureReason.networkError,
      );

      final result = await session.tryRefresh();

      expect(result, isFalse);
      expect(session.isAuthenticated, isTrue);
    });

    test('returns false when not authenticated', () async {
      final result = await session.tryRefresh();
      expect(result, isFalse);
    });

    test('returns false when refresh service throws', () async {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      // FakeTokenRefreshService with no nextResult throws StateError
      final result = await session.tryRefresh();

      expect(result, isFalse);
      expect(session.isAuthenticated, isTrue);
    });

    test('guards against session change during await', () async {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      final completer = Completer<TokenRefreshResult>();
      refreshService.nextResult = null;

      // Override refresh to use a completer we control
      final slowRefreshService = _DelayedRefreshService(completer.future);
      final slowSession = AuthSession(refreshService: slowRefreshService);
      slowSession.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      final refreshFuture = slowSession.tryRefresh();

      // Logout while refresh is in-flight
      slowSession.logout();

      // Complete the refresh
      completer.complete(
        TokenRefreshSuccess(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      final result = await refreshFuture;

      // Should not apply the refresh since session changed
      expect(result, isFalse);
      expect(slowSession.isAuthenticated, isFalse);
    });

    test('concurrent calls coalesce', () async {
      session.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      var callCount = 0;
      final countingService = _CountingRefreshService(
        result: TokenRefreshSuccess(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        onRefresh: () => callCount++,
      );
      final countingSession = AuthSession(refreshService: countingService);
      countingSession.login(
        provider: _provider,
        tokens: _tokens(expiresIn: const Duration(seconds: 30)),
      );

      final results = await Future.wait([
        countingSession.tryRefresh(),
        countingSession.tryRefresh(),
        countingSession.tryRefresh(),
      ]);

      expect(results, everyElement(isTrue));
      expect(callCount, 1);
    });
  });
}

/// Refresh service that delays until a future completes.
class _DelayedRefreshService extends TokenRefreshService {
  _DelayedRefreshService(this._future) : super(httpClient: FakeHttpClient());

  final Future<TokenRefreshResult> _future;

  @override
  Future<TokenRefreshResult> refresh({
    required String discoveryUrl,
    required String refreshToken,
    required String clientId,
  }) => _future;
}

/// Refresh service that counts calls.
class _CountingRefreshService extends TokenRefreshService {
  _CountingRefreshService({required this.result, required this.onRefresh})
    : super(httpClient: FakeHttpClient());

  final TokenRefreshResult result;
  final void Function() onRefresh;

  @override
  Future<TokenRefreshResult> refresh({
    required String discoveryUrl,
    required String refreshToken,
    required String clientId,
  }) async {
    onRefresh();
    return result;
  }
}
