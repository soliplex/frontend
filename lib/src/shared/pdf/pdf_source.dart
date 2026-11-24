import 'package:flutter/foundation.dart';

/// A PDF the viewer can open: what to call it, and how to get its bytes.
@immutable
class PdfViewerSource {
  const PdfViewerSource({
    required this.title,
    required this.origin,
    required this.cacheKey,
    required this.load,
    this.sizeBytes,
    this.whenGone,
  });

  /// The file name the header shows.
  final String title;

  /// Where it came from, in a few words ("Thread upload", "Linked from
  /// example.com"), shown under the title.
  final String origin;

  /// Names the document to pdfrx, which keys its caches by it. Identifiers
  /// only — it can reach logs — so never a URL with a query or a token.
  final String cacheKey;

  final PdfLoad load;

  /// The size the server listed, when it listed one, so a file too large to
  /// view is turned away before it is fetched.
  final int? sizeBytes;

  /// What to say when the server has no such file, where the usual "removed
  /// or renamed" would be wrong: a document can be listed and still have no
  /// PDF to show.
  final ({String heading, String detail})? whenGone;
}

/// How a [PdfViewerSource]'s bytes are obtained.
sealed class PdfLoad {
  const PdfLoad();
}

/// Bytes fetched through the app's own API client — so token refresh, the
/// diagnostics capture and typed errors all apply. The viewer calls [fetch]
/// itself, and again on a retry.
final class PdfLoadBytes extends PdfLoad {
  const PdfLoadBytes(this.fetch);

  final Future<Uint8List> Function() fetch;
}

/// A public document pdfrx downloads itself. Never sent with credentials: a
/// link in an answer can point anywhere. On the web the host must allow the
/// app's origin (CORS), so a load can fail where a browser tab would not.
final class PdfLoadUri extends PdfLoad {
  const PdfLoadUri(this.uri);

  final Uri uri;
}
