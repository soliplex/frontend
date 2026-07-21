/// Display text for a browser URL: scheme (and any query/fragment) removed so
/// the origin reads as `host/path` without `https://` noise.
String browserUrlDisplay(Uri url) => '${url.host}${url.path}';

/// The clickable origin URL a document carries under the backend `source_url`
/// metadata key, or null when absent/unusable.
///
/// `source_url` is the transformed, viewer-ready URL (e.g. `…/view`); the raw
/// `source_uri` upstream path is intentionally ignored. Only `http`/`https`
/// values are accepted — a bare `file://` path is not a browser URL.
Uri? sourceUrlFromMetadata(Map<String, dynamic> metadata) {
  final value = metadata['source_url'];
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}
