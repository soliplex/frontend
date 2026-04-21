import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

void main() {
  late MockHttpTransport mockTransport;
  late SoliplexApi api;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockTransport = MockHttpTransport();
    api = SoliplexApi(
      transport: mockTransport,
      urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
    );
    when(() => mockTransport.close()).thenReturn(null);
  });

  tearDown(() {
    api.close();
    reset(mockTransport);
  });

  group('uploadFileToRoom', () {
    test('sends multipart POST to /uploads/{roomId}', () async {
      when(
        () => mockTransport.request<void>(
          any(),
          any(),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {});

      final fileBytes = utf8.encode('file content');

      await api.uploadFileToRoom(
        'room-123',
        filename: 'test.txt',
        fileBytes: fileBytes,
      );

      final captured = verify(
        () => mockTransport.request<void>(
          'POST',
          captureAny(),
          body: captureAny(named: 'body'),
          headers: captureAny(named: 'headers'),
        ),
      ).captured;

      final uri = captured[0] as Uri;
      expect(uri.path, contains('/uploads/room-123'));

      final body = captured[1] as List<int>;
      final bodyString = utf8.decode(body);
      expect(bodyString, contains('name="upload_file"'));
      expect(bodyString, contains('filename="test.txt"'));
      expect(bodyString, contains('file content'));

      final headers = captured[2] as Map<String, String>;
      expect(
        headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
    });
  });

  group('uploadFileToThread', () {
    test('sends multipart POST to /uploads/{roomId}/{threadId}', () async {
      when(
        () => mockTransport.request<void>(
          any(),
          any(),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {});

      final fileBytes = utf8.encode('thread file');

      await api.uploadFileToThread(
        'room-123',
        'thread-456',
        filename: 'report.pdf',
        fileBytes: fileBytes,
      );

      final captured = verify(
        () => mockTransport.request<void>(
          'POST',
          captureAny(),
          body: captureAny(named: 'body'),
          headers: captureAny(named: 'headers'),
        ),
      ).captured;

      final uri = captured[0] as Uri;
      expect(uri.path, contains('/uploads/room-123/thread-456'));

      final body = captured[1] as List<int>;
      final bodyString = utf8.decode(body);
      expect(bodyString, contains('filename="report.pdf"'));
      expect(bodyString, contains('thread file'));

      final headers = captured[2] as Map<String, String>;
      expect(
        headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
    });
  });

  group('getRoomUploads', () {
    test('returns FileUpload entries from server payload', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => {
          'room_id': 'room-123',
          'uploads': [
            {
              'filename': 'a.pdf',
              'url': 'https://example.com/uploads/room-123/a.pdf',
            },
            {
              'filename': 'b.txt',
              'url': 'https://example.com/uploads/room-123/b.txt',
            },
          ],
        },
      );

      final uploads = await api.getRoomUploads('room-123');

      expect(uploads, hasLength(2));
      expect(uploads[0].filename, 'a.pdf');
      expect(
        uploads[0].url.toString(),
        'https://example.com/uploads/room-123/a.pdf',
      );
      expect(uploads[1].filename, 'b.txt');
    });

    test('returns empty list when uploads array is empty', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => {'room_id': 'room-123', 'uploads': <dynamic>[]},
      );

      expect(await api.getRoomUploads('room-123'), isEmpty);
    });

    test('returns empty list when uploads field is missing', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => {'room_id': 'room-123'});

      expect(await api.getRoomUploads('room-123'), isEmpty);
    });

    test('throws UnexpectedException when uploads field is not a list',
        () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => {'room_id': 'room-123', 'uploads': 'not-a-list'},
      );

      await expectLater(
        api.getRoomUploads('room-123'),
        throwsA(isA<UnexpectedException>()),
      );
    });

    test('skips malformed entries and returns valid ones', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => {
          'room_id': 'room-123',
          'uploads': [
            {'filename': 'good.pdf', 'url': 'https://example.com/good'},
            {'filename': 'missing-url'},
            'not a map',
            {
              'filename': 'also-good.pdf',
              'url': 'https://example.com/good2',
            },
          ],
        },
      );

      final uploads = await api.getRoomUploads('room-123');

      expect(uploads.map((u) => u.filename), ['good.pdf', 'also-good.pdf']);
    });

    test('uses /uploads/{roomId} URL', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await api.getRoomUploads('room-abc');

      final captured = verify(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured.single as Uri;

      expect(captured.path, endsWith('/uploads/room-abc'));
    });

    test('throws ArgumentError for empty roomId', () {
      expect(() => api.getRoomUploads(''), throwsA(isA<ArgumentError>()));
    });
  });

  group('getThreadUploads', () {
    test('returns FileUpload entries from server payload', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => {
          'room_id': 'room-123',
          'uploads': [
            {
              'filename': 'thread.pdf',
              'url':
                  'https://example.com/uploads/room-123/thread-456/thread.pdf',
            },
          ],
        },
      );

      final uploads = await api.getThreadUploads('room-123', 'thread-456');

      expect(uploads, hasLength(1));
      expect(uploads.first.filename, 'thread.pdf');
    });

    test('uses /uploads/{roomId}/thread/{threadId} URL', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await api.getThreadUploads('room-abc', 'thread-xyz');

      final captured = verify(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured.single as Uri;

      expect(captured.path, endsWith('/uploads/room-abc/thread/thread-xyz'));
    });

    test('throws ArgumentError for empty roomId', () {
      expect(
        () => api.getThreadUploads('', 'thread-1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty threadId', () {
      expect(
        () => api.getThreadUploads('room-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
