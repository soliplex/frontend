import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

void main() {
  late MockSoliplexApi mockApi;
  late UploadTracker tracker;

  setUp(() {
    mockApi = MockSoliplexApi();
    tracker = UploadTracker();
  });

  tearDown(() {
    tracker.dispose();
  });

  group('uploadToRoom', () {
    test('tracks upload lifecycle: uploading then success', () async {
      final completer = Completer<void>();

      when(
        () => mockApi.uploadFileToRoom(
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) => completer.future);

      tracker.uploadToRoom(
        api: mockApi,
        roomId: 'room-1',
        filename: 'test.txt',
        fileBytes: utf8.encode('content'),
      );

      // Immediately in uploading state
      final entries = tracker.roomUploads('room-1').value;
      expect(entries, hasLength(1));
      expect(entries.first.filename, 'test.txt');
      expect(entries.first.status, isA<UploadUploading>());

      // Complete the upload
      completer.complete();
      await Future<void>.delayed(Duration.zero);

      final updated = tracker.roomUploads('room-1').value;
      expect(updated.first.status, isA<UploadSuccess>());
    });

    test('tracks upload error from API exception', () async {
      when(
        () => mockApi.uploadFileToRoom(
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async =>
            throw const ApiException(statusCode: 500, message: 'Server error'),
      );

      tracker.uploadToRoom(
        api: mockApi,
        roomId: 'room-1',
        filename: 'fail.txt',
        fileBytes: [0],
      );

      await Future<void>.delayed(Duration.zero);

      final entries = tracker.roomUploads('room-1').value;
      expect(entries, hasLength(1));
      expect(entries.first.status, isA<UploadError>());
      expect(
        (entries.first.status as UploadError).message,
        contains('Server error'),
      );
    });

    test('tracks upload error from network exception', () async {
      when(
        () => mockApi.uploadFileToRoom(
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => throw NetworkException(message: 'Connection refused'),
      );

      tracker.uploadToRoom(
        api: mockApi,
        roomId: 'room-1',
        filename: 'fail.txt',
        fileBytes: [0],
      );

      await Future<void>.delayed(Duration.zero);

      final entries = tracker.roomUploads('room-1').value;
      expect(entries, hasLength(1));
      expect(entries.first.status, isA<UploadError>());
      expect(
        (entries.first.status as UploadError).message,
        contains('Connection refused'),
      );
    });
  });

  group('uploadToThread', () {
    test('tracks upload lifecycle: uploading then success', () async {
      final completer = Completer<void>();

      when(
        () => mockApi.uploadFileToThread(
          any(),
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) => completer.future);

      tracker.uploadToThread(
        api: mockApi,
        roomId: 'room-1',
        threadId: 'thread-1',
        filename: 'report.pdf',
        fileBytes: [0],
      );

      final entries = tracker.threadUploads('room-1', 'thread-1').value;
      expect(entries, hasLength(1));
      expect(entries.first.filename, 'report.pdf');
      expect(entries.first.status, isA<UploadUploading>());

      completer.complete();
      await Future<void>.delayed(Duration.zero);

      final updated = tracker.threadUploads('room-1', 'thread-1').value;
      expect(updated.first.status, isA<UploadSuccess>());
    });
  });

  group('dismiss', () {
    test('removes entry from list', () async {
      when(
        () => mockApi.uploadFileToRoom(
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async {});

      tracker.uploadToRoom(
        api: mockApi,
        roomId: 'room-1',
        filename: 'test.txt',
        fileBytes: [0],
      );

      await Future<void>.delayed(Duration.zero);

      final entries = tracker.roomUploads('room-1').value;
      expect(entries, hasLength(1));

      tracker.dismiss(entries.first.id);

      final updated = tracker.roomUploads('room-1').value;
      expect(updated, isEmpty);
    });
  });

  group('scoping', () {
    test('room uploads are scoped per room', () async {
      when(
        () => mockApi.uploadFileToRoom(
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async {});

      tracker.uploadToRoom(
        api: mockApi,
        roomId: 'room-1',
        filename: 'a.txt',
        fileBytes: [0],
      );
      tracker.uploadToRoom(
        api: mockApi,
        roomId: 'room-2',
        filename: 'b.txt',
        fileBytes: [0],
      );

      expect(tracker.roomUploads('room-1').value, hasLength(1));
      expect(tracker.roomUploads('room-2').value, hasLength(1));
      expect(tracker.roomUploads('room-1').value.first.filename, 'a.txt');
    });

    test('thread uploads are scoped per room+thread', () async {
      when(
        () => mockApi.uploadFileToThread(
          any(),
          any(),
          filename: any(named: 'filename'),
          fileBytes: any(named: 'fileBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async {});

      tracker.uploadToThread(
        api: mockApi,
        roomId: 'room-1',
        threadId: 'thread-1',
        filename: 'a.txt',
        fileBytes: [0],
      );
      tracker.uploadToThread(
        api: mockApi,
        roomId: 'room-1',
        threadId: 'thread-2',
        filename: 'b.txt',
        fileBytes: [0],
      );

      expect(tracker.threadUploads('room-1', 'thread-1').value, hasLength(1));
      expect(tracker.threadUploads('room-1', 'thread-2').value, hasLength(1));
    });
  });
}
