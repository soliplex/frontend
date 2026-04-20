import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
// ignore: implementation_imports
import 'package:ag_ui/src/sse/sse_parser.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/resume_policy.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';

/// Streams AG-UI events using the Soliplex HTTP stack directly.
///
/// Replaces [AgUiClient] usage in pure Dart packages. Routes SSE through
/// [HttpTransport] so status code mapping, auth, observability, cancel
/// wrapping, and platform clients apply automatically.
///
/// Implements transparent resume via the SSE `Last-Event-ID` header: when
/// the stream drops mid-run, the client reconnects and yields synthetic
/// [CustomEvent]s (see [ReconnectEvent]) so UI consumers can show a
/// reconnect banner. On exhausted retries, a synthetic [RunErrorEvent] is
/// yielded before returning so downstream state machines see a terminal
/// run without resume-specific branches.
class AgUiStreamClient {
  /// Creates a client that streams AG-UI events via [httpTransport].
  ///
  /// [resumePolicy] configures the SSE reconnect behavior; pass
  /// [ResumePolicy.disabled] to opt out entirely. Per-call overrides are
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
  /// If the stream drops mid-run and [resumePolicy] (or the instance
  /// default) allows it, the client reconnects using `Last-Event-ID` and
  /// emits [ReconnectEvent] custom events on the stream.
  Stream<BaseEvent> runAgent(
    String endpoint,
    SimpleRunAgentInput input, {
    CancelToken? cancelToken,
    ResumePolicy? resumePolicy,
  }) async* {
    final uri = _urlBuilder.build(path: endpoint);
    final body = input.toJson();
    final policy = resumePolicy ?? _resumePolicy;
    const decoder = EventDecoder();

    String? lastEventId;
    var attempt = 0;
    var sawTerminalEvent = false;
    var skippedEventCount = 0;

    while (true) {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        if (lastEventId != null) 'Last-Event-ID': lastEventId,
      };

      final StreamedHttpResponse response;
      try {
        response = await _httpTransport.requestStream(
          'POST',
          uri,
          headers: headers,
          body: body,
          cancelToken: cancelToken,
        );
      } on CancelledException {
        rethrow;
      } on AuthException catch (e) {
        if (lastEventId != null) {
          yield* _finalFailure(
            attempts: attempt,
            message: 'Unauthorized during resume: ${e.message}',
          );
          return;
        }
        rethrow;
      } on NotFoundException catch (e) {
        if (lastEventId != null) {
          yield* _finalFailure(
            attempts: attempt,
            message: 'Not found during resume: ${e.message}',
          );
          return;
        }
        rethrow;
      } on ApiException catch (e) {
        final retryable = e.statusCode >= 500 && e.statusCode < 600;
        if (lastEventId != null && retryable && _canRetry(policy, attempt)) {
          attempt += 1;
          yield _reconnectingEvent(attempt, lastEventId, e.message);
          _logAttempt(attempt, lastEventId, e);
          await Future<void>.delayed(policy.backoffFor(attempt));
          continue;
        }
        if (lastEventId != null) {
          yield* _finalFailure(attempts: attempt, message: e.message);
          return;
        }
        rethrow;
      } on NetworkException catch (e) {
        if (lastEventId != null && _canRetry(policy, attempt)) {
          attempt += 1;
          yield _reconnectingEvent(attempt, lastEventId, e.message);
          _logAttempt(attempt, lastEventId, e);
          await Future<void>.delayed(policy.backoffFor(attempt));
          continue;
        }
        if (lastEventId != null) {
          yield* _finalFailure(attempts: attempt, message: e.message);
          return;
        }
        rethrow;
      }

      final isResumeAttempt = lastEventId != null && attempt > 0;
      var announcedResume = !isResumeAttempt;
      final sseMessages = SseParser().parseBytes(response.body);
      Object? streamError;

      try {
        await for (final message in sseMessages) {
          if (message.id != null && message.id!.isNotEmpty) {
            lastEventId = message.id;
          }
          if (message.data == null || message.data!.isEmpty) continue;

          final decoded = <BaseEvent>[];
          try {
            final jsonData = json.decode(message.data!);
            if (jsonData is Map<String, dynamic>) {
              decoded.add(decoder.decodeJson(jsonData));
            } else if (jsonData is List) {
              for (final item in jsonData) {
                if (item is Map<String, dynamic>) {
                  try {
                    decoded.add(decoder.decodeJson(item));
                  } on DecodingError catch (e) {
                    skippedEventCount++;
                    developer.log(
                      'Skipped undecodable AG-UI event in batch: $e',
                      name: _logName,
                      level: 900,
                    );
                  }
                } else {
                  skippedEventCount++;
                  developer.log(
                    'Skipped non-object item in AG-UI batch: '
                    '${item.runtimeType}',
                    name: _logName,
                    level: 900,
                  );
                }
              }
            }
          } on FormatException catch (e) {
            skippedEventCount++;
            developer.log(
              'Skipped malformed JSON in SSE event: $e',
              name: _logName,
              level: 900,
            );
          } on DecodingError catch (e) {
            skippedEventCount++;
            developer.log(
              'Skipped undecodable AG-UI event: $e',
              name: _logName,
              level: 900,
            );
          }

          if (decoded.isEmpty) continue;
          if (!announcedResume) {
            _logSuccess(attempt, lastEventId);
            yield _reconnectedEvent(attempt);
            announcedResume = true;
            attempt = 0;
          }
          for (final ev in decoded) {
            if (ev is RunFinishedEvent || ev is RunErrorEvent) {
              sawTerminalEvent = true;
            }
            yield ev;
          }
          if (sawTerminalEvent) break;
        }
      } on CancelledException {
        rethrow;
      } on Object catch (e) {
        streamError = e;
        developer.log(
          'SSE stream dropped after id=${lastEventId ?? "<none>"}: $e',
          name: _logName,
          level: 900,
        );
      }

      if (sawTerminalEvent || streamError == null) {
        // Normal completion: terminal event received, or stream closed
        // cleanly (EOF). Only explicit stream errors trigger resume.
        if (skippedEventCount > 0) {
          _onWarning?.call(
            'Skipped $skippedEventCount malformed event(s) during streaming',
          );
        }
        return;
      }

      final errMsg = streamError.toString();

      if (lastEventId == null) {
        // Stream errored before any event id was seen — nothing to
        // resume against.
        developer.log(
          'SSE stream errored before any events: $errMsg',
          name: _logName,
          level: 1000,
        );
        throw NetworkException(
          message: errMsg,
          originalError: streamError,
        );
      }

      if (!_canRetry(policy, attempt)) {
        yield* _finalFailure(attempts: attempt, message: errMsg);
        return;
      }

      attempt += 1;
      yield _reconnectingEvent(attempt, lastEventId, errMsg);
      _logAttempt(attempt, lastEventId, streamError);
      await Future<void>.delayed(policy.backoffFor(attempt));
    }
  }

  /// Closes the underlying transport.
  void close() => _httpTransport.close();

  bool _canRetry(ResumePolicy policy, int attemptsSoFar) =>
      policy.enabled && attemptsSoFar < policy.maxAttempts;

  Stream<BaseEvent> _finalFailure({
    required int attempts,
    required String message,
  }) async* {
    developer.log(
      'Resume failed after $attempts attempt(s): $message',
      name: _logName,
      level: 1000,
    );
    yield CustomEvent(
      name: ReconnectEvent.failed,
      value: <String, dynamic>{
        'attempts': attempts,
        'error': message,
      },
    );
    yield RunErrorEvent(
      message: 'Stream resume failed: $message',
      code: 'stream.resume_failed',
    );
  }

  CustomEvent _reconnectingEvent(int attempt, String? lastId, String? err) =>
      CustomEvent(
        name: ReconnectEvent.reconnecting,
        value: <String, dynamic>{
          'attempt': attempt,
          if (lastId != null) 'lastEventId': lastId,
          if (err != null) 'error': err,
        },
      );

  CustomEvent _reconnectedEvent(int attempt) => CustomEvent(
        name: ReconnectEvent.reconnected,
        value: <String, dynamic>{'attempt': attempt},
      );

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
