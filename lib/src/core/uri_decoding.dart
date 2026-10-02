/// Whether [uri]'s path and query decode.
///
/// `pathSegments` and `queryParametersAll` decode, and throw a
/// [FormatException] when an escape decodes to invalid UTF-8. A stray `%ZZ`
/// is re-encoded by `Uri.parse` and never throws.
bool isDecodable(Uri uri) {
  try {
    uri.pathSegments;
    uri.queryParametersAll;
    return true;
  } on FormatException {
    return false;
  }
}
