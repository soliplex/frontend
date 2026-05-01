import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
import 'package:fake_async/fake_async.dart';
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

      test(
        'mixed batch with two undecodable items reports skipped=2',
        () async {
          // Decision 2: _decodeOne returns ({events, skipped}); the
          // caller-side accumulator must count both undecodable items
          // and surface them as a single onWarning at clean termination.
          final warnings = <String>[];
          final clientWithWarning = AgUiStreamClient(
            httpTransport: mockTransport,
            urlBuilder: UrlBuilder(baseUrl),
            onWarning: warnings.add,
          );
          addTearDown(clientWithWarning.close);

          final batch = [
            {'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'r-1'},
            {'type': 'TOTALLY_UNKNOWN_EVENT', 'a': 1},
            'not even an object',
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

          final result =
              await clientWithWarning.runAgent(endpoint, input).toList();

          expect(result, hasLength(2));
          expect(warnings, hasLength(1));
          expect(warnings.single, contains('Skipped 2 malformed event'));
        },
      );

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
        // Decision 1: reconnect lifecycle flows through the
        // onReconnectStatus callback, NOT via synthetic CustomEvents
        // on the BaseEvent stream.
        final statuses = <ReconnectStatus>[];
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
        final run = resumeClient.runAgent(
          endpoint,
          input,
          onReconnectStatus: statuses.add,
        );
        final iterator = StreamIterator<BaseEvent>(run);

        // Drain the first two real events. Then re-stub the transport
        // for the resume request before consuming further.
        await iterator.moveNext();
        events.add(iterator.current);
        await iterator.moveNext();
        events.add(iterator.current);

        // Swap the stub to return events 2..3 + RUN_FINISHED.
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

        // Reconnect lifecycle on the callback, in order.
        expect(statuses, hasLength(2));
        expect(statuses[0], isA<Reconnecting>());
        expect((statuses[0] as Reconnecting).attempt, 1);
        expect((statuses[0] as Reconnecting).lastEventId, 'run-1:1');
        expect(statuses[1], isA<Reconnected>());
        expect((statuses[1] as Reconnected).attempt, 1);

        // No CustomEvents leaked into the BaseEvent stream.
        expect(events.whereType<CustomEvent>(), isEmpty);

        // Run events delivered end-to-end.
        expect(events.whereType<RunStartedEvent>(), hasLength(1));
        expect(events.whereType<TextMessageContentEvent>(), hasLength(1));
        expect(events.whereType<RunFinishedEvent>(), hasLength(1));
      });

      test(
        'multi-resume: cursor preserved across two consecutive drops',
        () async {
          // Plan A4: drops twice consecutively → Reconnecting × 2,
          // Reconnected × 1. Resume #1 fails at the transport layer
          // (no body events yielded → no Reconnected fires); resume #2
          // succeeds and fires Reconnected once.
          final statuses = <ReconnectStatus>[];
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
              // Initial: yield :0 with id, then drop.
              return StreamedHttpResponse(
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
                  ],
                  const NetworkException(message: 'drop 1'),
                ),
              );
            }
            if (callCount == 2) {
              // Resume #1: transport rejects connection — no body
              // events ever flow, so no Reconnected fires.
              throw const NetworkException(message: 'drop 2');
            }
            // Resume #2: yield finish.
            return StreamedHttpResponse(
              statusCode: 200,
              body: sseByteStreamWithIds([
                (
                  'run-1:1',
                  {
                    'type': 'RUN_FINISHED',
                    'threadId': 't-1',
                    'runId': 'run-1',
                  },
                ),
              ]),
            );
          });

          final events = await resumeClient
              .runAgent(
                endpoint,
                input,
                onReconnectStatus: statuses.add,
              )
              .toList();

          expect(callCount, 3);

          final captured = verify(
            () => mockTransport.requestStream(
              any(),
              any(),
              headers: captureAny(named: 'headers'),
              body: any(named: 'body'),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).captured;
          expect(captured, hasLength(3));
          final h1 = captured[0] as Map<String, String>;
          final h2 = captured[1] as Map<String, String>;
          final h3 = captured[2] as Map<String, String>;
          expect(h1.containsKey('Last-Event-ID'), isFalse);
          // Both resumes carry the cursor from the only event yielded
          // so far. Resume #1 didn't yield, so the cursor stays at :0.
          expect(h2['Last-Event-ID'], 'run-1:0');
          expect(h3['Last-Event-ID'], 'run-1:0');

          // Reconnecting × 2, Reconnected × 1.
          expect(statuses.whereType<Reconnecting>(), hasLength(2));
          expect(statuses.whereType<Reconnected>(), hasLength(1));
          expect(statuses.whereType<ReconnectFailed>(), isEmpty);
          expect(statuses.first, isA<Reconnecting>());
          expect((statuses[0] as Reconnecting).attempt, 1);
          expect((statuses[1] as Reconnecting).attempt, 2);
          expect(statuses.last, isA<Reconnected>());
          expect((statuses.last as Reconnected).attempt, 2);

          expect(events.whereType<RunFinishedEvent>(), hasLength(1));
        },
      );

      test(
        'retry-budget exhausted: throws NetworkException with marker prefix',
        () async {
          // Decision 4: streamResumeFailedPrefix is the exact prefix of
          // the thrown NetworkException's message on retry exhaustion.
          final statuses = <ReconnectStatus>[];
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
            throw NetworkException(message: 'drop $callCount');
          });

          await expectLater(
            resumeClient
                .runAgent(
                  endpoint,
                  input,
                  onReconnectStatus: statuses.add,
                )
                .toList(),
            throwsA(
              isA<NetworkException>().having(
                (e) => e.message,
                'message',
                startsWith(streamResumeFailedPrefix),
              ),
            ),
          );

          // Reconnecting × 2, then ReconnectFailed × 1.
          expect(statuses.whereType<Reconnecting>(), hasLength(2));
          expect(statuses.whereType<ReconnectFailed>(), hasLength(1));
          expect(statuses.last, isA<ReconnectFailed>());
          expect((statuses.last as ReconnectFailed).attempts, 2);
          expect(callCount, 3); // initial + 2 retries
        },
      );

      test(
        'retry exhaustion still flushes skipped-event warning and embeds '
        'count in NetworkException message',
        () async {
          // Decision 6: skipped-event diagnostics survive terminal
          // failure. Both _onWarning AND the thrown message carry the
          // count.
          final warnings = <String>[];
          final resumeClient = AgUiStreamClient(
            httpTransport: mockTransport,
            urlBuilder: UrlBuilder(baseUrl),
            onWarning: warnings.add,
            resumePolicy: const ResumePolicy(
              maxAttempts: 1,
              initialBackoff: Duration(milliseconds: 1),
              maxBackoff: Duration(milliseconds: 1),
              jitter: 0,
            ),
          );
          addTearDown(resumeClient.close);

          // Initial: yield a batch with 2 undecodable items + one good
          // event with id, then drop.
          final batch = [
            {'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'run-3'},
            {'type': 'TOTALLY_UNKNOWN_EVENT', 'a': 1},
            'plain string in batch',
          ];
          final initialBytes = StreamController<List<int>>();
          unawaited(
            Future<void>(() async {
              final buf = StringBuffer()
                ..writeln('id: run-3:0')
                ..writeln('data: ${json.encode(batch)}')
                ..writeln();
              initialBytes.add(utf8.encode(buf.toString()));
              await Future<void>.delayed(Duration.zero);
              initialBytes.addError(const NetworkException(message: 'drop'));
              await initialBytes.close();
            }),
          );

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
                body: initialBytes.stream,
              );
            }
            // Resume attempt fails terminally.
            throw const NetworkException(message: 'drop again');
          });

          await expectLater(
            resumeClient.runAgent(endpoint, input).toList(),
            throwsA(
              isA<NetworkException>().having(
                (e) => e.message,
                'message',
                allOf(
                  startsWith(streamResumeFailedPrefix),
                  contains('skipped 2 malformed events'),
                ),
              ),
            ),
          );

          // _onWarning still fires once with the count.
          expect(warnings, hasLength(1));
          expect(warnings.single, contains('Skipped 2 malformed event'));
        },
      );

      test(
        'no-cursor mid-flight drop: NetworkException carries marker prefix',
        () async {
          // Decision 5 (friendly-message routing): when the stream
          // errors before any id has been seen, there is nothing to
          // resume against, but we still wrap the failure so the UI
          // renders friendly copy via _friendlyMessage.
          final resumeClient = AgUiStreamClient(
            httpTransport: mockTransport,
            urlBuilder: UrlBuilder(baseUrl),
            resumePolicy: _fastPolicy,
          );
          addTearDown(resumeClient.close);

          // Yield one event WITHOUT an id, then drop.
          final controller = StreamController<List<int>>();
          unawaited(
            Future<void>(() async {
              final buf = StringBuffer()
                ..writeln(
                  'data: ${json.encode({
                        'type': 'RUN_STARTED',
                        'threadId': 't-1',
                        'runId': 'r-1',
                      })}',
                )
                ..writeln();
              controller.add(utf8.encode(buf.toString()));
              await Future<void>.delayed(Duration.zero);
              controller.addError(const NetworkException(message: 'mid drop'));
              await controller.close();
            }),
          );

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
              body: controller.stream,
            ),
          );

          await expectLater(
            resumeClient.runAgent(endpoint, input).toList(),
            throwsA(
              isA<NetworkException>().having(
                (e) => e.message,
                'message',
                startsWith(streamResumeFailedPrefix),
              ),
            ),
          );
          // No retry attempt was made — there was no cursor.
          verify(
            () => mockTransport.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
        },
      );

      test(
        'initial-connect failure rethrows raw NetworkException without marker',
        () async {
          // The marker prefix is reserved for resume-attempt failures.
          // An initial POST that fails must surface the original
          // exception unchanged so callers can react accordingly.
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
          ).thenThrow(const NetworkException(message: 'connect refused'));

          await expectLater(
            resumeClient.runAgent(endpoint, input).toList(),
            throwsA(
              isA<NetworkException>().having(
                (e) => e.message,
                'message',
                isNot(startsWith(streamResumeFailedPrefix)),
              ),
            ),
          );
          verify(
            () => mockTransport.requestStream(
              any(),
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
        },
      );

      test(
        'auth error during resume → ReconnectFailed + NetworkException',
        () async {
          final statuses = <ReconnectStatus>[];
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

          await expectLater(
            resumeClient
                .runAgent(
                  endpoint,
                  input,
                  onReconnectStatus: statuses.add,
                )
                .toList(),
            throwsA(
              isA<NetworkException>().having(
                (e) => e.message,
                'message',
                startsWith(streamResumeFailedPrefix),
              ),
            ),
          );

          expect(statuses.whereType<Reconnecting>(), hasLength(1));
          expect(statuses.whereType<ReconnectFailed>(), hasLength(1));
        },
      );
    });

    group('raceBackoff (Decision 3 — cancel-aware backoff)', () {
      test('returns normally when delay elapses without cancellation', () {
        fakeAsync((async) {
          final token = CancelToken();
          var completed = false;
          unawaited(
            AgUiStreamClient.raceBackoff(const Duration(seconds: 1), token)
                .then((_) => completed = true),
          );

          async.elapse(const Duration(milliseconds: 999));
          expect(completed, isFalse);
          async.elapse(const Duration(milliseconds: 2));
          expect(completed, isTrue);
        });
      });

      test('throws CancelledException promptly when cancelled mid-delay',
          () async {
        final token = CancelToken();
        final stopwatch = Stopwatch()..start();
        // Cancel after 10ms while a 5-second backoff is in progress.
        Future<void>.delayed(
          const Duration(milliseconds: 10),
          () => token.cancel('user cancel'),
        );

        await expectLater(
          AgUiStreamClient.raceBackoff(const Duration(seconds: 5), token),
          throwsA(isA<CancelledException>()),
        );
        // The cancel-aware race must resolve well before the full
        // backoff. Generous 1-second cap protects against CI jitter
        // while still proving we didn't sit on the 5-second delay.
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('without a token, just delays', () {
        fakeAsync((async) {
          var completed = false;
          unawaited(
            AgUiStreamClient.raceBackoff(const Duration(seconds: 1), null)
                .then((_) => completed = true),
          );
          async.elapse(const Duration(milliseconds: 1001));
          expect(completed, isTrue);
        });
      });
    });
  });
}
