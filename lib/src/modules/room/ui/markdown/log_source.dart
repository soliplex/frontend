import 'package:soliplex_logging/soliplex_logging.dart';

/// Returns a triage-friendly representation of a markdown image source URI
/// for logging. For `data:` URIs the payload is replaced with a length
/// marker (the bytes can be PII for image scans or text content); for
/// everything else the URI is truncated to [max] characters with the
/// original length appended.
String safeSourceForLog(String src, {int max = 120}) {
  if (src.startsWith('data:')) {
    final commaIdx = src.indexOf(',');
    if (commaIdx < 0) return 'data:<no payload separator>';
    final header = src.substring(0, commaIdx);
    final payloadLen = src.length - commaIdx - 1;
    return '$header,<$payloadLen chars redacted>';
  }
  return src.length <= max
      ? src
      : '${src.substring(0, max)}…(${src.length} chars)';
}

/// Hashes of source keys already logged once at warning level. Flutter's
/// `errorBuilder` is invoked on every rebuild while the failed image is
/// mounted; without dedupe a single broken image in chat history can flood the
/// log sink. Shared across all callers of [logFailedSourceOnce] so a key that
/// fails in several of those paths logs once total. Only each key's hash is
/// retained, so a `data:` URI's (potentially multi-megabyte) base64 payload is
/// not held for the process lifetime.
final _loggedSources = <int>{};

/// Logs [message] at warning level the first time [key] is seen, otherwise
/// silently drops it. Keys are URIs for per-source dedupe, or short tags like
/// `'scheme:ftp'` for per-category dedupe. Dedupe is best-effort: keyed on
/// [key]'s hash so large payloads are never retained, at the cost that two keys
/// whose hashes collide are treated as one — an acceptable, rare miss for log
/// dedupe. Pass [logger] so the call site's logger namespace appears in the
/// output.
void logFailedSourceOnce(
  Logger logger,
  String message,
  String key, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (_loggedSources.add(key.hashCode)) {
    logger.warning(message, error: error, stackTrace: stackTrace);
  }
}
