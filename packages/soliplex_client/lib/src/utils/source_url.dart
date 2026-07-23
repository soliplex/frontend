/// Extracts a document's clickable origin URL from its free-form metadata.
///
/// Reads the `source_url` key and returns it only when it is a non-empty web
/// URL — `http`/`https` with a host. A raw `file://` path, the separate
/// `source_uri` upstream key, a hostless value, or a non-string all yield null.
/// `source_url` is the backend's viewer-ready URL; rejecting a non-web scheme
/// guards its contract so no blank-text link renders.
Uri? sourceUrlFromMetadata(Map<String, dynamic> metadata) {
  final value = metadata['source_url'];
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}
