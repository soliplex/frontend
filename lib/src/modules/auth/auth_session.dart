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
  String? get accessToken => switch (_session.value) {
        ActiveSession(:final tokens) => tokens.accessToken,
        NoSession() => null,
      };

  bool get isAuthenticated => _session.value is ActiveSession;

  void login({required OidcProvider provider, required AuthTokens tokens}) {
    _session.value = ActiveSession(provider: provider, tokens: tokens);
  }

  void logout() {
    _session.value = const NoSession();
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
    final current = _session.value;
    if (current is! ActiveSession) return false;

    final TokenRefreshResult result;
    try {
      result = await _refreshService.refresh(
        discoveryUrl: current.provider.discoveryUrl,
        refreshToken: current.tokens.refreshToken,
        clientId: current.provider.clientId,
      );
    } catch (_) {
      return false;
    }

    // Guard: session may have changed (logout or re-login) during the await.
    if (!identical(_session.value, current)) return false;

    switch (result) {
      case TokenRefreshSuccess():
        _session.value = ActiveSession(
          provider: current.provider,
          tokens: AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: result.expiresAt,
            idToken: result.idToken ?? current.tokens.idToken,
          ),
        );
        return true;

      case TokenRefreshFailure(reason: TokenRefreshFailureReason.invalidGrant):
        logout();
        return false;

      case TokenRefreshFailure():
        return false;
    }
  }
}
