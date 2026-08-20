import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'platform/host_resolution.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.connection_probe');

/// Signature for the auth provider discovery function.
///
/// Defaults to [discoverAuthProviders] from soliplex_agent. Accepting this
/// as a parameter lets tests supply a fake without mocking HTTP responses.
typedef DiscoverProviders = Future<List<AuthProviderConfig>> Function(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
);

/// Signature for fetching a server's human-readable identity.
///
/// Defaults to [discoverServerInfo] from soliplex_agent, which returns `null`
/// only for a 404 (server configures no name/description) and otherwise throws.
/// [probeConnection] treats any failure here as best-effort and falls back to
/// `null`, so server info never fails a probe.
typedef DiscoverServerInfo = Future<ServerInfo?> Function(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
);

/// Result of probing a backend URL for connectivity.
sealed class ConnectionProbeResult {
  const ConnectionProbeResult();
}

/// Backend was reached successfully.
class ConnectionSuccess extends ConnectionProbeResult {
  const ConnectionSuccess({
    required this.serverUrl,
    required this.providers,
    this.info,
  });

  final Uri serverUrl;
  final List<AuthProviderConfig> providers;

  /// The server's human-readable identity, or `null` when the server
  /// configures none (or the metadata call failed). Callers fall back to the
  /// raw [serverUrl] when this is absent.
  final ServerInfo? info;

  /// Whether the connection uses HTTP (not HTTPS).
  bool get isInsecure => serverUrl.scheme == 'http';
}

/// Backend could not be reached.
class ConnectionFailure extends ConnectionProbeResult {
  const ConnectionFailure(this.error, {this.attemptedUrls = const []});

  final Object error;

  /// The URLs that were actually tried before failing.
  final List<Uri> attemptedUrls;
}

/// Probes a backend by trying HTTPS first, falling back to HTTP on network
/// errors.
///
/// If the input has an explicit scheme, only that scheme is tried.
/// For schemeless input, tries `https://` first. If that fails with a
/// [NetworkException], tries `http://`. Non-network errors (4xx, 5xx) are
/// not retried since they indicate the server was reachable.
///
/// Pass [discover] to override the default [discoverAuthProviders] for testing.
Future<ConnectionProbeResult> probeConnection({
  required String input,
  required SoliplexHttpClient httpClient,
  DiscoverProviders discover = _defaultDiscover,
  DiscoverServerInfo discoverInfo = _defaultDiscoverInfo,
  Duration probeTimeout = const Duration(seconds: 5),
}) async {
  final List<Uri> candidates;
  try {
    candidates = _buildCandidateUrls(input);
  } on FormatException catch (e) {
    _logger.warning(
      'Probe rejected the address before any request',
      error: e,
      attributes: {'input': '"$input"', 'inputLength': input.length},
    );
    return ConnectionFailure(e);
  }

  final started = DateTime.now();
  NetworkException? lastNetworkError;
  final tried = <Uri>[];
  for (final uri in candidates) {
    tried.add(uri);
    try {
      final providers = await discover(uri, httpClient).timeout(probeTimeout);
      // Server identity is best-effort enrichment: any failure here (404, slow
      // response, network blip, malformed or empty body) must not turn a
      // successful probe into a failure, so log it and fall back to null.
      ServerInfo? info;
      try {
        info = await discoverInfo(uri, httpClient).timeout(probeTimeout);
      } on Object catch (e) {
        _logger.warning(
          'Server info fetch failed for $uri; using raw address',
          error: e,
        );
        info = null;
      }
      return ConnectionSuccess(
        serverUrl: uri,
        providers: providers,
        info: info,
      );
    } on NetworkException catch (e) {
      lastNetworkError = e;
    } on TimeoutException {
      lastNetworkError = const NetworkException(
        message: 'Connection timed out',
        isTimeout: true,
      );
    } on Exception catch (e) {
      _logger.warning(
        'Probe failed with a non-network error',
        error: e,
        attributes: {
          'requestedUrl': uri.toString(),
          'errorType': e.runtimeType.toString(),
          'elapsedMs': DateTime.now().difference(started).inMilliseconds,
        },
      );
      return ConnectionFailure(e, attemptedUrls: List.unmodifiable(tried));
    }
  }
  // Stopped before the resolver check below, so it measures the probe rather
  // than the probe plus the diagnostic that follows it. An instant failure
  // means no resolution was attempted; seconds mean a real attempt that failed.
  final elapsedMs = DateTime.now().difference(started).inMilliseconds;
  // Ask the platform resolver directly: a "cannot find host" from the HTTP
  // stack does not distinguish a real resolver failure from anything else in
  // that stack preventing the lookup.
  //
  // This delays the failure the user is waiting on, which is why the lookup is
  // held to a short deadline: a resolver that has not answered by then has
  // already told us what the record needs to say.
  final hostResolution = await describeHostResolution(tried.last.host);
  _logger.warning(
    'Probe exhausted every candidate address',
    error: lastNetworkError,
    attributes: {
      'input': '"$input"',
      'inputLength': input.length,
      'candidates': tried.map((u) => u.toString()).toList(),
      'hosts': tried.map((u) => '"${u.host}"').toList(),
      'hostResolution': hostResolution,
      'errorType': lastNetworkError?.runtimeType.toString(),
      'isTimeout': lastNetworkError?.isTimeout,
      // The platform error carries the domain and numeric code (e.g.
      // NSURLErrorDomain -1003), which name the failure far more precisely
      // than the localized sentence shown to the user.
      'platformError': lastNetworkError?.originalError?.toString(),
      'elapsedMs': elapsedMs,
    },
  );
  return ConnectionFailure(
    lastNetworkError ?? Exception('No reachable server at: $input'),
    attemptedUrls: List.unmodifiable(tried),
  );
}

/// Parses user input into candidate URIs to probe, in priority order.
///
/// For schemeless input, returns [https, http]. For explicit schemes,
/// returns a single URI. Strips trailing slashes.
List<Uri> _buildCandidateUrls(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Server URL cannot be empty');
  }

  // Use string check instead of Uri.hasScheme to avoid Dart's parser treating
  // `localhost:8000` as scheme `localhost` with path `8000`.
  final hasScheme = trimmed.contains('://');

  if (hasScheme) {
    final uri = Uri.parse(trimmed);
    if (uri.host.isEmpty) {
      throw FormatException('Invalid server URL: $input');
    }
    return [_stripTrailingSlash(uri)];
  }

  final httpsUri = Uri.tryParse('https://$trimmed');
  if (httpsUri == null || httpsUri.host.isEmpty) {
    throw FormatException('Invalid server URL: $input');
  }

  return [
    _stripTrailingSlash(httpsUri),
    _stripTrailingSlash(Uri.parse('http://$trimmed')),
  ];
}

Uri _stripTrailingSlash(Uri uri) {
  final path = uri.path;
  if (path.endsWith('/')) {
    return uri.replace(path: path.substring(0, path.length - 1));
  }
  return uri;
}

Future<List<AuthProviderConfig>> _defaultDiscover(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) =>
    discoverAuthProviders(serverUrl: serverUrl, httpClient: httpClient);

Future<ServerInfo?> _defaultDiscoverInfo(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) =>
    discoverServerInfo(serverUrl: serverUrl, httpClient: httpClient);
