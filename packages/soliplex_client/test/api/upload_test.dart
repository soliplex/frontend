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
}
