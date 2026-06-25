import 'package:soliplex_client/src/domain/server_info.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_transport.dart';

/// Fetches the server's human-readable identity from the backend.
///
/// Calls `GET /api/v1/installation/identity` to retrieve the server's
/// configured name and description.
///
/// Returns `null` when the server has no identity configured (the backend
/// responds 404) so callers can fall back to displaying the raw address.
///
/// Parameters:
/// - [transport]: HTTP transport for making the request.
/// - [baseUrl]: Backend base URL (e.g., "https://api.example.com").
Future<ServerInfo?> fetchServerInfo({
  required HttpTransport transport,
  required Uri baseUrl,
}) async {
  final uri = baseUrl.resolve('/api/v1/installation/identity');
  try {
    final response = await transport.request<Map<String, dynamic>>('GET', uri);
    return ServerInfo.fromJson(response);
  } on NotFoundException {
    // Server configured no name/description — fall back to the raw address.
    return null;
  }
}
