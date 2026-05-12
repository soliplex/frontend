import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';

/// Default timeout for HTTP requests (10 minutes).
///
/// This timeout applies to both regular requests and streaming connections.
/// For SSE connections on iOS/macOS, this controls the maximum time between
/// data chunks before the connection is considered dead.
const kDefaultHttpTimeout = Duration(seconds: 600);

/// Abstract interface for Soliplex HTTP clients.
///
/// Implementations wrap platform-specific HTTP clients to provide a unified
/// interface for making HTTP requests. Use `DartHttpClient` for the default
/// pure-Dart implementation using `package:http`.
///
/// Example:
/// ```dart
/// final client = DartHttpClient();
/// final response = await client.request(
///   'GET',
///   Uri.parse('https://api.example.com/data'),
/// );
/// print(response.body);
/// client.close();
/// ```
abstract class SoliplexHttpClient {
  /// Performs an HTTP request and returns the complete response.
  ///
  /// Parameters:
  /// - [method]: HTTP method (GET, POST, PUT, DELETE, PATCH, etc.)
  /// - [uri]: The request URI
  /// - [headers]: Optional request headers
  /// - [body]: Optional request body. Supported types:
  ///   - `String`: Sent as-is with UTF-8 encoding
  ///   - `List<int>`: Sent as raw bytes
  ///   - `Map<String, dynamic>`: JSON encoded automatically
  /// - [timeout]: Request timeout. Uses client's default if not specified.
  ///
  /// Throws `NetworkException` on connection failures or timeouts.
  /// Throws `CancelledException` if the request was cancelled.
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  });

  /// Performs a streaming HTTP request and returns a [StreamedHttpResponse].
  ///
  /// Used for SSE (Server-Sent Events) and other streaming protocols.
  /// The returned [StreamedHttpResponse] contains the HTTP status code and
  /// headers, plus a body stream that emits byte chunks as they arrive.
  ///
  /// **Cancel semantics:** Cancelling the body stream's subscription (either
  /// directly or via [cancelToken]) sends an abrupt TCP close (RST) to the
  /// server. This can cause server-side connection pool errors. For SSE
  /// streams where the server sends a terminal application event before
  /// closing, prefer detaching the subscription reference rather than
  /// cancelling — let the server close the stream naturally.
  ///
  /// Parameters:
  /// - [method]: HTTP method (typically GET or POST)
  /// - [uri]: The request URI
  /// - [headers]: Optional request headers
  /// - [body]: Optional request body (same types as [request])
  /// - [cancelToken]: Optional token for cancelling the request. When
  ///   cancelled, throws [CancelledException] instead of proceeding.
  ///
  /// Throws `NetworkException` on connection failures.
  /// Throws `CancelledException` if the request was cancelled.
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  });

  /// Closes the client and releases any resources.
  ///
  /// After calling this method, no further requests should be made.
  /// Calling [close] multiple times is safe.
  void close();
}
