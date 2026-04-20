import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/agui_stream_client.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/resume_policy.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

/// Encodes a list of SSE events into a byte stream.
///
/// Each event is a JSON object wrapped in `data: ...\n\n`.
Stream<List<int>> sseByteStream(List<Map<String, dynamic>> events) {
  final buffer = StringBuffer();
  for (final event in events) {
    buffer
      ..writeln('data: ${json.encode(event)}')
      ..writeln();
  }
  return Stream.value(utf8.encode(buffer.toString()));
}

/// Encodes (id, event) pairs into a byte stream with explicit `id:` fields.
Stream<List<int>> sseByteStreamWithIds(
  List<(String, Map<String, dynamic>)> events,
) {
  final buffer = StringBuffer();
  for (final (id, event) in events) {
    buffer
      ..writeln('id: $id')
      ..writeln('data: ${json.encode(event)}')
      ..writeln();
  }
  return Stream.value(utf8.encode(buffer.toString()));
}

/// Emits bytes for [events] with ids, then errors with [error], to
/// simulate a mid-stream connection drop.
Stream<List<int>> sseByteStreamThenError(
  List<(String, Map<String, dynamic>)> events,
  Object error,
) {
  final controller = StreamController<List<int>>();
  Future<void>(() async {
    final buffer = StringBuffer();
    for (final (id, event) in events) {
      buffer
        ..writeln('id: $id')
        ..writeln('data: ${json.encode(event)}')
        ..writeln();
    }
    controller.add(utf8.encode(buffer.toString()));
    // Yield so the parser can process before we inject the error.
    await Future<void>.delayed(Duration.zero);
    controller.addError(error);
    await controller.close();
  });
  return controller.stream;
}

/// Fast policy for unit tests — minimal backoff, no jitter.
const _fastPolicy = ResumePolicy(
  initialBackoff: Duration(milliseconds: 1),
  maxBackoff: Duration(milliseconds: 2),
  jitter: 0,
);

void main() {
  late MockHttpTransport mockTransport;
  late AgUiStreamClient client;

  const baseUrl = 'https://api.test/v1';

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    mockTransport = MockHttpTransport();
    client = AgUiStreamClient(
      httpTransport: mockTransport,
      urlBuilder: UrlBuilder(baseUrl),
    );
    when(() => mockTransport.close()).thenReturn(null);
  });

  tearDown(() {
    client.close();
    reset(mockTransport);
  });

  group('AgUiStreamClient', () {
    const endpoint = 'rooms/test-room/agui/thread-1/run-1';
    const input = SimpleRunAgentInput();

    group('runAgent', () {
      test('passes CancelToken to requestStream', () async {
        final token = CancelToken();

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: sseByteStream([])),
        );

        await client.runAgent(endpoint, input, cancelToken: token).toList();

        final captured = verify(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: captureAny(named: 'cancelToken'),
          ),
        ).captured;

        expect(captured.single, same(token));
      });

      test('builds correct URI from endpoint', () async {
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: sseByteStream([])),
        );

        await client.runAgent(endpoint, input).toList();

        final captured = verify(
          () => mockTransport.requestStream(
            'POST',
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).captured;

        final uri = captured.single as Uri;
        expect(uri.toString(), '$baseUrl/$endpoint');
      });

      test('sends correct headers', () async {
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async =>
              StreamedHttpResponse(statusCode: 200, body: sseByteStream([])),
        );

        await client.runAgent(endpoint, input).toList();

        final captured = verify(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).captured;

        final headers = captured.single as Map<String, String>;
        expect(headers['Content-Type'], 'application/json');
        expect(headers['Accept'], 'text/event-stream');
      });

      test('parses single SSE events into BaseEvents', () async {
        final events = [
          {'type': 'RUN_STARTED', 'threadId': 'thread-1', 'runId': 'run-1'},
          {
            'type': 'TEXT_MESSAGE_START',
            'messageId': 'msg-1',
            'role': 'assistant',
          },
          {
            'type': 'TEXT_MESSAGE_CONTENT',
            'messageId': 'msg-1',
            'delta': 'Hello',
          },
          {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
          {'type': 'RUN_FINISHED', 'threadId': 'thread-1', 'runId': 'run-1'},
        ];

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStream(events),
          ),
        );

        final result = await client.runAgent(endpoint, input).toList();

        expect(result, hasLength(5));
        expect(result[0], isA<RunStartedEvent>());
        expect(result[1], isA<TextMessageStartEvent>());
        expect(result[2], isA<TextMessageContentEvent>());
        expect((result[2] as TextMessageContentEvent).delta, 'Hello');
        expect(result[3], isA<TextMessageEndEvent>());
        expect(result[4], isA<RunFinishedEvent>());
      });

      test('parses batched SSE events (JSON array)', () async {
        final batch = [
          {'type': 'RUN_STARTED', 'threadId': 'thread-1', 'runId': 'run-1'},
          {'type': 'RUN_FINISHED', 'threadId': 'thread-1', 'runId': 'run-1'},
        ];

        // Encode the array as a single SSE data line.
        final sseBody = StringBuffer()
          ..writeln('data: ${json.encode(batch)}')
          ..writeln();

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: Stream.value(utf8.encode(sseBody.toString())),
          ),
        );

        final result = await client.runAgent(endpoint, input).toList();

        expect(result, hasLength(2));
        expect(result[0], isA<RunStartedEvent>());
        expect(result[1], isA<RunFinishedEvent>());
      });

      test('skips SSE messages with empty data', () async {
        // Build a stream with one empty-data message and one real event.
        final sseBody = StringBuffer()
          ..writeln('data: ')
          ..writeln()
          ..writeln(
            'data: ${json.encode({
                  'type': 'RUN_STARTED',
                  'threadId': 't-1',
                  'runId': 'r-1',
                })}',
          )
          ..writeln();

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: Stream.value(utf8.encode(sseBody.toString())),
          ),
        );

        final result = await client.runAgent(endpoint, input).toList();

        expect(result, hasLength(1));
        expect(result[0], isA<RunStartedEvent>());
      });
    });

    group('error handling', () {
      test('propagates AuthException from transport on 401', () async {
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(
          const AuthException(message: 'Unauthorized', statusCode: 401),
        );

        expect(
          () => client.runAgent(endpoint, input).toList(),
          throwsA(isA<AuthException>()),
        );
      });

      test('propagates ApiException from transport on 500', () async {
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(
          const ApiException(message: 'Internal Server Error', statusCode: 500),
        );

        expect(
          () => client.runAgent(endpoint, input).toList(),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
          ),
        );
      });

      test('skips unknown event types and continues streaming', () async {
        final events = [
          {'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'r-1'},
          {'type': 'TOTALLY_UNKNOWN_EVENT', 'foo': 'bar'},
          {'type': 'RUN_FINISHED', 'threadId': 't-1', 'runId': 'r-1'},
        ];

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStream(events),
          ),
        );

        final result = await client.runAgent(endpoint, input).toList();

        expect(result, hasLength(2));
        expect(result[0], isA<RunStartedEvent>());
        expect(result[1], isA<RunFinishedEvent>());
      });

      test('skips bad event in batch without dropping remaining', () async {
        final batch = [
          {'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'r-1'},
          {'type': 'TOTALLY_UNKNOWN_EVENT', 'foo': 'bar'},
          {'type': 'RUN_FINISHED', 'threadId': 't-1', 'runId': 'r-1'},
        ];

        final sseBody = StringBuffer()
          ..writeln('data: ${json.encode(batch)}')
          ..writeln();

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: Stream.value(utf8.encode(sseBody.toString())),
          ),
        );

        final result = await client.runAgent(endpoint, input).toList();

        expect(result, hasLength(2));
        expect(result[0], isA<RunStartedEvent>());
        expect(result[1], isA<RunFinishedEvent>());
      });

      test('skips malformed JSON and continues streaming', () async {
        final sseBody = StringBuffer()
          ..writeln('data: not valid json at all')
          ..writeln()
          ..writeln(
            'data: ${json.encode({
                  'type': 'RUN_STARTED',
                  'threadId': 't-1',
                  'runId': 'r-1',
                })}',
          )
          ..writeln();

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: Stream.value(utf8.encode(sseBody.toString())),
          ),
        );

        final result = await client.runAgent(endpoint, input).toList();

        expect(result, hasLength(1));
        expect(result[0], isA<RunStartedEvent>());
      });

      test('calls onWarning with count when events are skipped', () async {
        final warnings = <String>[];
        final clientWithWarning = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          onWarning: warnings.add,
        );
        addTearDown(clientWithWarning.close);

        final events = [
          {'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'r-1'},
          {'type': 'TOTALLY_UNKNOWN_EVENT', 'foo': 'bar'},
          {'type': 'RUN_FINISHED', 'threadId': 't-1', 'runId': 'r-1'},
        ];

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStream(events),
          ),
        );

        final result =
            await clientWithWarning.runAgent(endpoint, input).toList();

        expect(result, hasLength(2));
        expect(warnings, hasLength(1));
        expect(warnings[0], contains('1 malformed event'));
      });

      test('propagates CancelledException from transport', () async {
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(const CancelledException());

        expect(
          () => client.runAgent(endpoint, input).toList(),
          throwsA(isA<CancelledException>()),
        );
      });
    });

    group('resume', () {
      test('resumes after mid-stream drop using Last-Event-ID', () async {
        final resumeClient = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          resumePolicy: _fastPolicy,
        );
        addTearDown(resumeClient.close);

        // First call: 2 events with ids, then a connection drop.
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStreamThenError(
              [
                (
                  'run-1:0',
                  {
                    'type': 'RUN_STARTED',
                    'threadId': 't-1',
                    'runId': 'run-1',
                  },
                ),
                (
                  'run-1:1',
                  {
                    'type': 'TEXT_MESSAGE_START',
                    'messageId': 'm-1',
                    'role': 'assistant',
                  },
                ),
              ],
              const NetworkException(message: 'connection reset'),
            ),
          ),
        );

        final events = <BaseEvent>[];
        final run = resumeClient.runAgent(endpoint, input);
        final iterator = StreamIterator<BaseEvent>(run);

        // Drain the first two real events + the reconnecting notice.
        while (await iterator.moveNext()) {
          events.add(iterator.current);
          if (events.whereType<CustomEvent>().any(
                (e) => e.name == 'stream.reconnecting',
              )) {
            break;
          }
        }

        // Now swap the stub to return events 2..3 + RUN_FINISHED.
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStreamWithIds([
              (
                'run-1:2',
                {
                  'type': 'TEXT_MESSAGE_CONTENT',
                  'messageId': 'm-1',
                  'delta': 'hi',
                },
              ),
              (
                'run-1:3',
                {'type': 'TEXT_MESSAGE_END', 'messageId': 'm-1'},
              ),
              (
                'run-1:4',
                {
                  'type': 'RUN_FINISHED',
                  'threadId': 't-1',
                  'runId': 'run-1',
                },
              ),
            ]),
          ),
        );

        while (await iterator.moveNext()) {
          events.add(iterator.current);
        }

        // Verify second call included Last-Event-ID.
        final captured = verify(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).captured;
        expect(captured, hasLength(2));
        final firstHeaders = captured[0] as Map<String, String>;
        final secondHeaders = captured[1] as Map<String, String>;
        expect(firstHeaders.containsKey('Last-Event-ID'), isFalse);
        expect(secondHeaders['Last-Event-ID'], 'run-1:1');

        // Verify reconnect lifecycle events were emitted.
        final customEvents = events.whereType<CustomEvent>().toList();
        expect(
          customEvents.map((e) => e.name),
          containsAllInOrder(['stream.reconnecting', 'stream.reconnected']),
        );
        final reconnecting = customEvents.firstWhere(
          (e) => e.name == 'stream.reconnecting',
        );
        expect((reconnecting.value as Map)['lastEventId'], 'run-1:1');
        expect((reconnecting.value as Map)['attempt'], 1);

        // Verify run events were delivered end-to-end.
        expect(events.whereType<RunStartedEvent>(), hasLength(1));
        expect(events.whereType<TextMessageContentEvent>(), hasLength(1));
        expect(events.whereType<RunFinishedEvent>(), hasLength(1));
      });

      test('emits reconnect_failed + RunErrorEvent when exhausted', () async {
        final resumeClient = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          resumePolicy: const ResumePolicy(
            maxAttempts: 2,
            initialBackoff: Duration(milliseconds: 1),
            maxBackoff: Duration(milliseconds: 1),
            jitter: 0,
          ),
        );
        addTearDown(resumeClient.close);

        var callCount = 0;
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            // First call: one event (so we have a Last-Event-ID) + drop.
            return StreamedHttpResponse(
              statusCode: 200,
              body: sseByteStreamThenError(
                [
                  (
                    'run-2:0',
                    {
                      'type': 'RUN_STARTED',
                      'threadId': 't-1',
                      'runId': 'run-2',
                    },
                  ),
                ],
                const NetworkException(message: 'drop 1'),
              ),
            );
          }
          // Subsequent reconnects fail.
          throw NetworkException(message: 'drop $callCount');
        });

        final events =
            await resumeClient.runAgent(endpoint, input).toList();

        final customEvents = events.whereType<CustomEvent>().toList();
        expect(
          customEvents.where((e) => e.name == 'stream.reconnecting').length,
          2,
        );
        expect(
          customEvents.any((e) => e.name == 'stream.reconnect_failed'),
          isTrue,
        );
        // Synthetic RunErrorEvent marks the run terminal.
        expect(events.whereType<RunErrorEvent>(), hasLength(1));
        expect(
          events.whereType<RunErrorEvent>().first.code,
          'stream.resume_failed',
        );
        expect(callCount, 3); // initial + 2 retries
      });

      test('does not resume when no event id has been seen', () async {
        final resumeClient = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          resumePolicy: _fastPolicy,
        );
        addTearDown(resumeClient.close);

        // Stream drops before any event with an id is delivered.
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStreamThenError(
              const [],
              const NetworkException(message: 'early drop'),
            ),
          ),
        );

        await expectLater(
          resumeClient.runAgent(endpoint, input).toList(),
          throwsA(isA<NetworkException>()),
        );
        verify(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1); // No retry.
      });

      test('rethrows initial AuthException without resume', () async {
        final resumeClient = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          resumePolicy: _fastPolicy,
        );
        addTearDown(resumeClient.close);

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(
          const AuthException(message: 'Unauthorized', statusCode: 401),
        );

        await expectLater(
          resumeClient.runAgent(endpoint, input).toList(),
          throwsA(isA<AuthException>()),
        );
      });

      test(
          'auth error during resume is surfaced as reconnect_failed + '
          'RunErrorEvent', () async {
        final resumeClient = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          resumePolicy: _fastPolicy,
        );
        addTearDown(resumeClient.close);

        var callCount = 0;
        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return StreamedHttpResponse(
              statusCode: 200,
              body: sseByteStreamThenError(
                [
                  (
                    'run-3:0',
                    {
                      'type': 'RUN_STARTED',
                      'threadId': 't-1',
                      'runId': 'run-3',
                    },
                  ),
                ],
                const NetworkException(message: 'drop'),
              ),
            );
          }
          throw const AuthException(message: 'Unauthorized', statusCode: 401);
        });

        final events =
            await resumeClient.runAgent(endpoint, input).toList();

        final customEvents = events.whereType<CustomEvent>().toList();
        expect(
          customEvents.map((e) => e.name),
          containsAllInOrder([
            'stream.reconnecting',
            'stream.reconnect_failed',
          ]),
        );
        expect(events.whereType<RunErrorEvent>(), hasLength(1));
      });

      test('disabled policy rethrows network errors without retry', () async {
        final resumeClient = AgUiStreamClient(
          httpTransport: mockTransport,
          urlBuilder: UrlBuilder(baseUrl),
          resumePolicy: const ResumePolicy.disabled(),
        );
        addTearDown(resumeClient.close);

        when(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => StreamedHttpResponse(
            statusCode: 200,
            body: sseByteStreamThenError(
              [
                (
                  'run-4:0',
                  {
                    'type': 'RUN_STARTED',
                    'threadId': 't-1',
                    'runId': 'run-4',
                  },
                ),
              ],
              const NetworkException(message: 'drop'),
            ),
          ),
        );

        // With resume disabled and a lastEventId set, the client emits a
        // synthetic failure (no rethrow) instead of retrying.
        final events =
            await resumeClient.runAgent(endpoint, input).toList();
        expect(
          events.whereType<CustomEvent>().map((e) => e.name),
          contains('stream.reconnect_failed'),
        );
        expect(events.whereType<RunErrorEvent>(), hasLength(1));
        verify(
          () => mockTransport.requestStream(
            any(),
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      });
    });

    group('close', () {
      test('delegates to httpTransport.close()', () {
        client.close();

        verify(() => mockTransport.close()).called(1);
      });
    });
  });
}
