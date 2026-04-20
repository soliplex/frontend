import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/agui_stream_client.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
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

        final captured =
            verify(
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

        final captured =
            verify(
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

        final captured =
            verify(
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
        final sseBody =
            StringBuffer()
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
        final sseBody =
            StringBuffer()
              ..writeln('data: ')
              ..writeln()
              ..writeln(
                'data: ${json.encode({'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'r-1'})}',
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

        final sseBody =
            StringBuffer()
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
        final sseBody =
            StringBuffer()
              ..writeln('data: not valid json at all')
              ..writeln()
              ..writeln(
                'data: ${json.encode({'type': 'RUN_STARTED', 'threadId': 't-1', 'runId': 'r-1'})}',
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

    group('close', () {
      test('delegates to httpTransport.close()', () {
        client.close();

        verify(() => mockTransport.close()).called(1);
      });
    });
  });
}
