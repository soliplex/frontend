import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:soliplex_logging/src/log_level.dart';
import 'package:soliplex_logging/src/log_record.dart';
import 'package:soliplex_logging/src/log_sink.dart';
import 'package:soliplex_logging/src/sinks/disk_queue.dart';
import 'package:soliplex_logging/src/sinks/memory_sink.dart';

/// Maximum record size in bytes before truncation (64 KB).
const int _maxRecordBytes = 64 * 1024;

/// Default maximum batch payload size in bytes (900 KB).
const int _defaultMaxBatchBytes = 900 * 1024;

/// Callback for error reporting from [BackendLogSink].
typedef SinkErrorCallback = void Function(String message, Object? error);

/// Log sink that persists records to disk and periodically POSTs them
/// as JSON to the Soliplex backend.
///
/// Records are always written to [DiskQueue] first, regardless of auth
/// state. Pre-login logs buffer on disk and ship together once
/// [jwtProvider] returns a non-null token.
class BackendLogSink implements LogSink {
  /// Creates a backend log sink.
  BackendLogSink({
    required this.endpoint,
    required http.Client client,
    required this.installId,
    required this.sessionId,
    required DiskQueue diskQueue,
    this.userId,
    this.memorySink,
    this.maxBreadcrumbs = 20,
    Map<String, Object?> resourceAttributes = const {},
    this.maxBatchBytes = _defaultMaxBatchBytes,
    this.batchSize = 100,
    Duration flushInterval = const Duration(seconds: 30),
    this.networkChecker,
    this.jwtProvider,
    this.flushGate,
    this.maxFlushHoldDuration = const Duration(minutes: 5),
    this.onError,
  }) : _client = client,
       _diskQueue = diskQueue,
       resourceAttributes = Map.unmodifiable(resourceAttributes) {
    _timer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Backend endpoint URL.
  final String endpoint;

  /// Per-install UUID.
  final String installId;

  /// Session UUID (new each app start).
  final String sessionId;

  /// Current user ID (null before auth).
  String? userId;

  /// Current active run thread ID (null when idle).
  String? threadId;

  /// Current active run ID (null when idle).
  String? runId;

  /// Optional memory sink for breadcrumb retrieval on error/fatal.
  final MemorySink? memorySink;

  /// Maximum number of breadcrumb records to attach on error/fatal.
  final int maxBreadcrumbs;

  /// Resource attributes for the payload envelope.
  final Map<String, Object?> resourceAttributes;

  /// Maximum batch payload size in bytes.
  final int maxBatchBytes;

  /// Maximum records per batch.
  final int batchSize;

  /// Returns `true` if the device has network connectivity.
  final bool Function()? networkChecker;

  /// Returns the current JWT or null if not yet authenticated.
  final String? Function()? jwtProvider;

  /// Returns `true` when flushing is allowed.
  ///
  /// When non-null and returning `false`, periodic flushes are held until
  /// the gate opens or [maxFlushHoldDuration] elapses (safety valve).
  /// `flush(force: true)` bypasses this gate entirely.
  final bool Function()? flushGate;

  /// Maximum time to hold flushes when [flushGate] returns `false`.
  final Duration maxFlushHoldDuration;

  /// Callback for error reporting.
  final SinkErrorCallback? onError;

  final http.Client _client;
  final DiskQueue _diskQueue;
  late final Timer _timer;

  final List<Future<void>> _pendingWrites = [];

  bool _closed = false;
  bool _closing = false;
  bool _disabled = false;
  bool _permanentlyDisabled = false;
  DateTime? _gatedSince;

  // C2 fix: guard against concurrent flush calls.
  bool _isFlushing = false;
  Future<void>? _activeFlush;

  int _retryCount = 0;
  int _consecutiveFailures = 0;
  String? _lastJwt;

  /// Backoff state — exposed for testing.
  @visibleForTesting
  DateTime? backoffUntil;

  /// Tracks whether the next HTTP response log should be suppressed
  /// because the preceding request was to the log-shipping endpoint.
  bool _skipNextHttpResponse = false;

  @override
  void write(LogRecord record) {
    if (_closed) return;

    // Don't ship logs about log-shipping itself (avoids feedback loop).
    if (record.loggerName == 'HTTP') {
      if (record.message.contains(endpoint)) {
        _skipNextHttpResponse = true;
        return;
      }
      if (_skipNextHttpResponse && record.message.startsWith('HTTP ')) {
        _skipNextHttpResponse = false;
        return;
      }
      _skipNextHttpResponse = false;
    }

    final json = _recordToJson(record);

    if (record.level >= LogLevel.error && memorySink != null) {
      json['breadcrumbs'] = _collectBreadcrumbs();
    }

    final truncated = _truncateRecord(json);

    if (record.level == LogLevel.fatal) {
      _diskQueue.appendSync(truncated);
    } else {
      final future = _diskQueue.append(truncated);
      _pendingWrites.add(future);
      // Error is handled by Future.wait in _flushImpl; silence the
      // unhandled rejection from this cleanup chain.
      future.whenComplete(() => _pendingWrites.remove(future)).ignore();
    }

    if (record.level >= LogLevel.error) {
      unawaited(flush(force: true));
    }
  }

  @override
  Future<void> flush({bool force = false}) {
    if (_closed) return Future.value();

    // C2 fix: prevent concurrent timer + error-triggered flush from
    // causing duplicate sends.
    if (_isFlushing) return _activeFlush ?? Future.value();
    _isFlushing = true;
    _activeFlush = _runFlush(force: force);
    return _activeFlush!;
  }

  Future<void> _runFlush({bool force = false}) async {
    try {
      await _flushImpl(force: force);
    } on Object catch (e) {
      onError?.call('Flush error: $e', e);
      developer.log('Flush error: $e', name: 'BackendLogSink');
    } finally {
      _isFlushing = false;
      _activeFlush = null;
    }
  }

  Future<void> _flushImpl({bool force = false}) async {
    // Wait for any pending async writes to complete.
    // Errors here should not prevent flushing already-persisted records.
    if (_pendingWrites.isNotEmpty) {
      try {
        await Future.wait(List.of(_pendingWrites));
      } on Object catch (e) {
        onError?.call('Pending write error (proceeding with flush): $e', e);
      }
    }

    // Check JWT availability (pre-auth buffering).
    final jwt = jwtProvider?.call();
    if (jwtProvider != null && jwt == null) return;

    // Re-enable if we got a new JWT after auth failure (401/403).
    // 404 sets _permanentlyDisabled and cannot be recovered.
    if (_disabled && !_permanentlyDisabled && jwt != null && jwt != _lastJwt) {
      _disabled = false;
      _retryCount = 0;
      _consecutiveFailures = 0;
      backoffUntil = null;
    }
    _lastJwt = jwt;

    if (_disabled) return;

    // Respect network check.
    if (networkChecker != null && !networkChecker!()) return;

    // Respect backoff timer (bypassed during close for best-effort drain).
    if (!_closing &&
        backoffUntil != null &&
        DateTime.now().isBefore(backoffUntil!)) {
      return;
    }

    // Respect flush gate (e.g., active run in progress).
    // force: true bypasses the gate (used for error/fatal and run completion).
    if (!force && flushGate != null) {
      if (!flushGate!()) {
        _gatedSince ??= DateTime.now();
        if (DateTime.now().difference(_gatedSince!) < maxFlushHoldDuration) {
          return;
        }
        // Safety valve triggered — reset timer and proceed.
        _gatedSince = null;
      } else {
        _gatedSince = null;
      }
    }

    final records = await _diskQueue.drain(batchSize);
    if (records.isEmpty) return;

    // Apply byte-based cap — returns records to send and total to confirm
    // (includes oversized records that were skipped/discarded).
    final (batch, confirmCount) = _capByBytes(records);

    // Confirm any leading oversized records even if batch is empty.
    if (batch.isEmpty) {
      if (confirmCount > 0) await _diskQueue.confirm(confirmCount);
      return;
    }

    // Coerce resource attributes for safe JSON encoding.
    final safeResource = _safeAttributes(resourceAttributes);

    final payload = jsonEncode({'logs': batch, 'resource': safeResource});

    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
        body: payload,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          await _diskQueue.confirm(confirmCount);
        } on Object catch (e) {
          // Records were sent successfully but local confirm failed.
          // Log and continue — duplicates are preferable to data loss.
          onError?.call('Confirm failed after successful send: $e', e);
        }
        _retryCount = 0;
        _consecutiveFailures = 0;
        backoffUntil = null;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _disabled = true;
        onError?.call(
          'Auth failure (${response.statusCode}), disabling export',
          null,
        );
      } else if (response.statusCode == 404) {
        _disabled = true;
        _permanentlyDisabled = true;
        onError?.call(
          'Endpoint not found (404), disabling export permanently',
          null,
        );
      } else if (response.statusCode == 429 || response.statusCode >= 500) {
        // 429, 5xx — retry with backoff.
        await _handleRetryableError(confirmCount);
      } else {
        // Other 4xx (400, 413, 422, etc.) — non-retryable data error.
        // Discard batch immediately to prevent blocking the queue.
        try {
          await _diskQueue.confirm(confirmCount);
        } on Object catch (e) {
          onError?.call('Confirm failed after batch rejection: $e', e);
        }
        onError?.call(
          'Batch rejected by server (${response.statusCode}), discarding',
          null,
        );
      }
    } on Object catch (e) {
      // Network error — retry with backoff.
      await _handleRetryableError(confirmCount);
      onError?.call('Network error: $e', e);
      developer.log('Flush failed: $e', name: 'BackendLogSink');
    }
  }

  /// Discards all pending (unsent) log records from the disk queue.
  Future<void> clearPending() => _diskQueue.clear();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closing = true;
    _timer.cancel();
    // Await any in-flight flush before the final one.
    await _activeFlush;
    // Run one final flush directly (bypasses _closed and backoff guards).
    await _runFlush();
    _closing = false;
    await _diskQueue.close();
  }

  Future<void> _handleRetryableError(int batchLength) async {
    _consecutiveFailures++;
    _retryCount++;

    // Poison pill: discard batch after 50 consecutive failures to prevent
    // a permanently stuck queue. At ~60s max backoff this covers ~50 minutes
    // of sustained outage before dropping a batch.
    if (_consecutiveFailures >= 50) {
      await _diskQueue.confirm(batchLength);
      _consecutiveFailures = 0;
      _retryCount = 0;
      onError?.call(
        'Batch discarded after 50 consecutive failures (poison pill)',
        null,
      );
      return;
    }

    // Exponential backoff with jitter: base 1s, 2s, 4s, ... max 60s,
    // plus random jitter up to 1s to decorrelate retries.
    final baseSeconds = min(pow(2, _retryCount - 1).toInt(), 60);
    final jitterMs = Random().nextInt(1000);
    backoffUntil = DateTime.now().add(
      Duration(seconds: baseSeconds, milliseconds: jitterMs),
    );
  }

  Map<String, Object?> _recordToJson(LogRecord record) {
    return {
      'timestamp': record.timestamp.toUtc().toIso8601String(),
      'level': record.level.name,
      'logger': record.loggerName,
      'message': record.message,
      'attributes': _safeAttributes(record.attributes),
      'error': record.error?.toString(),
      'stack_trace': record.stackTrace?.toString(),
      'span_id': record.spanId,
      'trace_id': record.traceId,
      'install_id': installId,
      'session_id': sessionId,
      'user_id': userId,
      'active_run':
          threadId != null ? {'thread_id': threadId, 'run_id': runId} : null,
    };
  }

  /// Coerces non-JSON-primitive attribute values to String.
  Map<String, Object?> _safeAttributes(Map<String, Object?> attributes) {
    if (attributes.isEmpty) return const {};
    final result = <String, Object?>{};
    for (final entry in attributes.entries) {
      result[entry.key] = _coerceValue(entry.value);
    }
    return result;
  }

  Object? _coerceValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) {
      return value.map(_coerceValue).toList();
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _coerceValue(v)));
    }
    return value.toString();
  }

  /// Truncates record fields to stay under the 64 KB limit.
  Map<String, Object?> _truncateRecord(Map<String, Object?> json) {
    // Use byte-accurate size check (UTF-8 encoding, not UTF-16 .length).
    final encoded = utf8.encode(jsonEncode(json));
    if (encoded.length <= _maxRecordBytes) return json;

    final result = Map<String, Object?>.of(json);

    for (final key in const ['message', 'stackTrace', 'error']) {
      final value = result[key];
      if (value is String && value.length > 1024) {
        result[key] = _utf8SafeTruncate(value, 1024);
      }
      if (utf8.encode(jsonEncode(result)).length <= _maxRecordBytes) {
        return result;
      }
    }

    if (result['attributes'] is Map) {
      result['attributes'] = const <String, Object?>{};
    }

    // Final safety net: if still oversized, return a minimal placeholder.
    if (utf8.encode(jsonEncode(result)).length > _maxRecordBytes) {
      return {
        'timestamp': result['timestamp'],
        'level': result['level'],
        'logger': result['logger'],
        'message': '[record exceeded ${_maxRecordBytes}B after truncation]',
        'installId': result['installId'],
        'sessionId': result['sessionId'],
        'userId': result['userId'],
      };
    }

    return result;
  }

  /// Truncates a string at a UTF-8 safe boundary.
  String _utf8SafeTruncate(String input, int maxBytes) {
    final encoded = utf8.encode(input);
    if (encoded.length <= maxBytes) return input;

    var end = maxBytes;
    // If we landed in the middle of a multi-byte sequence, backtrack to
    // the lead byte to find the sequence start.
    while (end > 0 && (encoded[end] & 0xC0) == 0x80) {
      end--;
    }
    // Now encoded[end] is either ASCII or a lead byte.
    // If it's a lead byte, check whether the full sequence fits.
    if (end < encoded.length && encoded[end] >= 0xC0) {
      int seqLen;
      final lead = encoded[end];
      if ((lead & 0xE0) == 0xC0) {
        seqLen = 2;
      } else if ((lead & 0xF0) == 0xE0) {
        seqLen = 3;
      } else {
        seqLen = 4;
      }
      // Keep the character only if the entire sequence fits within maxBytes.
      if (end + seqLen <= maxBytes) {
        end += seqLen;
      }
    }
    return '${utf8.decode(encoded.sublist(0, end))}…[truncated]';
  }

  /// Reads the last [maxBreadcrumbs] records from [memorySink].
  List<Map<String, Object?>> _collectBreadcrumbs() {
    if (maxBreadcrumbs <= 0) return [];
    final records = memorySink!.records;
    final start =
        records.length > maxBreadcrumbs ? records.length - maxBreadcrumbs : 0;
    return [
      for (var i = start; i < records.length; i++)
        _breadcrumbFromRecord(records[i]),
    ];
  }

  Map<String, Object?> _breadcrumbFromRecord(LogRecord record) {
    return {
      'timestamp': record.timestamp.toUtc().toIso8601String(),
      'level': record.level.name,
      'logger': record.loggerName,
      'message': record.message,
      'category': deriveBreadcrumbCategory(record),
    };
  }

  /// Caps records by byte size.
  ///
  /// Returns a tuple of (batch to send, total records to confirm).
  /// The confirm count includes oversized records that were discarded.
  (List<Map<String, Object?>>, int) _capByBytes(
    List<Map<String, Object?>> records,
  ) {
    final result = <Map<String, Object?>>[];
    var totalBytes = 0;
    var scanned = 0;
    final envelopeOverhead =
        utf8
            .encode(
              jsonEncode({
                'logs': <Object>[],
                'resource': _safeAttributes(resourceAttributes),
              }),
            )
            .length;
    totalBytes += envelopeOverhead;

    for (final record in records) {
      final recordBytes = utf8.encode(jsonEncode(record)).length;

      // Discard any individual record that exceeds the batch limit,
      // regardless of its position, to prevent head-of-line blocking.
      if (recordBytes > maxBatchBytes - envelopeOverhead) {
        scanned++;
        onError?.call(
          'Log record dropped; size ${recordBytes}B exceeds max batch '
          'size ${maxBatchBytes}B',
          null,
        );
        continue;
      }

      // Account for the comma separator between JSON array elements.
      final separatorBytes = result.isEmpty ? 0 : 1;
      if (totalBytes + separatorBytes + recordBytes > maxBatchBytes) break;
      result.add(record);
      totalBytes += separatorBytes + recordBytes;
      scanned++;
    }
    return (result, scanned);
  }
}

/// Logger name prefixes that map to breadcrumb categories.
const _loggerCategoryPrefixes = {
  'Router': 'ui',
  'Navigation': 'ui',
  'UI': 'ui',
  'Http': 'network',
  'Network': 'network',
  'Connectivity': 'network',
  'Lifecycle': 'system',
  'Permission': 'system',
  'Auth': 'user',
  'Login': 'user',
  'User': 'user',
};

/// Derives a breadcrumb category from a [LogRecord].
///
/// If the record has an explicit `breadcrumb_category` attribute, that
/// value is used. Otherwise, the category is inferred from the
/// [LogRecord.loggerName] prefix (e.g. `Router.Home` -> `ui`).
/// Falls back to `system` if no match is found.
String deriveBreadcrumbCategory(LogRecord record) {
  final explicit = record.attributes['breadcrumb_category'];
  if (explicit is String) return explicit;

  final name = record.loggerName;
  for (final entry in _loggerCategoryPrefixes.entries) {
    if (name == entry.key || name.startsWith('${entry.key}.')) {
      return entry.value;
    }
  }
  return 'system';
}
