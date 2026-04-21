import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/ui/upload_event_banner.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

class _MockApi extends Mock implements SoliplexApi {}

FileUpload _persisted(String filename, [String? url]) {
  return FileUpload(
    filename: filename,
    url: Uri.parse(url ?? 'https://example.com/$filename'),
  );
}

void main() {
  late _MockApi api;
  late UploadTracker tracker;

  setUpAll(() {
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    api = _MockApi();
    tracker = UploadTracker(api: api);

    // Defaults: empty server lists, uploads succeed. Individual tests
    // override as needed.
    when(
      () => api.getRoomUploads(
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => const <FileUpload>[]);
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => const <FileUpload>[]);
    when(
      () => api.uploadFileToThread(
        any(),
        any(),
        filename: any(named: 'filename'),
        fileBytes: any(named: 'fileBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() {
    tracker.dispose();
    reset(api);
  });

  Widget frame(String roomId, String? threadId) {
    return MaterialApp(
      home: Scaffold(
        body: UploadEventBanner(
          tracker: tracker,
          roomId: roomId,
          threadId: threadId,
        ),
      ),
    );
  }

  testWidgets('completion fires success pill with filename', (tester) async {
    await tester.pumpWidget(frame('room-1', 'thread-1'));

    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'b.pdf',
      fileBytes: const [1, 2, 3],
    );
    // POST resolves; refresh now returns the new file.
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => [_persisted('b.pdf')]);

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Uploaded b.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('failure fires failure pill with message', (tester) async {
    when(
      () => api.uploadFileToThread(
        any(),
        any(),
        filename: any(named: 'filename'),
        fileBytes: any(named: 'fileBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenThrow(const NetworkException(message: 'wifi down'));

    await tester.pumpWidget(frame('room-1', 'thread-1'));
    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'b.pdf',
      fileBytes: const [1, 2, 3],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Failed to upload b.pdf'), findsOneWidget);
    expect(find.textContaining('wifi down'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('success pill auto-dismisses after 4s', (tester) async {
    await tester.pumpWidget(frame('room-1', 'thread-1'));
    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'b.pdf',
      fileBytes: const [1, 2, 3],
    );
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => [_persisted('b.pdf')]);

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Uploaded b.pdf'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Uploaded b.pdf'), findsNothing);
  });

  testWidgets('failure pill does NOT auto-dismiss', (tester) async {
    when(
      () => api.uploadFileToThread(
        any(),
        any(),
        filename: any(named: 'filename'),
        fileBytes: any(named: 'fileBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenThrow(const NetworkException(message: 'wifi down'));

    await tester.pumpWidget(frame('room-1', 'thread-1'));
    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'b.pdf',
      fileBytes: const [1, 2, 3],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Failed to upload b.pdf'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.textContaining('Failed to upload b.pdf'), findsOneWidget);
  });

  testWidgets('X dismisses success and failure pills independently',
      (tester) async {
    // First upload succeeds, second fails.
    var uploadCallCount = 0;
    when(
      () => api.uploadFileToThread(
        any(),
        any(),
        filename: any(named: 'filename'),
        fileBytes: any(named: 'fileBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async {
      uploadCallCount++;
      if (uploadCallCount == 2) {
        throw const NetworkException(message: 'wifi down');
      }
    });

    await tester.pumpWidget(frame('room-1', 'thread-1'));
    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'a.pdf',
      fileBytes: const [1],
    );
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => [_persisted('a.pdf')]);
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'bad.pdf',
      fileBytes: const [2],
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Uploaded a.pdf'), findsOneWidget);
    expect(find.textContaining('Failed to upload bad.pdf'), findsOneWidget);

    final successCloseFinder = find.descendant(
      of: find.ancestor(
        of: find.text('Uploaded a.pdf'),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(successCloseFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Uploaded a.pdf'), findsNothing);
    expect(find.textContaining('Failed to upload bad.pdf'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Failed to upload bad.pdf'), findsNothing);
  });

  testWidgets('scope switch does not fire pill for pre-existing failed',
      (tester) async {
    when(
      () => api.uploadFileToThread(
        any(),
        any(),
        filename: any(named: 'filename'),
        fileBytes: any(named: 'fileBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenThrow(const NetworkException(message: 'prior'));

    unawaited(tracker.refreshThread('room-1', 'thread-A'));
    // Drain the refresh microtask queue without a widget binding: use
    // pumpEventQueue via pumpWidget + pump to create a bound context.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-A',
      filename: 'old.pdf',
      fileBytes: const [1],
    );
    await tester.pump();
    await tester.pump();

    // Now mount the banner for thread-A — it should see pre-existing
    // FailedUpload as baseline, not a transition.
    await tester.pumpWidget(frame('room-1', 'thread-A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Failed to upload old.pdf'), findsNothing);

    // Switch to thread-B.
    await tester.pumpWidget(frame('room-1', 'thread-B'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Failed'), findsNothing);
    expect(find.textContaining('Uploaded'), findsNothing);
  });

  testWidgets('scope switch mid-success drops the pending timer',
      (tester) async {
    await tester.pumpWidget(frame('room-1', 'thread-A'));
    unawaited(tracker.refreshThread('room-1', 'thread-A'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-A',
      filename: 'a.pdf',
      fileBytes: const [1],
    );
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => [_persisted('a.pdf')]);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Uploaded a.pdf'), findsOneWidget);

    // Switch scope 1s into the 4s auto-dismiss window.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(frame('room-1', 'thread-B'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Pill for thread-A is gone; thread-B shows nothing.
    expect(find.text('Uploaded a.pdf'), findsNothing);

    // Advance past where the original timer would have fired.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // Still nothing — the cancelled timer didn't resurrect anything.
    expect(find.textContaining('Uploaded'), findsNothing);
    expect(find.textContaining('Failed'), findsNothing);
  });

  testWidgets('success aggregation shows first + count', (tester) async {
    await tester.pumpWidget(frame('room-1', 'thread-1'));
    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'a.pdf',
      fileBytes: const [1],
    );
    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'b.pdf',
      fileBytes: const [2],
    );
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => [_persisted('a.pdf'), _persisted('b.pdf')]);

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('and 1 more'), findsOneWidget);
  });

  testWidgets('both pills render when a failure and a success coexist',
      (tester) async {
    var uploadCallCount = 0;
    when(
      () => api.uploadFileToThread(
        any(),
        any(),
        filename: any(named: 'filename'),
        fileBytes: any(named: 'fileBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async {
      uploadCallCount++;
      if (uploadCallCount == 1) {
        throw const NetworkException(message: 'bad');
      }
    });

    await tester.pumpWidget(frame('room-1', 'thread-1'));
    unawaited(tracker.refreshThread('room-1', 'thread-1'));
    await tester.pump();
    await tester.pump();

    // Fail first.
    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'bad.pdf',
      fileBytes: const [1],
    );
    await tester.pump();
    await tester.pump();

    // Then succeed.
    tracker.uploadToThread(
      roomId: 'room-1',
      threadId: 'thread-1',
      filename: 'good.pdf',
      fileBytes: const [2],
    );
    when(
      () => api.getThreadUploads(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => [_persisted('good.pdf')]);

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Uploaded good.pdf'), findsOneWidget);
    expect(find.textContaining('Failed to upload bad.pdf'), findsOneWidget);
  });
}
