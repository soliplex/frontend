import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';

/// Signature for the auth provider discovery function.
///
/// Defaults to [discoverAuthProviders] from soliplex_agent. Accepting this
/// as a parameter lets tests supply a fake without mocking HTTP responses.
typedef DiscoverProviders = Future<List<AuthProviderConfig>> Function(
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
  });

  final Uri serverUrl;
  final List<AuthProviderConfig> providers;

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
  Duration probeTimeout = const Duration(seconds: 5),
}) async {
  final List<Uri> candidates;
  try {
    candidates = _buildCandidateUrls(input);
  } on FormatException catch (e) {
    return ConnectionFailure(e);
  }

  NetworkException? lastNetworkError;
  final tried = <Uri>[];
  for (final uri in candidates) {
    tried.add(uri);
    try {
      final providers = await discover(uri, httpClient).timeout(probeTimeout);
      return ConnectionSuccess(serverUrl: uri, providers: providers);
    } on NetworkException catch (e) {
      lastNetworkError = e;
    } on TimeoutException {
      lastNetworkError = const NetworkException(
        message: 'Connection timed out',
        isTimeout: true,
      );
    } on Exception catch (e) {
      return ConnectionFailure(e, attemptedUrls: List.unmodifiable(tried));
    }
  }
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
