import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/log_once.dart';

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

/// Logs [message] at warning level the first time [key] is seen, otherwise
/// silently drops it. A key names whatever the caller wants deduped: a URI for
/// per-source dedupe, a short tag like `'scheme:ftp'` for per-category dedupe,
/// or a message-and-slot tag for one attachment. Dedupe is best-effort; see
/// [isFirstOccurrence]. Pass [logger] so the call site's logger namespace
/// appears in the output; [attributes] are forwarded to the record.
void logFailedSourceOnce(
  Logger logger,
  String message,
  String key, {
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?>? attributes,
}) {
  if (isFirstOccurrence(key)) {
    logger.warning(
      message,
      error: error,
      stackTrace: stackTrace,
      attributes: attributes,
    );
  }
}
