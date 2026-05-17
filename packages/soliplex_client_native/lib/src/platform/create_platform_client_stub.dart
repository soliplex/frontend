import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_client_native/src/clients/web_xhr_http_client.dart';

/// Platform-specific client factory for the web target.
///
/// Returns [WebXhrHttpClient], which delegates to [DartHttpClient] for
/// all non-upload traffic. For file uploads carrying a
/// [WebMultipartFileBody] it switches to `XMLHttpRequest + FormData`
/// so the browser handles multipart encoding natively and streams from
/// the file's disk-backed Blob — file bytes never enter the JS heap.
SoliplexHttpClient createPlatformClientImpl({
  Duration defaultTimeout = defaultHttpTimeout,
}) {
  return WebXhrHttpClient(defaultTimeout: defaultTimeout);
}
