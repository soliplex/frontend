import 'package:soliplex_agent/soliplex_agent.dart';

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

  /// Sync read for the HTTP client's getToken callback.
  ///
  /// Returns null for [ExpiredSession] — the access token is known dead
  /// and sending it as a header would just round-trip a guaranteed 401.
  String? get accessToken => switch (_session.value) {
        ActiveSession(:final tokens) => tokens.accessToken,
        ExpiredSession() => null,
        NoSession() => null,
      };

  /// Refresh token available for both active and expired sessions.
  String? get refreshToken => switch (_session.value) {
        ActiveSession(:final tokens) => tokens.refreshToken,
        ExpiredSession(:final tokens) => tokens.refreshToken,
        NoSession() => null,
      };

  bool get isAuthenticated => _session.value is ActiveSession;

  void login({required OidcProvider provider, required AuthTokens tokens}) {
    _session.value = ActiveSession(provider: provider, tokens: tokens);
  }

  void logout() {
    _session.value = const NoSession();
  }

  /// Flip an active or expired session to [ExpiredSession], preserving
  /// the tokens so a later refresh attempt can revive the session
  /// silently. No-op if the session is already expired or has been
  /// signed out.
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
    } catch (_) {
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
      case TokenRefreshFailure(
          reason: TokenRefreshFailureReason.noRefreshToken
        ):
        markSessionExpired();
        return false;

      case TokenRefreshFailure():
        return false;
    }
  }
}
