import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:soliplex_agent/soliplex_agent.dart'
    show NetworkException, SoliplexHttpClient, fetchOidcDiscoveryDocument;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'auth_tokens.dart';
import 'platform/auth_flow.dart';
import 'server_entry.dart';
import 'server_manager.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.server_logout');

/// Signs [entry] out of its identity provider, clearing the local session
/// and, when [remove] is set, removing the server from [serverManager]. The
/// returned future completes once the storage writes for that local state
/// have settled.
///
/// Ordering of the local clear relative to [AuthFlow.endSession] is
/// platform-conditional:
///
/// Native (iOS/macOS/Android): `endSession` opens a system browser sheet via
/// flutter_appauth, the IdP round-trip completes in-process, and control
/// returns to Dart. We clear the local session ONLY after `endSession` returns
/// cleanly. If it throws (user cancel, network, IdP unreachable), the local
/// session stays signed in, the server is kept, and the error propagates to
/// the caller. This keeps the invariant "local state matches IdP state."
///
/// Web: `WebAuthFlow.endSession` is a full-page navigation to the IdP's logout
/// endpoint — the SPA is unloading. There is no in-process signal of IdP
/// completion (the redirect-back is the confirmation, and by then the previous
/// page is gone), and nothing after the navigation is sure to run. So on web
/// local state, the removal included, is cleared and written to storage
/// BEFORE navigating; otherwise restoreServers() could pick up a stale
/// `ActiveSession` or a removed server after the redirect back. This accepts
/// the weaker invariant that if the user abandons the IdP logout page (closes
/// the tab or navigates back), local will be cleared even though the IdP
/// session is still alive. This drift self-corrects on the next sign-in (the
/// IdP's SSO cookie typically auto-issues fresh tokens for the same user
/// without a prompt). A storage write that fails is logged by
/// [ServerManager], and the navigation still happens. On web this function
/// throws only for a failure before local state is cleared (the discovery
/// fetch); an `endSession` failure after it is logged, not thrown.
///
/// The principled fix for web parity would be a backend "BFF logout" endpoint
/// (mirroring the existing `/api/login/{provider}` BFF sign-in pattern): the
/// frontend POSTs to the backend, which calls the IdP's logout
/// server-to-server (no CORS, no full-page navigation), and the await resolves
/// only when the IdP confirms — matching native semantics.
Future<void> logoutServer({
  required ServerEntry entry,
  required ServerManager serverManager,
  required bool remove,
  required AuthFlow authFlow,
  required SoliplexHttpClient probeClient,
  // The platform branch is a seam so the web and native orderings — the
  // invariant this function exists to protect — are both reachable in a VM
  // test. Production always uses the real `kIsWeb`.
  bool web = kIsWeb,
}) async {
  Future<void> clearLocal() {
    entry.auth.logout();
    if (remove) serverManager.removeServer(entry.serverId);
    return serverManager.whenPersisted(entry.serverId);
  }

  // An expired session still ends the IdP session: Keycloak accepts an expired
  // `id_token_hint` (it checks only the signature), and the RP-initiated
  // logout spec expects IdPs to. Skipping it would leave the SSO session
  // signing the next sign-in straight back in.
  final signedIn = switch (entry.auth.session.value) {
    ActiveSession(:final provider, :final tokens) ||
    ExpiredSession(:final provider, :final tokens) =>
      (provider: provider, idToken: tokens.idToken),
    NoSession() => null,
  };
  if (signedIn == null) {
    await clearLocal();
    return;
  }
  final (:provider, :idToken) = signedIn;
  if (idToken == null) {
    // Without an `id_token_hint` the IdP can't tie the RP-initiated logout to a
    // specific session and may ignore it, leaving the IdP session alive. Make
    // that degraded outcome observable rather than omitting the hint
    // silently.
    _logger.warning(
      'Session has no id_token; RP-initiated logout omits id_token_hint and '
      'the IdP may not end its session',
      attributes: {'serverId': entry.serverId},
    );
  }

  if (web) {
    // Web needs the IdP's `end_session_endpoint` (extracted from the discovery
    // document) to navigate to. `WebAuthFlow.endSession` is a full-page
    // navigation, so local state is cleared and saved first per the ordering
    // note above.
    // A discovery-fetch failure bubbles to the caller and preserves the local
    // session — the alternative (degrading to `endSessionEndpoint = null`)
    // would clear local while the IdP session stays alive.
    final discovery = await fetchOidcDiscoveryDocument(
      Uri.parse(provider.discoveryUrl),
      probeClient,
    );
    final endSessionEndpoint = discovery.endSessionEndpoint?.toString();
    await clearLocal();
    if (endSessionEndpoint == null) {
      // The provider publishes no `end_session_endpoint`, so RP-initiated
      // logout is impossible — local state is cleared but the IdP's SSO
      // session stays alive. Make that partial logout observable instead of a
      // silent no-op.
      _logger.warning(
        'Web logout: provider has no end_session_endpoint; cleared local '
        'session only, IdP session not ended',
        attributes: {'serverId': entry.serverId},
      );
    }
    try {
      await authFlow.endSession(
        discoveryUrl: provider.discoveryUrl,
        endSessionEndpoint: endSessionEndpoint,
        idToken: idToken,
        clientId: provider.clientId,
      );
    } on Object catch (e, st) {
      // Local state is already cleared and saved, so throwing would tell the
      // caller the server was kept. Log the partial logout, as for a provider
      // with no `end_session_endpoint`.
      _logger.warning(
        'Web logout: ending the IdP session failed; cleared local session '
        'only, IdP session may not be ended',
        attributes: {
          'serverId': entry.serverId,
          'failure': describeFailure(e),
        },
        stackTrace: st,
      );
    }
    return;
  }

  // Native: `NativeAuthFlow.endSession` re-discovers via `discoveryUrl` through
  // `flutter_appauth`, so the `endSessionEndpoint` argument is unused — don't
  // pay for a pre-fetch.
  await authFlow.endSession(
    discoveryUrl: provider.discoveryUrl,
    endSessionEndpoint: null,
    idToken: idToken,
    clientId: provider.clientId,
  );
  await clearLocal();
}

/// Maps a logout failure to a fixed sentence, so the UI never shows
/// exception text.
String describeLogoutFailure(Object e) => switch (e) {
      AuthException(kind: AuthFailureKind.cancelled) =>
        'Sign-out was cancelled.',
      NetworkException() =>
        "Couldn't reach the identity provider. Check your connection and "
            'try again.',
      FormatException() =>
        "The identity provider's sign-out settings couldn't be read. Please "
            'try again.',
      _ => 'Sign-out failed. Please try again.',
    };
