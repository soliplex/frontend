import 'dart:io';

import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_client_native/src/clients/cupertino_http_client.dart';

/// Creates platform-specific client for IO platforms.
///
/// Returns [CupertinoHttpClient] on macOS and iOS, otherwise returns
/// [DartHttpClient] for Android, Windows, and Linux.
///
/// Note: Falls back to [DartHttpClient] if native bindings are unavailable
/// (e.g., in Flutter test environment).
SoliplexHttpClient createPlatformClientImpl({
  Duration defaultTimeout = defaultHttpTimeout,
  HttpDiagnosticHandler? onDiagnostic,
}) {
  final handler = onDiagnostic ?? defaultHttpDiagnosticHandler;
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      return CupertinoHttpClient(
        defaultTimeout: defaultTimeout,
        onDiagnostic: handler,
      );
    } on Object catch (error, stackTrace) {
      // Fallback to DartHttpClient if native bindings unavailable
      // (e.g., in Flutter test environment). Silently downgrading would
      // hide the loss of NSURLSession's proxy, trust and HTTP/2 handling
      // behind whatever the request fails with later, so record it.
      safeDiagnosticHandler(handler)(
        error,
        stackTrace,
        message: 'Native HTTP client unavailable; using DartHttpClient',
      );
      return DartHttpClient(
        defaultTimeout: defaultTimeout,
        onDiagnostic: handler,
      );
    }
  }
  // Fallback to DartHttpClient for Android, Windows, Linux
  return DartHttpClient(
    defaultTimeout: defaultTimeout,
    onDiagnostic: handler,
  );
}
