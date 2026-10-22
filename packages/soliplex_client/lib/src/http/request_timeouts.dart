/// Every request timeout the client sets, so each bound is chosen in one place
/// and none is lost inline.
///
/// Each bounds one attempt of a `request`, not the caller's total wait: the
/// platform client applies it to the response headers and again to the body
/// (a web multipart upload is bounded as a whole), a concurrency-limited
/// client starts it only once the request holds a slot, and a refreshing
/// client applies it afresh to the retry after a token refresh. OIDC
/// discovery and token refresh go through a client that does not refresh, so
/// they get no such retry.
library;

/// The timeout a platform client applies to a `request` that names none —
/// 10 minutes, sized for streamed upload bodies, which rely on it.
///
/// `requestStream` takes no timeout. On iOS/macOS the URLSession's request
/// timeout, built from this, ends a stream idle this long between chunks;
/// `AgUiStreamClient.followRun` ends a followed stream idle this long on every
/// platform.
const defaultHttpTimeout = Duration(seconds: 600);

/// For a small read whose answer gates something on screen — a capability,
/// a note, a setting's availability — so a slow answer is reported as one
/// rather than held for [defaultHttpTimeout]. A caller that must render
/// before the answer arrives still needs its own in-flight state.
const shortReadTimeout = Duration(seconds: 15);

/// For fetching an OIDC provider's discovery document.
const oidcDiscoveryTimeout = Duration(seconds: 10);

/// For exchanging a refresh token at the provider's token endpoint.
const tokenRefreshTimeout = Duration(seconds: 30);
