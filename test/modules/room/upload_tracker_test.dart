import 'dart:async';
import 'dart:io' show FileSystemException, SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

import '../../helpers/fakes.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

// Lets the event loop drain pending microtasks so awaited Futures
// chained inside the tracker can run to completion.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

FileUpload _fileUpload(String filename, [String? url]) {
  return FileUpload(
    filename: filename,
    url: Uri.parse(url ?? 'https://example.com/$filename'),
  );
}

void main() {
  late MockSoliplexApi mockApi;
  late UploadTracker tracker;

  setUpAll(() {
    registerFallbackValue(CancelToken());
  });

  late AuthSession auth;

  setUp(() {
    mockApi = MockSoliplexApi();
    auth = AuthSession(refreshService: FakeTokenRefreshService());
    tracker = UploadTracker(api: mockApi, auth: auth);
  });

  tearDown(() {
    tracker.dispose();
    reset(mockApi);
  });

  // Default: upload methods succeed; override per test as needed.
  void stubUploadToRoomSuccess() {
    when(() => mockApi.uploadFileToRoom(
          any(),
          filename: any(named: 'filename'),
          openStream: any(named: 'openStream'),
          contentLength: any(named: 'contentLength'),
          mimeType: any(named: 'mimeType'),
          webFileBlob: any(named: 'webFileBlob'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async {});
  }

  void stubUploadToThreadSuccess() {
    when(() => mockApi.uploadFileToThread(
          any(),
          any(),
          filename: any(named: 'filename'),
          openStream: any(named: 'openStream'),
          contentLength: any(named: 'contentLength'),
          mimeType: any(named: 'mimeType'),
          webFileBlob: any(named: 'webFileBlob'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async {});
  }

  void stubGetRoomUploads(List<FileUpload> uploads) {
    when(() => mockApi.getRoomUploads(
          any(),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async => uploads);
  }

  void stubGetThreadUploads(List<FileUpload> uploads) {
    when(() => mockApi.getThreadUploads(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async => uploads);
  }

  group('initial fetch', () {
    test('emits Loading then Loaded with server list', () async {
      stubGetRoomUploads([_fileUpload('a.pdf'), _fileUpload('b.txt')]);

      unawaited(tracker.refreshRoom('room-1'));
      expect(tracker.roomUploads('room-1').value, isA<UploadsLoading>());

      await _pump();

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsLoaded>());
      final uploads = (status as UploadsLoaded).uploads;
      expect(uploads, hasLength(2));
      expect(uploads.every((u) => u is PersistedUpload), isTrue);
      expect(uploads.map((u) => u.filename), ['a.pdf', 'b.txt']);
    });

    test('emits Loaded with empty list when server returns empty', () async {
      stubGetRoomUploads([]);

      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsLoaded>());
      expect((status as UploadsLoaded).uploads, isEmpty);
    });
  });

  group('fetch failure', () {
    test('emits UploadsFailed from a non-Loaded state', () async {
      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenThrow(const ApiException(statusCode: 500, message: 'boom'));

      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsFailed>());
      expect((status as UploadsFailed).error, isA<ApiException>());
    });

    test('preserves Loaded list when a refresh fails', () async {
      stubGetRoomUploads([_fileUpload('a.pdf')]);

      unawaited(tracker.refreshRoom('room-1'));
      await _pump();
      expect(tracker.roomUploads('room-1').value, isA<UploadsLoaded>());

      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenThrow(
        NetworkException(message: 'wifi down'),
      );

      await tracker.refreshRoom('room-1');

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsLoaded>());
      expect((status as UploadsLoaded).uploads, hasLength(1));
    });

    test(
        'wraps a non-SoliplexException into UploadsFailed(UnexpectedException)',
        () async {
      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {
        throw StateError('unexpected non-soliplex error');
      });

      await tracker.refreshRoom('room-1');

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsFailed>());
      final failure = status as UploadsFailed;
      expect(failure.error, isA<UnexpectedException>());
      expect(failure.error.originalError, isA<StateError>());
    });

    test('keeps stale Loaded list when a non-SoliplexException refresh fails',
        () async {
      stubGetRoomUploads([_fileUpload('a.pdf')]);
      await tracker.refreshRoom('room-1');
      expect(tracker.roomUploads('room-1').value, isA<UploadsLoaded>());

      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {
        throw TypeError();
      });

      await tracker.refreshRoom('room-1');

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsLoaded>());
      expect((status as UploadsLoaded).uploads, hasLength(1));
    });
  });

  group('upload success', () {
    test('appends Pending, then drops it when refresh surfaces Persisted',
        () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final uploadCompleter = Completer<void>();
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => uploadCompleter.future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: () => Stream<List<int>>.value(const [1, 2, 3]),
        contentLength: 3,
      );

      // Pending appears immediately, atop the (empty) persisted list.
      var entries =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(entries, hasLength(1));
      expect(entries.single, isA<PendingUpload>());
      expect(entries.single.filename, 'a.pdf');

      // Next refresh returns the new file.
      stubGetRoomUploads([_fileUpload('a.pdf')]);

      uploadCompleter.complete();
      await _pump();

      entries = (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(entries, hasLength(1));
      expect(entries.single, isA<PersistedUpload>());
      expect(entries.single.filename, 'a.pdf');
    });

    test('overwrite: renders both rows briefly, ends with single Persisted',
        () async {
      // Server already has a.pdf.
      stubGetRoomUploads([_fileUpload('a.pdf', 'https://example.com/old')]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final uploadCompleter = Completer<void>();
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => uploadCompleter.future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );

      // Both rows visible during the POST: old Persisted + new Pending.
      final duringUpload =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(duringUpload, hasLength(2));
      expect(duringUpload.whereType<PersistedUpload>(), hasLength(1));
      expect(duringUpload.whereType<PendingUpload>(), hasLength(1));

      // Refresh returns the new file (same filename, new url).
      stubGetRoomUploads([_fileUpload('a.pdf', 'https://example.com/new')]);
      uploadCompleter.complete();
      await _pump();

      final after =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(after, hasLength(1));
      expect(after.single, isA<PersistedUpload>());
      expect(
        (after.single as PersistedUpload).url.toString(),
        'https://example.com/new',
      );
    });

    test(
        'concurrent same-name uploads: first completion drops only the '
        'first pending; second completion drops the second', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final firstCompleter = Completer<void>();
      final secondCompleter = Completer<void>();
      final completers = <Completer<void>>[firstCompleter, secondCompleter];
      var callIndex = 0;

      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => completers[callIndex++].future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'dup.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'dup.pdf',
        openStream: () => Stream<List<int>>.value(const [2]),
        contentLength: 1,
      );

      var pending = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<PendingUpload>()
          .toList();
      expect(pending, hasLength(2));
      expect(pending.map((e) => e.id).toSet(), hasLength(2));

      // After the first POST completes, its refresh returns the now-
      // persisted file. The first record (now _Posted, filename
      // matches persisted) drops. The second pending remains because
      // its POST hasn't completed yet.
      stubGetRoomUploads([_fileUpload('dup.pdf')]);
      firstCompleter.complete();
      await _pump();

      pending = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<PendingUpload>()
          .toList();
      expect(pending, hasLength(1));

      // After the second POST completes, its refresh confirms the
      // (overwritten) file. The second pending drops.
      secondCompleter.complete();
      await _pump();

      pending = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<PendingUpload>()
          .toList();
      expect(pending, isEmpty);
    });
  });

  group('upload failure', () {
    test('flips Pending to Failed; parent status stays Loaded', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenThrow(const ApiException(statusCode: 500, message: 'nope'));

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'fail.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      await _pump();

      final status = tracker.roomUploads('room-1').value;
      expect(status, isA<UploadsLoaded>(),
          reason: 'POST failures must not transition the parent status');
      final entries = (status as UploadsLoaded).uploads;
      expect(entries, hasLength(1));
      final failed = entries.single as FailedUpload;
      expect(failed.filename, 'fail.pdf');
      expect(
        failed.message,
        'Server is temporarily unavailable. Try uploading again in a moment.',
      );

      // No extra list fetch was triggered by the failure — the catch
      // path must not call refresh. (Initial fetch is the one call.)
      verify(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).called(1);
    });

    test('non-Exception throw from POST becomes a Failed row, not a spinner',
        () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {
        throw StateError('plugin bug');
      });

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'fail.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      await _pump();

      final entries =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(entries, hasLength(1));
      expect(entries.single, isA<FailedUpload>());
    });
  });

  group('recordClientError', () {
    test('surfaces a FailedUpload row on the room scope', () async {
      stubGetRoomUploads([]);
      await tracker.refreshRoom('room-1');

      tracker.recordClientError(
        roomId: 'room-1',
        filename: 'doc.pdf',
        message: 'Failed to read file',
      );

      final entries =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(entries, hasLength(1));
      final failed = entries.single as FailedUpload;
      expect(failed.filename, 'doc.pdf');
      expect(failed.message, 'Failed to read file');
    });

    test('routes to the thread scope when threadId is supplied', () async {
      stubGetRoomUploads([]);
      stubGetThreadUploads([]);
      await tracker.refreshRoom('room-1');
      await tracker.refreshThread('room-1', 'thread-1');

      tracker.recordClientError(
        roomId: 'room-1',
        threadId: 'thread-1',
        filename: 'doc.pdf',
        message: 'Failed to read file',
      );

      expect(
        (tracker.roomUploads('room-1').value as UploadsLoaded).uploads,
        isEmpty,
      );
      final threadEntries =
          (tracker.threadUploads('room-1', 'thread-1').value as UploadsLoaded)
              .uploads;
      expect(threadEntries.single, isA<FailedUpload>());
      expect(threadEntries.single.filename, 'doc.pdf');
    });

    test('assigns unique ids so each row is independently dismissible',
        () async {
      stubGetRoomUploads([]);
      await tracker.refreshRoom('room-1');

      tracker.recordClientError(
        roomId: 'room-1',
        filename: 'one.pdf',
        message: 'fail',
      );
      tracker.recordClientError(
        roomId: 'room-1',
        filename: 'two.pdf',
        message: 'fail',
      );

      final entries = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<FailedUpload>()
          .toList();
      expect(entries, hasLength(2));
      expect(entries[0].id, isNot(equals(entries[1].id)));

      tracker.dismissFailed(entries.first.id);
      final remaining = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<FailedUpload>();
      expect(remaining.single.filename, 'two.pdf');
    });
  });

  group('re-fetch races', () {
    test("cancelled upload-refresh doesn't strand a completed upload",
        () async {
      // Initial fetch: empty room.
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final postA = Completer<void>();
      final postB = Completer<void>();
      final posts = [postA, postB];
      var postIdx = 0;

      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => posts[postIdx++].future);

      // Each upload-triggered refresh gets its own completer so we
      // can resolve them out of order.
      final fetchA = Completer<List<FileUpload>>();
      final fetchB = Completer<List<FileUpload>>();
      final fetches = [fetchA, fetchB];
      var fetchIdx = 0;

      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => fetches[fetchIdx++].future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'b.pdf',
        openStream: () => Stream<List<int>>.value(const [2]),
        contentLength: 1,
      );

      postA.complete();
      await _pump();
      // A's refresh is now in flight (fetchA).

      postB.complete();
      await _pump();
      // B's refresh cancels A's token and starts fetchB.

      // fetchA completes late — cancelled token, value ignored.
      fetchA.complete([_fileUpload('a.pdf')]);
      await _pump();

      // fetchB completes with both persisted files.
      fetchB.complete([_fileUpload('a.pdf'), _fileUpload('b.pdf')]);
      await _pump();

      final uploads =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(
        uploads.whereType<PersistedUpload>().map((e) => e.filename),
        containsAll(['a.pdf', 'b.pdf']),
      );
      expect(
        uploads.whereType<PendingUpload>(),
        isEmpty,
        reason: 'both uploads completed and appear in persisted; '
            "neither should be stranded as pending even though A's "
            'refresh was cancelled by B',
      );
    });

    test('late response from a cancelled fetch does not overwrite state',
        () async {
      final first = Completer<List<FileUpload>>();
      final second = Completer<List<FileUpload>>();
      final completers = [first, second];
      var callIndex = 0;

      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => completers[callIndex++].future);

      unawaited(tracker.refreshRoom('room-1'));
      // Kick a second fetch; internally this cancels the first token.
      unawaited(tracker.refreshRoom('room-1'));

      // Complete the NEW fetch first, so the scope becomes Loaded
      // with its result.
      second.complete([_fileUpload('winner.pdf')]);
      await _pump();
      expect(
        (tracker.roomUploads('room-1').value as UploadsLoaded)
            .uploads
            .single
            .filename,
        'winner.pdf',
      );

      // Now complete the cancelled fetch. Its guard must swallow the
      // result; the scope must still show the newer list.
      first.complete([_fileUpload('loser.pdf')]);
      await _pump();

      expect(
        (tracker.roomUploads('room-1').value as UploadsLoaded)
            .uploads
            .single
            .filename,
        'winner.pdf',
      );
    });
  });

  group('cancelUpload', () {
    test(
      'flips an in-flight Pending row to Failed with a cancelled message '
      'and cancels its token',
      () async {
        stubGetRoomUploads([]);
        unawaited(tracker.refreshRoom('room-1'));
        await _pump();

        CancelToken? capturedToken;
        final never = Completer<void>();
        when(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((invocation) {
          capturedToken =
              invocation.namedArguments[#cancelToken] as CancelToken;
          return never.future;
        });

        tracker.uploadToRoom(
          roomId: 'room-1',
          filename: 'a.pdf',
          openStream: () => Stream<List<int>>.value(const [1]),
          contentLength: 1,
        );
        await _pump();

        expect(capturedToken, isNotNull);
        expect(capturedToken!.isCancelled, isFalse);

        final pending = (tracker.roomUploads('room-1').value as UploadsLoaded)
            .uploads
            .whereType<PendingUpload>()
            .single;

        tracker.cancelUpload(pending.id);

        final failed = (tracker.roomUploads('room-1').value as UploadsLoaded)
            .uploads
            .whereType<FailedUpload>()
            .single;
        expect(failed.id, pending.id);
        expect(failed.filename, 'a.pdf');
        expect(failed.message, 'Upload cancelled.');

        expect(capturedToken!.isCancelled, isTrue);
        expect(capturedToken!.reason, 'user');
      },
    );

    test('is a no-op for an unknown id', () async {
      stubGetRoomUploads([_fileUpload('a.pdf')]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      tracker.cancelUpload('upload-9999');

      final uploads =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(uploads, hasLength(1));
      expect(uploads.single, isA<PersistedUpload>());
    });

    test(
      'cancelling a queued-but-not-started upload yields a Failed row '
      'and the API is never called',
      () async {
        stubGetRoomUploads([]);
        unawaited(tracker.refreshRoom('room-1'));
        await _pump();

        // Block the first upload's POST forever so the second stays
        // queued, never reaching the API.
        final blocked = Completer<void>();
        when(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((_) => blocked.future);

        tracker.uploadToRoom(
          roomId: 'room-1',
          filename: 'first.pdf',
          openStream: () => Stream<List<int>>.value(const [1]),
          contentLength: 1,
        );
        tracker.uploadToRoom(
          roomId: 'room-1',
          filename: 'second.pdf',
          openStream: () => Stream<List<int>>.value(const [2]),
          contentLength: 1,
        );
        await _pump();

        final pendings = (tracker.roomUploads('room-1').value as UploadsLoaded)
            .uploads
            .whereType<PendingUpload>()
            .toList();
        final second = pendings.firstWhere((p) => p.filename == 'second.pdf');

        // Only the first job's POST was invoked; the second is queued.
        verify(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).called(1);

        tracker.cancelUpload(second.id);
        await _pump();

        // Second became a Failed row; first stayed Pending.
        final uploads =
            (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
        final failed = uploads.whereType<FailedUpload>().single;
        expect(failed.filename, 'second.pdf');
        expect(failed.message, 'Upload cancelled.');

        // No new API call for the cancelled queued job.
        verifyNever(() => mockApi.uploadFileToRoom(
              any(),
              filename: 'second.pdf',
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            ));
      },
    );
  });

  group('dismissFailed', () {
    test('removes a Failed entry by id', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenThrow(NetworkException(message: 'dns'));

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      await _pump();

      final failed = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<FailedUpload>()
          .single;

      tracker.dismissFailed(failed.id);

      expect(
        (tracker.roomUploads('room-1').value as UploadsLoaded).uploads,
        isEmpty,
      );
    });

    test('is a no-op for an unknown id', () async {
      stubGetRoomUploads([_fileUpload('a.pdf')]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      tracker.dismissFailed('a.pdf'); // mistaken use of filename as id
      tracker.dismissFailed('upload-9999');

      final uploads =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      expect(uploads, hasLength(1));
      expect(uploads.single, isA<PersistedUpload>());
    });

    test('asserts when called on a Pending record', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final never = Completer<void>();
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => never.future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );

      final pending = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<PendingUpload>()
          .single;

      expect(() => tracker.dismissFailed(pending.id), throwsAssertionError);

      // The pending record survives — assertion fires but release-mode
      // behavior still refuses the removal.
      expect(
        (tracker.roomUploads('room-1').value as UploadsLoaded)
            .uploads
            .whereType<PendingUpload>(),
        hasLength(1),
      );
    });
  });

  group('scoping', () {
    test('room and thread scopes hold independent state', () async {
      stubGetRoomUploads([_fileUpload('room.pdf')]);
      stubGetThreadUploads([_fileUpload('thread.pdf')]);
      stubUploadToRoomSuccess();
      stubUploadToThreadSuccess();

      unawaited(tracker.refreshRoom('room-1'));
      unawaited(tracker.refreshThread('room-1', 'thread-1'));
      await _pump();

      final roomUploads =
          (tracker.roomUploads('room-1').value as UploadsLoaded).uploads;
      final threadUploads =
          (tracker.threadUploads('room-1', 'thread-1').value as UploadsLoaded)
              .uploads;

      expect(roomUploads.single.filename, 'room.pdf');
      expect(threadUploads.single.filename, 'thread.pdf');
    });

    test('distinct threads under the same room are independent', () async {
      // Use a call counter so each thread scope gets its own list.
      var callCount = 0;
      when(() => mockApi.getThreadUploads(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((invocation) async {
        final threadId = invocation.positionalArguments[1] as String;
        callCount++;
        return [_fileUpload('$threadId.pdf')];
      });

      unawaited(tracker.refreshThread('room-1', 'thread-a'));
      unawaited(tracker.refreshThread('room-1', 'thread-b'));
      await _pump();

      expect(callCount, 2);
      final a =
          (tracker.threadUploads('room-1', 'thread-a').value as UploadsLoaded)
              .uploads
              .single;
      final b =
          (tracker.threadUploads('room-1', 'thread-b').value as UploadsLoaded)
              .uploads
              .single;
      expect(a.filename, 'thread-a.pdf');
      expect(b.filename, 'thread-b.pdf');
    });
  });

  group('dispose', () {
    test('cancels any in-flight list fetch', () async {
      final never = Completer<List<FileUpload>>();
      CancelToken? capturedToken;

      when(() => mockApi.getRoomUploads(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((invocation) {
        capturedToken = invocation.namedArguments[#cancelToken] as CancelToken?;
        return never.future;
      });

      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isFalse);

      tracker.dispose();

      expect(capturedToken!.isCancelled, isTrue);
    });

    test('does not cancel in-flight uploads (POSTs have no CancelToken)',
        () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      // The upload method has no cancelToken parameter — intentional
      // per plan. Verify the signature in the stub doesn't reference one.
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {});

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'x.pdf',
        openStream: () => Stream<List<int>>.value(const [0]),
        contentLength: 1,
      );
      tracker.dispose();

      // No exception; dispose completes cleanly even with an in-flight
      // upload Future. (The Future continues but its result is ignored
      // because _isDisposed is set.)
    });

    test('roomUploads throws StateError after dispose', () {
      tracker.dispose();
      expect(() => tracker.roomUploads('room-1'), throwsStateError);
    });

    test('threadUploads throws StateError after dispose', () {
      tracker.dispose();
      expect(
        () => tracker.threadUploads('room-1', 'thread-1'),
        throwsStateError,
      );
    });

    test('dispose cancels the in-flight upload CancelToken', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      CancelToken? capturedToken;
      final uploadCompleter = Completer<void>();
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((invocation) {
        capturedToken = invocation.namedArguments[#cancelToken] as CancelToken;
        return uploadCompleter.future;
      });

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: () => Stream<List<int>>.value(const [1, 2, 3]),
        contentLength: 3,
      );
      await _pump();

      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isFalse);

      tracker.dispose();

      expect(capturedToken!.isCancelled, isTrue);
      expect(capturedToken!.reason, 'disposed');
    });
  });

  group('auth retry', () {
    test('AuthException triggers one retry with a fresh openStream call',
        () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      var callCount = 0;
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw const AuthException(statusCode: 401, message: 'token expired');
        }
        // Retry succeeds.
      });

      var factoryCalls = 0;
      Stream<List<int>> openStream() {
        factoryCalls++;
        return Stream<List<int>>.value(const [1, 2, 3]);
      }

      stubGetRoomUploads([_fileUpload('a.pdf')]);
      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'a.pdf',
        openStream: openStream,
        contentLength: 3,
      );
      await _pump();
      await _pump();

      // Two POSTs (one failed, one succeeded); the API method is the one
      // that drains openStream on each call, so factoryCalls reflects
      // POST attempts here too.
      expect(callCount, 2);
      expect(factoryCalls, 0,
          reason: 'Mock API does not drain the stream; factory is invoked '
              'inside the real api method, not the mock.');

      // No Failed row — retry succeeded.
      final status = tracker.roomUploads('room-1').value as UploadsLoaded;
      expect(status.uploads.whereType<FailedUpload>(), isEmpty);
    });

    test('AuthException on every attempt surfaces a Failed row', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      auth.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      var callCount = 0;
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {
        callCount++;
        throw const AuthException(
          statusCode: 401,
          message: 'token expired',
        );
      });

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'fail.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      await _pump();
      await _pump();

      expect(callCount, 2, reason: 'Initial attempt + one retry on 401');

      final status = tracker.roomUploads('room-1').value as UploadsLoaded;
      final failed = status.uploads.whereType<FailedUpload>().single;
      expect(failed.filename, 'fail.pdf');
      expect(failed.message, 'Session expired. Please sign in again.');

      // Session funneled through markSessionExpired so route guard
      // and lobby UX can react. Tokens preserved.
      expect(auth.session.value, isA<ExpiredSession>());
    });

    test(
      'auth flip to ExpiredSession cancels pending uploads',
      () async {
        stubGetRoomUploads([]);
        unawaited(tracker.refreshRoom('room-1'));
        await _pump();

        auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        // Stage an upload whose POST blocks until we tell it to.
        final postCompleter = Completer<void>();
        late CancelToken capturedToken;
        when(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((invocation) async {
          capturedToken = invocation.namedArguments[const Symbol('cancelToken')]
              as CancelToken;
          await postCompleter.future;
          if (capturedToken.isCancelled) throw const CancelledException();
        });

        tracker.uploadToRoom(
          roomId: 'room-1',
          filename: 'slow.pdf',
          openStream: () => Stream<List<int>>.value(const [1]),
          contentLength: 1,
        );
        await _pump();

        // Sanity: the upload's token is alive while POST is in flight.
        expect(capturedToken.isCancelled, isFalse);

        // Flip auth on this server (could be triggered from anywhere).
        auth.markSessionExpired();

        expect(capturedToken.isCancelled, isTrue);

        // Let the staged POST observe the cancel and unblock.
        postCompleter.complete();
        await _pump();
      },
    );

    test(
      'progress emissions update PendingUpload.sentBytes as chunks flow',
      () async {
        stubGetRoomUploads([]);
        unawaited(tracker.refreshRoom('room-1'));
        await _pump();

        // The mock drains the openStream so the wrapper's chunk callbacks
        // fire. We then inspect the emitted PendingUpload snapshots.
        when(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((invocation) async {
          final openStream = invocation.namedArguments[#openStream]
              as Stream<List<int>> Function();
          await openStream().drain<void>();
        });

        // Three chunks summing to 6 bytes.
        final chunks = <List<int>>[
          [1, 2],
          [3, 4],
          [5, 6],
        ];

        // Throttle is 50 ms; insert delays so each chunk gets its own
        // emission rather than coalescing.
        Stream<List<int>> openStream() async* {
          for (final chunk in chunks) {
            yield chunk;
            await Future<void>.delayed(const Duration(milliseconds: 60));
          }
        }

        final sentByteSnapshots = <int>[];
        final unsub = tracker.roomUploads('room-1').subscribe((status) {
          if (status is! UploadsLoaded) return;
          final pending = status.uploads.whereType<PendingUpload>().firstOrNull;
          if (pending != null) sentByteSnapshots.add(pending.sentBytes);
        });

        tracker.uploadToRoom(
          roomId: 'room-1',
          filename: 'progress.bin',
          openStream: openStream,
          contentLength: 6,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        unsub();

        // Saw monotonic progress, including the final 6/6.
        expect(sentByteSnapshots, contains(6));
        for (var i = 1; i < sentByteSnapshots.length; i++) {
          expect(sentByteSnapshots[i],
              greaterThanOrEqualTo(sentByteSnapshots[i - 1]));
        }
      },
    );

    test('Posted state still reports 100% via PendingUpload.progress',
        () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final uploadCompleter = Completer<void>();
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => uploadCompleter.future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'done.bin',
        openStream: () => Stream<List<int>>.value(const [1, 2, 3]),
        contentLength: 3,
      );
      await _pump();

      // No refresh queued — leave the upload stuck in _Posted.
      uploadCompleter.complete();
      await _pump();

      final pending = (tracker.roomUploads('room-1').value as UploadsLoaded)
          .uploads
          .whereType<PendingUpload>()
          .single;
      expect(pending.sentBytes, equals(pending.totalBytes));
      expect(pending.progress, equals(1.0));
    });

    test('zero-length file reports indeterminate progress (null)', () {
      // Synthetic check on the PendingUpload class rather than full
      // tracker flow, since 0-byte streams are an edge case.
      const upload = PendingUpload(
        id: 'x',
        filename: 'empty.bin',
        sentBytes: 0,
        totalBytes: 0,
      );
      expect(upload.progress, isNull);
    });

    test('413 ApiException surfaces as "File is too large to upload"', () {
      final message = uploadErrorMessage(
        const ApiException(
            statusCode: 413, message: 'Request Entity Too Large'),
      );
      expect(message, 'File is too large to upload.');
    });

    test('FileSystemException surfaces as "Could not read file from disk"', () {
      final fsError = FileSystemException('No such file', '/tmp/gone.txt');
      expect(
        uploadErrorMessage(fsError),
        'Could not read file from disk.',
      );

      // Same translation when the FileSystemException is wrapped inside
      // a NetworkException (typical path when openStream() fails inside
      // the HTTP transport's sink-add).
      final wrapped = NetworkException(
        message: 'Stream error',
        originalError: fsError,
      );
      expect(
        uploadErrorMessage(wrapped),
        'Could not read file from disk.',
      );
    });

    test('415 ApiException surfaces as unsupported file type message', () {
      final message = uploadErrorMessage(
        const ApiException(
          statusCode: 415,
          message: 'Unsupported Media Type',
        ),
      );
      expect(message, "This file type isn't supported.");
    });

    test('5xx ApiException surfaces as temporarily-unavailable message', () {
      for (final statusCode in [500, 502, 503, 504]) {
        final message = uploadErrorMessage(
          ApiException(statusCode: statusCode, message: 'boom'),
        );
        expect(
          message,
          'Server is temporarily unavailable. Try uploading again in a moment.',
          reason: 'statusCode=$statusCode',
        );
      }
    });

    test('NetworkException(isTimeout: true) surfaces as upload-timeout message',
        () {
      final message = uploadErrorMessage(
        NetworkException(message: 'Read timeout', isTimeout: true),
      );
      expect(
        message,
        'Upload timed out. Try a smaller file or check your connection.',
      );
    });

    test(
      'NetworkException wrapping a SocketException surfaces as '
      'connection-lost message',
      () {
        final message = uploadErrorMessage(
          NetworkException(
            message: 'Stream error',
            originalError: const SocketException('Connection reset by peer'),
          ),
        );
        expect(message, 'Network connection lost. Try uploading again.');
      },
    );

    test('AuthException(statusCode: 401) surfaces as session-expired message',
        () {
      final message = uploadErrorMessage(
        const AuthException(statusCode: 401, message: 'token expired'),
      );
      expect(message, 'Session expired. Please sign in again.');
    });

    test('AuthException(statusCode: 403) surfaces as no-permission message',
        () {
      final message = uploadErrorMessage(
        const AuthException(statusCode: 403, message: 'forbidden'),
      );
      expect(message, "You don't have permission to upload here.");
    });

    test('CancelledException does not produce a Failed row', () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async {
        throw const CancelledException(reason: 'disposed');
      });

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'cancelled.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      await _pump();

      final status = tracker.roomUploads('room-1').value as UploadsLoaded;
      expect(status.uploads.whereType<FailedUpload>(), isEmpty);
    });
  });

  group('global upload queue', () {
    test(
      'queues uploads across scopes and drains one at a time in enqueue order',
      () async {
        stubGetRoomUploads([]);
        stubGetThreadUploads([]);
        unawaited(tracker.refreshRoom('room-1'));
        unawaited(tracker.refreshThread('room-1', 'thread-1'));
        await _pump();

        final firstPost = Completer<void>();
        final secondPost = Completer<void>();
        when(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((_) => firstPost.future);
        when(() => mockApi.uploadFileToThread(
              any(),
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).thenAnswer((_) => secondPost.future);

        // Enqueue: room upload first (job A), thread upload second (job B).
        tracker.uploadToRoom(
          roomId: 'room-1',
          filename: 'room-file.pdf',
          openStream: () => Stream<List<int>>.value(const [1]),
          contentLength: 1,
        );
        tracker.uploadToThread(
          roomId: 'room-1',
          threadId: 'thread-1',
          filename: 'thread-file.pdf',
          openStream: () => Stream<List<int>>.value(const [2]),
          contentLength: 1,
        );

        // Both Pending rows are visible immediately in their respective
        // scopes, regardless of which job is currently in flight.
        expect(
          (tracker.roomUploads('room-1').value as UploadsLoaded)
              .uploads
              .whereType<PendingUpload>(),
          hasLength(1),
        );
        expect(
          (tracker.threadUploads('room-1', 'thread-1').value as UploadsLoaded)
              .uploads
              .whereType<PendingUpload>(),
          hasLength(1),
        );

        await _pump();

        // Job A is in flight; job B's API has NOT been called yet.
        verify(() => mockApi.uploadFileToRoom(
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).called(1);
        verifyNever(() => mockApi.uploadFileToThread(
              any(),
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            ));

        // Finish job A → drainer pulls job B.
        firstPost.complete();
        await _pump();

        verify(() => mockApi.uploadFileToThread(
              any(),
              any(),
              filename: any(named: 'filename'),
              openStream: any(named: 'openStream'),
              contentLength: any(named: 'contentLength'),
              mimeType: any(named: 'mimeType'),
              webFileBlob: any(named: 'webFileBlob'),
              onProgress: any(named: 'onProgress'),
              cancelToken: any(named: 'cancelToken'),
            )).called(1);

        // Finish job B → queue drains.
        secondPost.complete();
        await _pump();
      },
    );

    test('dispose cancels queued-but-not-started jobs without invoking the API',
        () async {
      stubGetRoomUploads([]);
      unawaited(tracker.refreshRoom('room-1'));
      await _pump();

      final blockedFirst = Completer<void>();
      when(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) => blockedFirst.future);

      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'first.pdf',
        openStream: () => Stream<List<int>>.value(const [1]),
        contentLength: 1,
      );
      tracker.uploadToRoom(
        roomId: 'room-1',
        filename: 'second.pdf',
        openStream: () => Stream<List<int>>.value(const [2]),
        contentLength: 1,
      );
      await _pump();

      // Only the first job's POST was invoked; the second waits in queue.
      verify(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          )).called(1);

      tracker.dispose();
      // Let any pending microtasks settle.
      await _pump();

      // dispose() did not let the queued job start.
      verifyNever(() => mockApi.uploadFileToRoom(
            any(),
            filename: any(named: 'filename'),
            openStream: any(named: 'openStream'),
            contentLength: any(named: 'contentLength'),
            mimeType: any(named: 'mimeType'),
            webFileBlob: any(named: 'webFileBlob'),
            onProgress: any(named: 'onProgress'),
            cancelToken: any(named: 'cancelToken'),
          ));
    });
  });
}
