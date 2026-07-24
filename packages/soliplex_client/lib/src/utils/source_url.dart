/// Returns [value] as a browser-launchable web URL, or null.
///
/// Accepts only a non-empty `http`/`https` string with a host. A raw
/// `file://`/`s3://` path, a hostless value, or a non-string all yield null —
/// so callers can hand the result straight to a link widget without rendering
/// a dead link.
Uri? launchableWebUrl(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// Extracts a document's clickable origin URL from its free-form metadata.
///
/// Reads the `source_url` key — the backend's viewer-ready URL — and returns it
/// only when it is a launchable web URL (see [launchableWebUrl]). The separate
/// `source_uri` upstream key is deliberately ignored.
Uri? sourceUrlFromMetadata(Map<String, dynamic> metadata) =>
    launchableWebUrl(metadata['source_url']);

/// Whether [metadata] carries a `source_url` that is present and non-empty but
/// not a launchable web URL — a malformed backend value, distinct from an
/// absent one. Lets callers log a backend contract drift while still degrading
/// gracefully to no link.
bool hasMalformedSourceUrl(Map<String, dynamic> metadata) {
  final value = metadata['source_url'];
  return value is String && value.isNotEmpty && launchableWebUrl(value) == null;
}
