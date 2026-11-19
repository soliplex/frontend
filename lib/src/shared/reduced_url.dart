/// [url] as its scheme, host, port and path, or `<url>` if it does not
/// parse: what a log may keep of a link. The query, fragment and user info
/// are where a link carries a signature or a token, so they go.
String reducedUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '<url>';
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port${uri.path}';
}
