import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
// ignore: implementation_imports
import 'package:ag_ui/src/sse/sse_parser.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/resume_policy.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';

/// Diagnostic prefix used inside
/// [StreamResumeFailedException.message]. Kept for log/test
/// readability; consumers should match on [StreamResumeFailedException]
/// rather than this string.
const String streamResumeFailedPrefix = 'Stream resume failed:';

/// Streams AG-UI events using the Soliplex HTTP stack directly.
///
/// Replaces [AgUiClient] usage in pure Dart packages. Routes SSE through
/// [HttpTransport] so status code mapping, auth, observability, cancel
/// wrapping, and platform clients apply automatically.
///
/// Implements transparent resume via the SSE `Last-Event-ID` header:
/// when the stream drops mid-run, the client reconnects and reports
/// progress through an optional [ReconnectStatus] callback. On
/// exhausted retries — or any retryable failure during a resume that
/// the policy can no longer cover — `runAgent` throws [NetworkException]
/// whose message starts with [streamResumeFailedPrefix].
class AgUiStreamClient {
  /// Creates a client that streams AG-UI events via [httpTransport].
  ///
  /// [resumePolicy] configures the SSE reconnect behavior; pass
  /// [ResumePolicy.noRetry] to opt out entirely. Per-call overrides are
  /// accepted on [runAgent].
  AgUiStreamClient({
    required HttpTransport httpTransport,
    required UrlBuilder urlBuilder,
    void Function(String message)? onWarning,
    ResumePolicy resumePolicy = const ResumePolicy(),
  })  : _httpTransport = httpTransport,
        _urlBuilder = urlBuilder,
        _onWarning = onWarning,
        _resumePolicy = resumePolicy;

  final HttpTransport _httpTransport;
  final UrlBuilder _urlBuilder;
  final void Function(String message)? _onWarning;
  final ResumePolicy _resumePolicy;

  static const _logName = 'soliplex_client.agui_stream';

  /// Streams AG-UI events for a run.
  ///
  /// Posts [input] to [endpoint] and parses the SSE response into typed
  /// [BaseEvent]s. The endpoint is relative to the base URL (e.g.
  /// `'rooms/my-room/agui/thread-1/run-1'`).
  ///
  /// Reconnect lifecycle is reported through [onReconnectStatus] (a
  /// [Reconnecting] before each retry, [Reconnected] on the first
  /// decoded event after a successful retry, [ReconnectFailed] when the
  /// retry budget is exhausted). On terminal transport failure the
  /// stream throws [NetworkException] whose message starts with
  /// [streamResumeFailedPrefix].
  Stream<BaseEvent> runAgent(
    String endpoint,
    SimpleRunAgentInput input, {
    CancelToken? cancelToken,
    ResumePolicy? resumePolicy,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async* {
    final policy = resumePolicy ?? _resumePolicy;
    final uri = _urlBuilder.build(path: endpoint);
    final body = input.toJson();
    String? lastEventId;
    var attempt = 0;
    var skippedEventCount = 0;

    while (true) {
      final isResumeRequest = lastEventId != null;
      final StreamedHttpResponse response;
      try {
        response = await _attempt(uri, body, lastEventId, cancelToken);
      } on CancelledException {
        rethrow;
      } on Object catch (e) {
        if (!isResumeRequest) rethrow;
        if (!_retryable(e) || !_canRetry(policy, attempt)) {
          onReconnectStatus?.call(
            ReconnectFailed(attempt: attempt, error: e),
          );
          _flushSkippedWarning(skippedEventCount);
          throw StreamResumeFailedException(
            message: _resumeFailureMessage(e, skippedEventCount),
            originalError: e,
          );
        }
        attempt += 1;
        onReconnectStatus?.call(
          Reconnecting(
            attempt: attempt,
            lastEventId: lastEventId,
            error: e,
          ),
        );
        _logAttempt(attempt, lastEventId, e);
        await raceBackoff(policy.backoffFor(attempt), cancelToken);
        continue;
      }

      var sawTerminalEvent = false;
      var announcedResume = !isResumeRequest;
      Object? streamError;
      StackTrace? streamErrorStack;

      try {
        // Construct the parser inside the try so a synchronous throw
        // from `parseBytes` is caught by the same handler as mid-stream
        // errors.
        final messages = SseParser().parseBytes(response.body);
        await for (final message in messages) {
          if (message.id != null && message.id!.isNotEmpty) {
            lastEventId = message.id;
          }
          if (message.data == null || message.data!.isEmpty) continue;

          final result = _decodeOne(message.data!);
          skippedEventCount += result.skipped;
          if (result.events.isEmpty) continue;

          if (!announcedResume) {
            _logSuccess(attempt, lastEventId);
            onReconnectStatus?.call(Reconnected(attempt: attempt));
            announcedResume = true;
            attempt = 0;
          }
          for (final ev in result.events) {
            if (ev is RunFinishedEvent || ev is RunErrorEvent) {
              sawTerminalEvent = true;
            }
            yield ev;
          }
          if (sawTerminalEvent) break;
        }
      } on CancelledException {
        rethrow;
      } on Object catch (e, st) {
        streamError = e;
        streamErrorStack = st;
        developer.log(
          'SSE stream dropped after id=${lastEventId ?? "<none>"}: $e',
          name: _logName,
          level: 900,
        );
      }

      if (sawTerminalEvent || streamError == null) {
        _flushSkippedWarning(skippedEventCount);
        return;
      }

      if (lastEventId == null) {
        // No id was ever emitted, so no resume is possible. Rethrow the
        // underlying error directly — wrapping with `streamResumeFailedPrefix`
        // would mislead consumers into treating this as a resume failure.
        _flushSkippedWarning(skippedEventCount);
        Error.throwWithStackTrace(
          streamError,
          streamErrorStack ?? StackTrace.current,
        );
      }

      if (!_canRetry(policy, attempt)) {
        onReconnectStatus?.call(
          ReconnectFailed(attempt: attempt, error: streamError),
        );
        _flushSkippedWarning(skippedEventCount);
        throw StreamResumeFailedException(
          message: _resumeFailureMessage(streamError, skippedEventCount),
          originalError: streamError,
        );
      }

      attempt += 1;
      onReconnectStatus?.call(
        Reconnecting(
          attempt: attempt,
          lastEventId: lastEventId,
          error: streamError,
        ),
      );
      _logAttempt(attempt, lastEventId, streamError);
      await raceBackoff(policy.backoffFor(attempt), cancelToken);
    }
  }

  /// Closes the underlying transport. Subsequent [runAgent] calls fail.
  void close() => _httpTransport.close();

  bool _retryable(Object e) => switch (e) {
        CancelledException() => false,
        AuthException() || NotFoundException() => false,
        ApiException(:final statusCode) =>
          statusCode >= 500 && statusCode < 600,
        NetworkException() => true,
        _ => false,
      };

  bool _canRetry(ResumePolicy policy, int attemptsSoFar) =>
      policy.enabled && attemptsSoFar < policy.maxAttempts;

  Future<StreamedHttpResponse> _attempt(
    Uri uri,
    Object body,
    String? lastEventId,
    CancelToken? cancelToken,
  ) {
    return _httpTransport.requestStream(
      'POST',
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        if (lastEventId != null) 'Last-Event-ID': lastEventId,
      },
      body: body,
      cancelToken: cancelToken,
    );
  }

  /// Decodes one SSE `data:` line into 0..N typed [BaseEvent]s. Returns
  /// the decoded events and the skip count from this single line. The
  /// caller accumulates skipped counts across the run.
  ///
  ///   - Single-event JSON object → `(events: [decoded], skipped: 0)`.
  ///   - JSON array batch → `(events: [decoded...], skipped: N)`
  ///     where N counts items that fail to decode or are not JSON
  ///     objects.
  ///   - Malformed JSON or any top-level decode failure
  ///     → `(events: [], skipped: 1)`.
  ({List<BaseEvent> events, int skipped}) _decodeOne(String data) {
    const decoder = EventDecoder();
    final decoded = <BaseEvent>[];
    var skipped = 0;
    try {
      final jsonData = json.decode(data);
      if (jsonData is Map<String, dynamic>) {
        decoded.add(decoder.decodeJson(jsonData));
      } else if (jsonData is List) {
        for (final item in jsonData) {
          if (item is Map<String, dynamic>) {
            try {
              decoded.add(decoder.decodeJson(item));
            } on DecodingError catch (e) {
              skipped++;
              developer.log(
                'Skipped undecodable AG-UI event in batch: $e',
                name: _logName,
                level: 900,
              );
            }
          } else {
            skipped++;
            developer.log(
              'Skipped non-object item in AG-UI batch: ${item.runtimeType}',
              name: _logName,
              level: 900,
            );
          }
        }
      } else {
        // JSON scalar (string/number/bool/null) at the top level —
        // not a valid AG-UI payload. Counted so the skipped-event
        // diagnostic surfaces server-side anomalies of this shape.
        skipped++;
        developer.log(
          'Skipped non-object JSON scalar in SSE event: '
          '${jsonData.runtimeType}',
          name: _logName,
          level: 900,
        );
      }
    } on FormatException catch (e) {
      skipped++;
      developer.log(
        'Skipped malformed JSON in SSE event: $e',
        name: _logName,
        level: 900,
      );
    } on DecodingError catch (e) {
      skipped++;
      developer.log(
        'Skipped undecodable AG-UI event: $e',
        name: _logName,
        level: 900,
      );
    }
    return (events: decoded, skipped: skipped);
  }

  /// Cancel-aware backoff: races a delay against the cancel token so a
  /// cancel during a long backoff resolves in microseconds rather than
  /// after the full delay. Throws [CancelledException] when the token
  /// fires before the delay elapses.
  ///
  /// Owns its underlying [Timer] so cancel can stop it directly,
  /// avoiding stranded timers that would otherwise expire on their own.
  @visibleForTesting
  static Future<void> raceBackoff(Duration d, CancelToken? token) async {
    if (token == null) {
      await Future<void>.delayed(d);
      return;
    }
    final completer = Completer<void>();
    final timer = Timer(d, () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(
      token.whenCancelled.then((_) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }),
    );
    await completer.future;
    timer.cancel();
    token.throwIfCancelled();
  }

  /// Logs and forwards a non-zero skipped-event count via [_onWarning].
  /// Caller invokes once per terminal exit from `runAgent`.
  void _flushSkippedWarning(int count) {
    if (count == 0) return;
    final noun = count == 1 ? 'event' : 'events';
    final message = 'Skipped $count malformed $noun during streaming';
    developer.log(message, name: _logName, level: 900);
    _onWarning?.call(message);
  }

  String _resumeFailureMessage(Object error, int skippedEventCount) {
    final inner = error is SoliplexException ? error.message : error.toString();
    if (skippedEventCount == 0) return '$streamResumeFailedPrefix $inner';
    final noun = skippedEventCount == 1 ? 'event' : 'events';
    return '$streamResumeFailedPrefix $inner '
        '(skipped $skippedEventCount malformed $noun)';
  }

  void _logAttempt(int attempt, String? lastId, Object? err) {
    developer.log(
      'Resuming SSE with Last-Event-ID=$lastId (attempt $attempt)'
      '${err != null ? ': $err' : ''}',
      name: _logName,
      level: 800,
    );
  }

  void _logSuccess(int attempt, String? lastId) {
    developer.log(
      'Resume succeeded after $attempt attempt(s), last id=$lastId',
      name: _logName,
      level: 800,
    );
  }
}
