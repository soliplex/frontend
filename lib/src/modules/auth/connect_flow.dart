import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_agent/soliplex_agent.dart' as agent show AuthException;

import 'auth_failure_description.dart';
import 'auth_tokens.dart';
import 'connection_probe.dart';
import 'consent_notice.dart';
import 'default_backend_url.dart';
import 'inactivity_logout_storage.dart';
import 'platform/auth_flow.dart';
import 'pre_auth_state.dart';
import 'selected_server_storage.dart';
import 'server_entry.dart';
import 'server_manager.dart';

/// State of the server connection flow.
sealed class ConnectState {
  const ConnectState();
}

/// A message to show on the URL-input screen.
sealed class ConnectMessage {
  const ConnectMessage(this.text);
  final String text;
}

/// An alarming failure (network, server rejection, …) — rendered red.
final class ConnectError extends ConnectMessage {
  const ConnectError(super.text);
}

/// A neutral, non-alarming message (sign-in cancelled, session expired) —
/// rendered without error styling.
final class ConnectNotice extends ConnectMessage {
  const ConnectNotice(super.text);
}

final class UrlInput extends ConnectState {
  const UrlInput({this.message});
  final ConnectMessage? message;
}

final class Probing extends ConnectState {
  const Probing();
}

final class InsecureWarning extends ConnectState {
  const InsecureWarning({required this.probeResult, required this.providers});
  final ConnectionSuccess probeResult;
  final List<AuthProviderConfig> providers;
}

final class Consent extends ConnectState {
  const Consent({
    required this.notice,
    required this.probeResult,
    required this.providers,
  });
  final ConsentNotice notice;
  final ConnectionSuccess probeResult;
  final List<AuthProviderConfig> providers;
}

final class ProviderSelection extends ConnectState {
  const ProviderSelection({required this.probeResult, required this.providers});
  final ConnectionSuccess probeResult;
  final List<AuthProviderConfig> providers;
}

final class Authenticating extends ConnectState {
  const Authenticating();
}

final class Connected extends ConnectState {
  const Connected();
}

/// Orchestrates the server connection flow: probe → consent → auth.
///
/// Pure Dart — no Flutter dependency. Owns a [Signal] that widgets
/// subscribe to for state changes.
class ConnectFlow {
  ConnectFlow({
    required this.serverManager,
    required this.probeClient,
    required this.discover,
    required this.authFlow,
    required this.inactivityLogoutFlags,
    this.consentNotice,
  });

  final ServerManager serverManager;
  final SoliplexHttpClient probeClient;
  final DiscoverProviders discover;
  final AuthFlow authFlow;
  final InactivityLogoutFlagStorage inactivityLogoutFlags;
  final ConsentNotice? consentNotice;

  final Signal<ConnectState> state = Signal<ConnectState>(const UrlInput());

  bool _disposed = false;
  int _generation = 0;

  /// Held between the start of [connect] and the eventual save of
  /// `PreAuthState` so the user lands back where they came from after
  /// a successful re-auth. Carried across consent / provider-selection
  /// pauses since those don't reset the flow.
  String? _pendingReturnTo;

  bool _isCancelled(int gen) => _disposed || gen != _generation;

  Future<void> connect(String url, {String? returnTo}) async {
    if (state.value is! UrlInput) return;
    final gen = ++_generation;
    _pendingReturnTo = returnTo;
    state.value = const Probing();

    try {
      final result = await probeConnection(
        input: url,
        httpClient: probeClient,
        discover: discover,
      );

      if (_isCancelled(gen)) return;

      switch (result) {
        case ConnectionSuccess():
          final resultId = serverIdFromUrl(result.serverUrl);
          final existing = serverManager.servers.value[resultId];
          if (existing != null && existing.isConnected) {
            await SelectedServerStorage.save(resultId);
            if (!_isCancelled(gen)) state.value = const Connected();
            return;
          }
          if (result.isInsecure) {
            state.value = InsecureWarning(
              probeResult: result,
              providers: result.providers,
            );
            return;
          }
          _proceedAfterProbe(result, result.providers);
        case ConnectionFailure(:final error, :final attemptedUrls):
          state.value = UrlInput(
            message: ConnectError(
              describeConnectionError(error, attemptedUrls),
            ),
          );
      }
    } catch (e, st) {
      debugPrint('ConnectFlow.connect: $e\n$st');
      if (!_isCancelled(gen)) {
        state.value = UrlInput(
          message: ConnectError('Unexpected error connecting to $url: $e'),
        );
      }
    }
  }

  void acceptInsecure() {
    if (state.value
        case InsecureWarning(:final probeResult, :final providers)) {
      _proceedAfterProbe(probeResult, providers);
    }
  }

  void acknowledgeConsent() {
    if (state.value case Consent(:final probeResult, :final providers)) {
      _proceedAfterConsent(probeResult, providers);
    }
  }

  void selectProvider(AuthProviderConfig provider) {
    if (state.value case ProviderSelection(:final probeResult)) {
      _authenticate(provider, probeResult: probeResult);
    }
  }

  void reset() {
    _generation++;
    _pendingReturnTo = null;
    state.value = const UrlInput();
  }

  void dispose() {
    _disposed = true;
  }

  void _proceedAfterProbe(
    ConnectionSuccess probeResult,
    List<AuthProviderConfig> providers,
  ) {
    if (consentNotice != null) {
      state.value = Consent(
        notice: consentNotice!,
        probeResult: probeResult,
        providers: providers,
      );
    } else {
      _proceedAfterConsent(probeResult, providers);
    }
  }

  void _proceedAfterConsent(
    ConnectionSuccess probeResult,
    List<AuthProviderConfig> providers,
  ) {
    if (providers.isEmpty) {
      _addServerNoAuth(probeResult);
    } else if (providers.length == 1) {
      _authenticate(providers.first, probeResult: probeResult);
    } else {
      state.value = ProviderSelection(
        probeResult: probeResult,
        providers: providers,
      );
    }
  }

  Future<void> _addServerNoAuth(ConnectionSuccess probeResult) async {
    final gen = _generation;
    final serverId = serverIdFromUrl(probeResult.serverUrl);
    serverManager.addServer(
      serverId: serverId,
      serverUrl: probeResult.serverUrl,
      requiresAuth: false,
    );
    DefaultBackendUrlStorage.save(probeResult.serverUrl.toString());
    await SelectedServerStorage.save(serverId);
    if (!_isCancelled(gen)) state.value = const Connected();
  }

  Future<void> _authenticate(
    AuthProviderConfig provider, {
    required ConnectionSuccess probeResult,
  }) async {
    final gen = ++_generation;
    state.value = const Authenticating();

    final discoveryUrl =
        '${provider.serverUrl}/.well-known/openid-configuration';

    await PreAuthStateStorage.save(PreAuthState(
      serverUrl: probeResult.serverUrl,
      providerId: provider.id,
      discoveryUrl: discoveryUrl,
      clientId: provider.clientId,
      createdAt: DateTime.timestamp(),
      frontendReturnTo: _pendingReturnTo,
    ));

    final serverId = serverIdFromUrl(probeResult.serverUrl);
    final forceLoginPrompt = await inactivityLogoutFlags.isMarked(serverId);

    if (_isCancelled(gen)) return;

    try {
      final authResult = await authFlow.authenticate(
        provider,
        backendUrl: probeResult.serverUrl,
        forceLoginPrompt: forceLoginPrompt,
      );

      if (_isCancelled(gen)) return;

      final entry = serverManager.addServer(
        serverId: serverId,
        serverUrl: probeResult.serverUrl,
      );

      entry.auth.login(
        provider: OidcProvider(
          discoveryUrl: discoveryUrl,
          clientId: provider.clientId,
        ),
        tokens: AuthTokens(
          accessToken: authResult.accessToken,
          refreshToken: authResult.refreshToken ?? '',
          expiresAt: authResult.expiresAt ??
              DateTime.now().add(AuthTokens.defaultLifetime),
          idToken: authResult.idToken,
        ),
      );

      // Post-login housekeeping is best-effort: the user is already
      // signed in, so a storage failure here must not bounce them to the
      // error state. Guard the PreAuthState clear (the inactivity flag
      // store swallows its own failures).
      try {
        await PreAuthStateStorage.clear();
      } catch (e, st) {
        debugPrint(
            'ConnectFlow: post-login PreAuthState clear failed: $e\n$st');
      }
      // Only clear after a successful login. If the IdP challenge was
      // cancelled or failed, the flag stays set so the next attempt
      // also forces prompt=login.
      await inactivityLogoutFlags.clear(serverId);
      DefaultBackendUrlStorage.save(probeResult.serverUrl.toString());
      if (!_isCancelled(gen)) {
        await SelectedServerStorage.save(serverId);
        if (!_isCancelled(gen)) state.value = const Connected();
      }
    } on AuthRedirectInitiated {
      // Web: browser is redirecting to IdP. The flag stays set;
      // AuthCallbackScreen clears it after persisting the new tokens.
    } on AuthException catch (e) {
      await PreAuthStateStorage.clear();
      if (!_isCancelled(gen)) {
        final description = describeAuthFailure(
          kind: e.kind,
          oauthError: e.oauthError,
          serverUrl: probeResult.serverUrl.toString(),
        );
        state.value = UrlInput(
          message: e.kind == AuthFailureKind.cancelled
              ? ConnectNotice(description)
              : ConnectError(description),
        );
      }
    } on Exception catch (e, st) {
      debugPrint('ConnectFlow._authenticate: $e\n$st');
      await PreAuthStateStorage.clear();
      if (!_isCancelled(gen)) {
        state.value = UrlInput(
          message: ConnectError(
            describeAuthFailure(kind: AuthFailureKind.unknown),
          ),
        );
      }
    }
  }
}

String describeConnectionError(Object error, List<Uri> attemptedUrls) {
  final url = attemptedUrls.join(' or ');
  final String detail;
  final String? serverDetail;
  switch (error) {
    case agent.AuthException(:final statusCode, :final serverMessage):
      serverDetail = serverMessage;
      detail = statusCode == 401
          ? 'Authentication required. $url requires login '
              'credentials. ($statusCode)'
          : 'Access denied by $url. The server may require additional '
              'configuration or may be blocking this connection. '
              '($statusCode)';
    case NotFoundException(:final serverMessage):
      serverDetail = serverMessage;
      detail = 'Server at $url was reached, but the expected API '
          'endpoint was not found. The server version may be '
          'incompatible. (404)';
    case CancelledException(:final reason):
      serverDetail = null;
      detail =
          reason != null ? 'Request cancelled: $reason' : 'Request cancelled.';
    case NetworkException(:final isTimeout, :final message):
      serverDetail = isTimeout ? null : message;
      detail = isTimeout
          ? 'Connection to $url timed out. '
              'The server may be slow or unreachable.'
          : 'Cannot reach $url. Check the URL and your '
              'network connection.';
    case ApiException(:final statusCode, :final serverMessage):
      serverDetail = serverMessage;
      detail = statusCode >= 500
          ? 'Server error at $url. '
              'Please try again later. ($statusCode)'
          : 'Unexpected response from $url. ($statusCode)';
    default:
      return 'Connection to $url failed: $error';
  }
  return serverDetail != null ? '$detail\n\nDetails: $serverDetail' : detail;
}
