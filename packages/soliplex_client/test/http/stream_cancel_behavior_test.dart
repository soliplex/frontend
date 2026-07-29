@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

/// Empirical tests for TCP cancel semantics against a real Soliplex backend.
///
/// These tests verify whether `subscription.cancel()` on an active SSE
/// stream causes a clean TCP close (FIN) or an abrupt reset (RST).
///
/// Run with:
///   dart test --tags integration test/http/stream_cancel_behavior_test.dart
///
/// Requires SOLIPLEX_BASE_URL (default: https://demo.toughserv.com)
/// and a room named "chat".
void main() {
  late DartHttpClient httpClient;
  late HttpTransport transport;
  late UrlBuilder urlBuilder;
  late SoliplexApi api;

  setUpAll(() {
    final baseUrl =
        io.Platform.environment['SOLIPLEX_BASE_URL'] ?? 'http://localhost:8000';
    final apiBase = '$baseUrl/api/v1';
    httpClient = DartHttpClient();
    transport = HttpTransport(client: httpClient);
    urlBuilder = UrlBuilder(apiBase);
    api = SoliplexApi(transport: transport, urlBuilder: urlBuilder);
  });

  tearDownAll(() {
    httpClient.close();
  });

  /// Creates a thread in the "chat" room and returns (threadId, runId).
  Future<(String, String)> createThreadAndRun() async {
    final (threadInfo, _) = await api.createThread('plain');
    final threadId = threadInfo.id;

    String runId;
    if (threadInfo.hasInitialRun) {
      runId = threadInfo.initialRunId;
    } else {
      final runInfo = await api.createRun('plain', threadId);
      runId = runInfo.id;
    }
    return (threadId, runId);
  }

  /// Builds an SSE POST request and returns the raw streamed response.
  Future<StreamedHttpResponse> postSse(
    String threadId,
    String runId,
    String message,
  ) async {
    final uri = urlBuilder.build(
      pathSegments: ['rooms', 'plain', 'agui', threadId, runId],
    );

    final input = SimpleRunAgentInput(
      threadId: threadId,
      runId: runId,
      messages: [
        UserMessage(
          id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
          content: message,
        ),
      ],
    );

    return httpClient.requestStream(
      'POST',
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      },
      body: jsonEncode(input.toJson()),
    );
  }

  group('stream cancel TCP behavior', () {
    // Pre-create all threads so later tests don't fail if the server's
    // connection pool gets poisoned by an earlier cancel test.
    late String naturalThreadId;
    late String naturalRunId;
    late String eagerThreadId;
    late String eagerRunId;
    late String cancelThreadId;
    late String cancelRunId;

    test('setup — create threads for all tests', () async {
      (naturalThreadId, naturalRunId) = await createThreadAndRun();
      (eagerThreadId, eagerRunId) = await createThreadAndRun();
      (cancelThreadId, cancelRunId) = await createThreadAndRun();
    });

    test('natural completion — stream ends without cancel', () async {
      final response = await postSse(
        naturalThreadId,
        naturalRunId,
        'Say "hello" only.',
      );

      expect(response.statusCode, 200);

      // Collect all SSE data and let the stream complete naturally.
      final allBytes = <int>[];
      Object? streamError;

      await response.body
          .listen(allBytes.addAll, onError: (Object e) => streamError = e)
          .asFuture<void>();

      // Parse to verify we got events.
      final sseMessages = SseClient().parseStream(Stream.value(allBytes));
      final eventTypes = <String>[];
      await for (final msg in sseMessages) {
        if (msg.data == null || msg.data!.isEmpty) continue;
        final json = jsonDecode(msg.data!);
        if (json is Map<String, dynamic> && json['type'] != null) {
          eventTypes.add(json['type'] as String);
        }
      }

      expect(eventTypes.map((e) => e.toUpperCase()), contains('RUN_STARTED'));
      expect(eventTypes.map((e) => e.toUpperCase()), contains('RUN_FINISHED'));
      expect(streamError, isNull, reason: 'Natural close should have no error');

      // ignore: avoid_print
      print('NATURAL CLOSE: stream completed cleanly');
      // ignore: avoid_print
      print('  Events: $eventTypes');
    });

    test('eager cancel after RunFinished — the #60 pattern', () async {
      final response = await postSse(
        eagerThreadId,
        eagerRunId,
        'Say "hello" only.',
      );

      expect(response.statusCode, 200);

      final sseMessages = SseClient().parseStream(response.body);
      const decoder = EventDecoder();
      final eventTypes = <String>[];
      var cancelledAfterFinish = false;
      StreamSubscription<SseMessage>? sub;
      final completer = Completer<void>();

      sub = sseMessages.listen(
        (message) {
          if (message.data == null || message.data!.isEmpty) return;
          final json = jsonDecode(message.data!);
          if (json is Map<String, dynamic>) {
            final event = decoder.decodeJson(json);
            eventTypes.add(event.runtimeType.toString());

            if (event is RunFinishedEvent) {
              cancelledAfterFinish = true;
              sub?.cancel();
              if (!completer.isCompleted) completer.complete();
            }
          }
        },
        onError: (Object error) {
          // ignore: avoid_print
          print('  Stream error: $error');
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('Timed out waiting for RunFinished'),
      );

      expect(cancelledAfterFinish, isTrue);
      expect(eventTypes, contains('RunFinishedEvent'));

      // ignore: avoid_print
      print('EAGER CANCEL after RunFinished:');
      // ignore: avoid_print
      print('  Events before cancel: $eventTypes');
      // ignore: avoid_print
      print('  Check server logs for broken pipe / connection reset');
    });

    test('CancelToken cancel mid-stream — user-initiated abort', () async {
      final cancelToken = CancelToken();

      final response = await postSse(
        cancelThreadId,
        cancelRunId,
        'Write a 1000-word essay about the history of programming languages. '
        'Include every decade from the 1950s to the 2020s.',
      );

      expect(response.statusCode, 200);

      // Wrap with HttpTransport-style cancellation to test the real path.
      late StreamController<List<int>> controller;
      StreamSubscription<List<int>>? innerSub;

      controller = StreamController<List<int>>(
        onListen: () {
          cancelToken.whenCancelled.then((_) {
            if (!controller.isClosed) {
              controller
                ..addError(CancelledException(reason: cancelToken.reason))
                ..close();
              innerSub?.cancel();
            }
          });
          innerSub = response.body.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        },
        onCancel: () => innerSub?.cancel(),
      );

      // Read first chunk, then cancel.
      var gotFirstChunk = false;
      Object? caughtError;
      final completer = Completer<void>();

      controller.stream.listen(
        (data) {
          if (!gotFirstChunk) {
            gotFirstChunk = true;
            cancelToken.cancel('User navigated away');
          }
        },
        onError: (Object error) {
          caughtError = error;
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('Timed out'),
      );

      expect(gotFirstChunk, isTrue);
      expect(caughtError, isA<CancelledException>());

      // ignore: avoid_print
      print('CANCEL TOKEN mid-stream:');
      // ignore: avoid_print
      print('  First chunk received, then CancelToken fired');
      // ignore: avoid_print
      print('  CancelledException caught: ${caughtError != null}');
      // ignore: avoid_print
      print('  Check server logs for broken pipe / connection reset');
    });
  });
}
