import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
// ignore: implementation_imports
import 'package:ag_ui/src/sse/sse_parser.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
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
/// Routes SSE through [HttpTransport] so status code mapping, auth,
/// observability, cancel wrapping, and platform clients apply
/// automatically.
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
  const AgUiStreamClient({
    required HttpTransport httpTransport,
    required UrlBuilder urlBuilder,
    ResumePolicy resumePolicy = const ResumePolicy(),
  }) : _httpTransport = httpTransport,
       _urlBuilder = urlBuilder,
       _resumePolicy = resumePolicy;

  final HttpTransport _httpTransport;
  final UrlBuilder _urlBuilder;
  final ResumePolicy _resumePolicy;

  static const _logName = 'soliplex_client.agui_stream';

  /// Streams AG-UI decode outcomes for a run.
  ///
  /// Posts [input] to [endpoint] and parses each SSE `data:` line into a
  /// sequence of [DecodeOutcome]s — [DecodedEvent] for items the decoder
  /// accepts and [DecodeFailed] for malformed JSON, unknown event types,
  /// or non-object scalars. The endpoint is relative to the base URL
  /// (e.g. `'rooms/my-room/agui/thread-1/run-1'`).
  ///
  /// Reconnect lifecycle is reported through [onReconnectStatus] (a
  /// [Reconnecting] before each retry, [Reconnected] on the first
  /// outcome of any kind after a successful retry, [ReconnectFailed]
  /// when the retry budget is exhausted). On terminal transport failure
  /// the stream throws [StreamResumeFailedException] whose message
  /// starts with [streamResumeFailedPrefix].
  Stream<DecodeOutcome> runAgent(
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
          onReconnectStatus?.call(ReconnectFailed(attempt: attempt, error: e));
          throw StreamResumeFailedException(
            message:
                '$streamResumeFailedPrefix '
                '${e is SoliplexException ? e.message : e}',
            originalError: e,
          );
        }
        attempt += 1;
        onReconnectStatus?.call(
          Reconnecting(attempt: attempt, lastEventId: lastEventId, error: e),
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

          final outcomes = _decodeOne(message.data!);
          if (outcomes.isEmpty) continue;

          if (!announcedResume) {
            _logSuccess(attempt, lastEventId);
            onReconnectStatus?.call(Reconnected(attempt: attempt));
            announcedResume = true;
            attempt = 0;
          }
          for (final outcome in outcomes) {
            if (outcome is DecodedEvent) {
              final ev = outcome.event;
              if (ev is RunFinishedEvent || ev is RunErrorEvent) {
                sawTerminalEvent = true;
              }
            }
            yield outcome;
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
        return;
      }

      if (lastEventId == null) {
        // No id was ever emitted, so no resume is possible. Rethrow the
        // underlying error directly — wrapping with `streamResumeFailedPrefix`
        // would mislead consumers into treating this as a resume failure.
        Error.throwWithStackTrace(streamError, streamErrorStack ?? .current);
      }

      if (!_canRetry(policy, attempt)) {
        onReconnectStatus?.call(
          ReconnectFailed(attempt: attempt, error: streamError),
        );
        final inner = streamError is SoliplexException
            ? streamError.message
            : streamError.toString();
        throw StreamResumeFailedException(
          message: '$streamResumeFailedPrefix $inner',
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
    ApiException(:final statusCode) => statusCode >= 500 && statusCode < 600,
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
        'Last-Event-ID': ?lastEventId,
      },
      body: body,
      cancelToken: cancelToken,
    );
  }

  /// Decodes one SSE `data:` line into 0..N [DecodeOutcome]s.
  ///
  ///   - Single-event JSON object → one outcome via [decodeMapSafely].
  ///   - JSON array batch → one outcome per item; non-Map items become
  ///     [DecodeFailed] with the raw value (or `null`) as `rawData`.
  ///   - Top-level JSON parse failure → single [DecodeFailed] carrying
  ///     the raw `String`.
  ///   - Top-level scalar (string/number/bool) or JSON `null` → single
  ///     [DecodeFailed] carrying the raw value.
  List<DecodeOutcome> _decodeOne(String data) {
    final outcomes = <DecodeOutcome>[];
    final dynamic jsonData;
    try {
      jsonData = json.decode(data);
    } on FormatException catch (e, st) {
      return [DecodeFailed(e, data, st)];
    }
    if (jsonData is Map<String, dynamic>) {
      outcomes.add(decodeMapSafely(jsonData));
    } else if (jsonData is List) {
      for (final item in jsonData) {
        if (item is Map<String, dynamic>) {
          outcomes.add(decodeMapSafely(item));
        } else {
          outcomes.add(
            DecodeFailed(
              FormatException(
                'Non-object item in AG-UI batch: ${item.runtimeType}',
              ),
              item,
              .current,
            ),
          );
        }
      }
    } else {
      outcomes.add(
        DecodeFailed(
          FormatException(
            'Non-object JSON scalar in SSE event: ${jsonData.runtimeType}',
          ),
          jsonData,
          .current,
        ),
      );
    }
    return outcomes;
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

  void _logAttempt(int attempt, String? lastId, Object? err) {
    developer.log(
      'Resuming SSE with Last-Event-ID=${lastId ?? '<none>'} (attempt $attempt)'
      '${err != null ? ': $err' : ''}',
      name: _logName,
      level: 800,
    );
  }

  void _logSuccess(int attempt, String? lastId) {
    developer.log(
      'Resume succeeded after $attempt attempt(s), '
      'last id=${lastId ?? '<none>'}',
      name: _logName,
      level: 800,
    );
  }
}
