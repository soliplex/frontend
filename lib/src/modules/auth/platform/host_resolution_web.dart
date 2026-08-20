/// Web has no resolver API, so the browser's own name resolution cannot be
/// probed separately from the request that failed.
Future<String> describeHostResolution(String host) async =>
    'not available on web';
