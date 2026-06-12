import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:soliplex_agent/soliplex_agent.dart'
    show SoliplexHttpClient, fetchOidcDiscoveryDocument;
import 'package:soliplex_client/soliplex_client.dart' show SoliplexException;

import 'auth_tokens.dart';
import 'platform/auth_flow.dart';
import 'server_entry.dart';

/// Signs [entry] out of its identity provider, clearing the local session.
///
/// Ordering of `entry.auth.logout()` relative to [AuthFlow.endSession] is
/// platform-conditional:
///
/// Native (iOS/macOS/Android): `endSession` opens a system browser sheet via
/// flutter_appauth, the IdP round-trip completes in-process, and control
/// returns to Dart. We clear the local session ONLY after `endSession` returns
/// cleanly. If it throws (user cancel, network, IdP unreachable), the local
/// session stays `ActiveSession` and the error propagates to the caller. This
/// keeps the invariant "local state matches IdP state."
///
/// Web: `WebAuthFlow.endSession` is a full-page navigation to the IdP's logout
/// endpoint — the SPA is unloading. There is no in-process signal of IdP
/// completion (the redirect-back is the confirmation, and by then the previous
/// page is gone). If we waited until after the await to clear local, the
/// post-await code would race the unload and likely not persist `NoSession` to
/// storage in time. On restoreServers(), the SPA would pick up a stale
/// `ActiveSession` and the user would appear signed in with dead tokens until
/// the next 401 → refresh → ExpiredSession cycle. So on web we clear local
/// BEFORE navigating, accepting the weaker invariant that if the user dismisses
/// the IdP logout sheet, local will be cleared even though the IdP session is
/// still alive. This drift self-corrects on the next sign-in (the IdP's SSO
/// cookie typically auto-issues fresh tokens for the same user without a
/// prompt).
///
/// The principled fix for web parity would be a backend "BFF logout" endpoint
/// (mirroring the existing `/api/login/{provider}` BFF sign-in pattern): the
/// frontend POSTs to the backend, which calls the IdP's logout
/// server-to-server (no CORS, no full-page navigation), and the await resolves
/// only when the IdP confirms — matching native semantics.
Future<void> logoutServer({
  required ServerEntry entry,
  required AuthFlow authFlow,
  required SoliplexHttpClient probeClient,
}) async {
  final session = entry.auth.session.value;
  if (session is! ActiveSession) {
    entry.auth.logout();
    return;
  }

  if (kIsWeb) {
    // Web needs the IdP's `end_session_endpoint` (extracted from the discovery
    // document) to navigate to. `WebAuthFlow.endSession` is a full-page
    // navigation, so local state is cleared first per the ordering note above.
    // A discovery-fetch failure bubbles to the caller and preserves the local
    // session — the alternative (degrading to `endSessionEndpoint = null`)
    // would clear local while the IdP session stays alive.
    final discovery = await fetchOidcDiscoveryDocument(
      Uri.parse(session.provider.discoveryUrl),
      probeClient,
    );
    entry.auth.logout();
    await authFlow.endSession(
      discoveryUrl: session.provider.discoveryUrl,
      endSessionEndpoint: discovery.endSessionEndpoint?.toString(),
      idToken: session.tokens.idToken ?? '',
      clientId: session.provider.clientId,
    );
    return;
  }

  // Native: `NativeAuthFlow.endSession` re-discovers via `discoveryUrl` through
  // `flutter_appauth`, so the `endSessionEndpoint` argument is unused — don't
  // pay for a pre-fetch.
  await authFlow.endSession(
    discoveryUrl: session.provider.discoveryUrl,
    endSessionEndpoint: null,
    idToken: session.tokens.idToken ?? '',
    clientId: session.provider.clientId,
  );
  entry.auth.logout();
}

/// Strips internal exception type names from common logout errors so a
/// "Log out failed: $msg" surface reads as a sentence rather than a stack
/// trace. The original exception should be logged separately; this is
/// render-only.
String friendlyLogoutError(Object e) {
  String raw;
  if (e is PlatformException) {
    raw = e.message ?? e.code;
  } else if (e is SoliplexException) {
    raw = e.message;
  } else if (e is Exception) {
    final s = e.toString();
    raw = s.startsWith('Exception: ') ? s.substring(11) : s;
  } else {
    // Unknown throwable (e.g. a stray Error from a programmer bug). Render a
    // generic one-liner rather than risk dumping a raw toString into a UI slot.
    raw = 'Sign-out failed. Please try again.';
  }
  const limit = 200;
  return raw.length > limit ? '${raw.substring(0, limit - 1)}…' : raw;
}
