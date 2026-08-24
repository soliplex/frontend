@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/cancel_token.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
// Import implementation directly since package uses conditional exports
import 'package:soliplex_client_native/src/clients/cupertino_http_client.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

/// The `openStream` factory `UploadTracker` hands to
/// `encodeMultipartStream` (`UploadTracker`'s `wrappedOpenStream`): an
/// `async*` generator forwarding the file stream through `await for` so it
/// can count bytes for progress. Cancelling the upload tears this down,
/// and an error the file stream raises while it unwinds is reported on the
/// future returned by `StreamSubscription.cancel()` rather than to
/// `onError`.
Stream<List<int>> progressCountingOpenStream(
  Stream<List<int>> file,
  void Function(int sent) emitProgress,
) async* {
  var sent = 0;
  await for (final chunk in file) {
    yield chunk;
    sent += chunk.length;
    emitProgress(sent);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeBaseRequest());
  });

  test(
    'cancelling a streaming upload does not leak the body teardown error',
    () async {
      final mockClient = _MockHttpClient();
      final diagnostics = <String>[];
      final client = CupertinoHttpClient.forTesting(
        client: mockClient,
        onDiagnostic: (error, _, {required message}) =>
            diagnostics.add('$message: $error'),
      );
      addTearDown(client.close);

      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as http.BaseRequest;
        // A real client reads the request body and fails the send when that
        // body errors, which is how the caller learns of the cancel.
        await request.finalize().toBytes();
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
      });

      final fileChunks = StreamController<List<int>>();
      final token = CancelToken();
      // Witness placed between the controller and the generator: it proves
      // the injected error really reached the body, without putting a
      // `finally` on the unwind path being tested.
      var reachedBody = false;
      final source = fileChunks.stream.handleError((Object e, StackTrace st) {
        reachedBody = true;
        Error.throwWithStackTrace(e, st);
      });

      // The file read failing as the socket goes down. Registered before the
      // client's own cancel listener so the error is in flight at the moment
      // the pipe cancels its source — the losing interleaving.
      unawaited(
        token.whenCancelled.then((_) {
          fileChunks.addError(StateError('file read failed'));
        }),
      );

      final encoded = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'a.pdf',
        openStream: () => progressCountingOpenStream(source, (_) {}),
        contentLength: 3,
      );

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final pending = client.request(
            'POST',
            Uri.parse('https://example.com/upload'),
            body: encoded.bodyStream,
            headers: {'content-type': encoded.contentType},
            cancelToken: token,
          );
          // Park the counting generator inside `await for`.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          fileChunks.add(const [1, 2, 3]);
          await Future<void>.delayed(const Duration(milliseconds: 30));

          token.cancel('user');

          // The caller's own contract on cancel, and the positive control
          // that the cancel machinery ran end to end.
          await expectLater(pending, throwsA(isA<CancelledException>()));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        },
        (error, _) => unhandled.add(error),
      );

      expect(
        unhandled,
        isEmpty,
        reason: 'an error raised while the counting generator unwinds must '
            'be absorbed by the pipe, not reach the zone',
      );
      // The read failure is not the cancellation the caller already has, so
      // it must leave a record rather than vanish.
      const expected = 'Request body teardown failed after cancel: '
          'Bad state: file read failed';
      expect(diagnostics, [expected]);
      expect(reachedBody, isTrue);
    },
  );

  test(
    'a cancellation surfacing from the body is not recorded',
    () async {
      final mockClient = _MockHttpClient();
      final diagnostics = <String>[];
      final client = CupertinoHttpClient.forTesting(
        client: mockClient,
        onDiagnostic: (error, _, {required message}) =>
            diagnostics.add('$message: $error'),
      );
      addTearDown(client.close);

      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as http.BaseRequest;
        // A real client reads the request body and fails the send when that
        // body errors, which is how the caller learns of the cancel.
        await request.finalize().toBytes();
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
      });

      final fileChunks = StreamController<List<int>>();
      final token = CancelToken();
      // Witness placed between the controller and the generator: it proves
      // the injected error really reached the body, without putting a
      // `finally` on the unwind path being tested.
      var reachedBody = false;
      final source = fileChunks.stream.handleError((Object e, StackTrace st) {
        reachedBody = true;
        Error.throwWithStackTrace(e, st);
      });

      // A cancel-aware body reacting to the same token, in flight at the
      // moment the pipe cancels its source.
      unawaited(
        token.whenCancelled.then((_) {
          fileChunks.addError(const CancelledException(reason: 'user'));
        }),
      );

      final encoded = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'a.pdf',
        openStream: () => progressCountingOpenStream(source, (_) {}),
        contentLength: 3,
      );

      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final pending = client.request(
            'POST',
            Uri.parse('https://example.com/upload'),
            body: encoded.bodyStream,
            headers: {'content-type': encoded.contentType},
            cancelToken: token,
          );
          // Park the counting generator inside `await for`.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          fileChunks.add(const [1, 2, 3]);
          await Future<void>.delayed(const Duration(milliseconds: 30));

          token.cancel('user');

          // The caller's own contract on cancel, and the positive control
          // that the cancel machinery ran end to end.
          await expectLater(pending, throwsA(isA<CancelledException>()));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        },
        (error, _) => unhandled.add(error),
      );

      expect(
        unhandled,
        isEmpty,
        reason: 'an error raised while the counting generator unwinds must '
            'be absorbed by the pipe, not reach the zone',
      );
      // The caller already has this cancellation on their request future,
      // so a second copy of it must leave no record.
      expect(diagnostics, isEmpty);
      expect(reachedBody, isTrue);
    },
  );

  test(
    'an abort reported as a client error surfaces as a cancellation',
    () async {
      // NSURLSession does not hand back the [CancelledException] the sink
      // carried: it crosses the `NSInputStream` bridge as an `NSError` and
      // arrives as `NSErrorClientException extends ClientException`. Without
      // the token check in that catch arm the caller sees a network failure
      // for a request they cancelled, and `UploadTracker`'s
      // `on CancelledException` arm never matches.
      final mockClient = _MockHttpClient();
      final diagnostics = <String>[];
      final client = CupertinoHttpClient.forTesting(
        client: mockClient,
        onDiagnostic: (error, _, {required message}) =>
            diagnostics.add('$message: $error'),
      );
      addTearDown(client.close);

      final gate = Completer<void>();
      when(() => mockClient.send(any())).thenAnswer((_) async {
        await gate.future;
        throw http.ClientException('NSError: cancelled');
      });

      final token = CancelToken();
      final pending = client.request(
        'POST',
        Uri.parse('https://example.com/upload'),
        // A streamed body is the only one wired to the token.
        body: Stream<List<int>>.fromIterable(const [
          [1, 2, 3],
        ]),
        headers: const {'content-type': 'application/octet-stream'},
        cancelToken: token,
      );
      // Cancel after dispatch, so the pre-flight check has already passed.
      token.cancel('user');
      gate.complete();

      await expectLater(pending, throwsA(isA<CancelledException>()));
      // The client error is discarded in favour of the cancellation, so this
      // record is the only trace the request died for another reason.
      const record = 'Client error on a cancelled streamed upload; '
          'reporting the cancellation instead: '
          'ClientException: NSError: cancelled';
      expect(diagnostics, [record]);
    },
  );

  test(
    'a client error on a buffered body stays a network failure',
    () async {
      // A buffered body is never wired to the token, so a cancel meant for
      // some other request sharing it must not relabel this failure.
      // `RoomInfoScreen` shares one token across two concurrent GETs.
      final mockClient = _MockHttpClient();
      final client = CupertinoHttpClient.forTesting(client: mockClient);
      addTearDown(client.close);

      final gate = Completer<void>();
      when(() => mockClient.send(any())).thenAnswer((_) async {
        await gate.future;
        throw http.ClientException('Connection reset by peer');
      });

      final token = CancelToken();
      final pending = client.request(
        'GET',
        Uri.parse('https://example.com/room'),
        cancelToken: token,
      );
      token.cancel('retry');
      gate.complete();

      await expectLater(pending, throwsA(isA<NetworkException>()));
    },
  );

  test(
    'requestStream maps an aborted streamed body to a cancellation too',
    () async {
      // The same guard arm, byte-identical, on the SSE entry point: a fix
      // landing in only one of the two is the risk this pins.
      final mockClient = _MockHttpClient();
      final client = CupertinoHttpClient.forTesting(client: mockClient);
      addTearDown(client.close);

      final gate = Completer<void>();
      when(() => mockClient.send(any())).thenAnswer((_) async {
        await gate.future;
        throw http.ClientException('NSError: cancelled');
      });

      final token = CancelToken();
      final pending = client.requestStream(
        'POST',
        Uri.parse('https://example.com/stream'),
        body: Stream<List<int>>.fromIterable(const [
          [1, 2, 3],
        ]),
        headers: const {'content-type': 'application/octet-stream'},
        cancelToken: token,
      );
      token.cancel('user');
      gate.complete();

      await expectLater(pending, throwsA(isA<CancelledException>()));
    },
  );
}
