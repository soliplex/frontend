import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:web/web.dart' as web;

import 'auth_flow.dart';

/// Abstraction for URL navigation to enable testing.
abstract class UrlNavigator {
  /// Gets the current page origin (e.g., 'https://example.com').
  String get origin;

  /// Navigates to the given URL.
  void navigateTo(String url);
}

/// Default implementation using browser window.
class WindowUrlNavigator implements UrlNavigator {
  @override
  String get origin => web.window.location.origin;

  @override
  void navigateTo(String url) {
    web.window.location.href = url;
  }
}

/// Creates the web platform implementation of [AuthFlow].
///
/// [redirectScheme] is ignored on web (uses origin-based redirect via BFF).
/// [navigator] is injected for testability.
AuthFlow createAuthFlow({
  required String redirectScheme,
  UrlNavigator? navigator,
}) => WebAuthFlow(navigator: navigator);

/// Web OIDC authentication using BFF pattern.
///
/// Redirects to backend OAuth endpoint which handles PKCE and token exchange.
/// Tokens are returned in the callback URL.
class WebAuthFlow implements AuthFlow {
  @visibleForTesting
  WebAuthFlow({UrlNavigator? navigator})
    : _navigator = navigator ?? WindowUrlNavigator();

  final UrlNavigator _navigator;

  @override
  Future<AuthResult> authenticate(
    AuthProviderConfig provider, {
    Uri? backendUrl,
  }) async {
    final frontendOrigin = _navigator.origin;
    final returnTo = Uri.encodeFull('$frontendOrigin/#/auth/callback');

    // Use backendUrl for BFF endpoint, fall back to same origin.
    final backend = backendUrl?.toString() ?? frontendOrigin;

    final loginUrl = '$backend/api/login/${provider.id}?return_to=$returnTo';
    _navigator.navigateTo(loginUrl);

    // Browser navigates away; throw to make the type system honest.
    throw const AuthRedirectInitiated();
  }

  @override
  Future<void> endSession({
    required String discoveryUrl,
    required String? endSessionEndpoint,
    required String idToken,
    required String clientId,
  }) async {
    if (endSessionEndpoint == null) return;

    final frontendOrigin = _navigator.origin;
    final baseUri = Uri.parse(endSessionEndpoint);
    final logoutUri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'post_logout_redirect_uri': frontendOrigin,
        'client_id': clientId,
        if (idToken.isNotEmpty) 'id_token_hint': idToken,
      },
    );

    _navigator.navigateTo(logoutUri.toString());
  }
}
