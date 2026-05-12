import 'dart:convert';

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';

/// Represents a validated OIDC discovery document.
///
/// Contains endpoint URLs extracted from an OpenID Provider Configuration
/// Document, with origin validation applied to prevent redirect attacks.
class OidcDiscoveryDocument {
  const OidcDiscoveryDocument._({
    required this.tokenEndpoint,
    this.endSessionEndpoint,
  });

  /// Parses discovery JSON, validating required fields and endpoint origins.
  ///
  /// Throws [FormatException] if:
  /// - Required `token_endpoint` is missing
  /// - Any endpoint fails origin validation (scheme/host/port mismatch)
  factory OidcDiscoveryDocument.fromJson(
    Map<String, dynamic> json,
    Uri discoveryUrl,
  ) {
    final tokenEndpoint = json['token_endpoint'] as String?;
    if (tokenEndpoint == null) {
      throw const FormatException(
        'OIDC discovery missing required token_endpoint',
      );
    }

    final tokenUri = Uri.parse(tokenEndpoint);
    _validateOrigin(tokenUri, discoveryUrl, 'token_endpoint');

    final endSessionEndpoint = json['end_session_endpoint'] as String?;
    Uri? endSessionUri;
    if (endSessionEndpoint != null) {
      endSessionUri = Uri.parse(endSessionEndpoint);
      _validateOrigin(endSessionUri, discoveryUrl, 'end_session_endpoint');
    }

    return OidcDiscoveryDocument._(
      tokenEndpoint: tokenUri,
      endSessionEndpoint: endSessionUri,
    );
  }

  /// Token endpoint URL (required per OIDC spec).
  final Uri tokenEndpoint;

  /// End session endpoint URL (optional per OIDC spec).
  ///
  /// Null if the IdP doesn't support RP-initiated logout.
  final Uri? endSessionEndpoint;

  /// Validates that an endpoint's origin matches the discovery URL's origin.
  ///
  /// Origin is defined as scheme + host + port (per browser same-origin
  /// policy). Throws [FormatException] on mismatch to prevent SSRF and
  /// redirect attacks.
  static void _validateOrigin(Uri endpoint, Uri discoveryUrl, String name) {
    if (endpoint.scheme != discoveryUrl.scheme ||
        endpoint.host != discoveryUrl.host ||
        endpoint.port != discoveryUrl.port) {
      throw FormatException(
        'OIDC $name origin mismatch: expected ${discoveryUrl.origin}, '
        'got ${endpoint.origin}',
      );
    }
  }
}

/// Fetches and parses an OIDC discovery document.
///
/// Throws:
/// - [NetworkException] on HTTP errors (connection failures, timeouts)
/// - [FormatException] on non-200 status, invalid JSON, missing required
///   fields, or origin mismatch
Future<OidcDiscoveryDocument> fetchOidcDiscoveryDocument(
  Uri discoveryUrl,
  SoliplexHttpClient httpClient, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final HttpResponse response;
  try {
    response = await httpClient.request('GET', discoveryUrl, timeout: timeout);
  } on Exception catch (e, st) {
    Error.throwWithStackTrace(
      NetworkException(
        message: 'Failed to fetch OIDC discovery document',
        originalError: e,
      ),
      st,
    );
  }

  if (response.statusCode != 200) {
    throw FormatException(
      'OIDC discovery failed with status ${response.statusCode}',
    );
  }

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException catch (_, st) {
    Error.throwWithStackTrace(
      const FormatException('Invalid OIDC discovery document JSON'),
      st,
    );
  }

  return OidcDiscoveryDocument.fromJson(json, discoveryUrl);
}
