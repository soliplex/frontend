import 'dart:developer' as dev;

import 'package:soliplex_agent/soliplex_agent.dart';

import 'access_token_identity.dart';
import 'auth_tokens.dart';

/// Manages auth session and implements TokenRefresher for the HTTP client.
///
/// Reactive state via a single `Signal<SessionState>`. Riverpod just
/// locates this object.
class AuthSession implements TokenRefresher {
  AuthSession({required TokenRefreshService refreshService})
      : _refreshService = refreshService;

  final TokenRefreshService _refreshService;
  Future<bool>? _activeRefresh;

  final Signal<SessionState> _session = Signal<SessionState>(const NoSession());
  ReadonlySignal<SessionState> get session => _session;

  /// The live user's stable identity (`iss#sub`) for this server, or `null`
  /// when signed out or the access token can't be decoded. Resolves the token
  /// from ActiveSession AND ExpiredSession — a draft persisted on auth-expiry
  /// must still be attributable to the user. Re-evaluates only when the session
  /// changes and yields the same value across a same-user refresh, so watchers
  /// don't churn. Raw (un-encoded); key builders percent-encode it downstream.
  ///
  /// A `null` on an *authenticated* session (an opaque, non-JWT access token
  /// carrying no `iss`/`sub`) is expected, not an error: user-scoped
  /// device-local state then shares this server's unauthenticated bucket, since
  /// there is no identity claim to isolate it by.
  late final ReadonlySignal<String?> currentUserId = computed(() {
    final token = switch (_session.value) {
      ActiveSession(:final tokens) => tokens.accessToken,
      ExpiredSession(:final tokens) => tokens.accessToken,
      NoSession() => null,
    };
    return token == null ? null : accessTokenIdentity(token);
  });

  /// Sync read for the HTTP client's getToken callback.
  ///
  /// Returns null for [ExpiredSession] — the access token is known dead
  /// and sending it as a header would just round-trip a guaranteed 401.
  String? get accessToken => switch (_session.value) {
        ActiveSession(:final tokens) => tokens.accessToken,
        ExpiredSession() => null,
        NoSession() => null,
      };

  bool get isAuthenticated => _session.value is ActiveSession;

  void login({required OidcProvider provider, required AuthTokens tokens}) {
    _session.value = ActiveSession(provider: provider, tokens: tokens);
  }

  void logout() {
    _session.value = const NoSession();
  }

  /// Flip an active session to [ExpiredSession], preserving the tokens
  /// so a later refresh attempt can revive the session silently. No-op
  /// when the session is already expired or has been signed out.
  void markSessionExpired() {
    switch (_session.value) {
      case ActiveSession(:final provider, :final tokens):
        _session.value = ExpiredSession(provider: provider, tokens: tokens);
      case ExpiredSession():
      case NoSession():
        return;
    }
  }

  // ── TokenRefresher interface ──

  @override
  bool get needsRefresh {
    final current = _session.value;
    if (current is! ActiveSession) return false;
    final threshold = TokenRefreshService.refreshThreshold;
    return DateTime.now().isAfter(current.tokens.expiresAt.subtract(threshold));
  }

  @override
  Future<void> refreshIfExpiringSoon() async {
    if (!needsRefresh) return;
    await tryRefresh();
  }

  @override
  Future<bool> tryRefresh() {
    return _activeRefresh ??= _doRefresh().whenComplete(() {
      _activeRefresh = null;
    });
  }

  Future<bool> _doRefresh() async {
    final (provider, tokens) = switch (_session.value) {
      ActiveSession(:final provider, :final tokens) => (provider, tokens),
      ExpiredSession(:final provider, :final tokens) => (provider, tokens),
      NoSession() => (null, null),
    };
    if (provider == null || tokens == null) return false;

    final TokenRefreshResult result;
    try {
      result = await _refreshService.refresh(
        discoveryUrl: provider.discoveryUrl,
        refreshToken: tokens.refreshToken,
        clientId: provider.clientId,
      );
    } on AuthException catch (e, st) {
      dev.log(
        'Token refresh threw AuthException; funneling to markSessionExpired',
        error: e,
        stackTrace: st,
        level: 900,
      );
      markSessionExpired();
      return false;
    } catch (e, st) {
      // Deliberately does NOT funnel via `markSessionExpired` (unlike
      // the AuthException arm above): an unexpected throw here is a
      // bug or a transient anomaly, not proof the IdP grant is dead.
      // Flipping to ExpiredSession would lock the user out for a
      // recoverable failure. Log SEVERE and let the next API call
      // surface the real status via AuthException → funnel.
      dev.log(
        'Token refresh threw before producing a result',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return false;
    }

    // User-initiated sign-out during the await wins; everything else
    // (including a concurrent flip to ExpiredSession) accepts the new
    // tokens.
    if (_session.value is NoSession) return false;

    switch (result) {
      case TokenRefreshSuccess():
        _session.value = ActiveSession(
          provider: provider,
          tokens: AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: result.expiresAt,
            idToken: result.idToken ?? tokens.idToken,
          ),
        );
        return true;

      case TokenRefreshFailure(reason: TokenRefreshFailureReason.invalidGrant):
        dev.log(
          'Token refresh rejected (invalid_grant) for ${provider.discoveryUrl}',
          level: 900,
        );
        markSessionExpired();
        return false;

      case TokenRefreshFailure(
          reason: TokenRefreshFailureReason.noRefreshToken
        ):
        // A refresh attempt without a refresh token is a frontend
        // invariant violation: the session should never have been
        // marked refreshable in the first place.
        dev.log(
          'Token refresh requested without a refresh token '
          'for ${provider.discoveryUrl}',
          level: 1000,
        );
        markSessionExpired();
        return false;

      case TokenRefreshFailure(:final reason):
        // networkError is recoverable on retry; unknownError is the
        // anomaly worth a SEVERE entry.
        dev.log(
          'Token refresh failed (${reason.name}) for ${provider.discoveryUrl}',
          level: reason == TokenRefreshFailureReason.networkError ? 900 : 1000,
        );
        return false;
    }
  }
}
