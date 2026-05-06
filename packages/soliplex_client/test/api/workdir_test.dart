import 'dart:typed_data';

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

  group('getRunWorkdirFiles', () {
    test('returns WorkdirFile entries from server payload', () async {
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
          'thread_id': 'thread-456',
          'run_id': 'run-789',
          'files': [
            {
              'filename': 'output.csv',
              'url': 'https://example.test/output.csv',
            },
            {
              'filename': 'plot.png',
              'url': 'https://example.test/plot.png',
            },
          ],
        },
      );

      final files = await api.getRunWorkdirFiles(
        'room-123',
        'thread-456',
        'run-789',
      );

      expect(files, hasLength(2));
      expect(files[0].filename, 'output.csv');
      expect(files[0].url, Uri.parse('https://example.test/output.csv'));
      expect(files[1].filename, 'plot.png');
      expect(files[1].url, Uri.parse('https://example.test/plot.png'));
    });

    test('returns empty list when files array is empty', () async {
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
          'thread_id': 'thread-456',
          'run_id': 'run-789',
          'files': <dynamic>[],
        },
      );

      expect(
        await api.getRunWorkdirFiles('room-123', 'thread-456', 'run-789'),
        isEmpty,
      );
    });

    test('returns empty list when files field is missing', () async {
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
        (_) async => {'room_id': 'room-123'},
      );

      expect(
        await api.getRunWorkdirFiles('room-123', 'thread-456', 'run-789'),
        isEmpty,
      );
    });

    test('throws UnexpectedException when files field is not a list', () async {
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
        (_) async => {'room_id': 'room-123', 'files': 'not-a-list'},
      );

      await expectLater(
        api.getRunWorkdirFiles('room-123', 'thread-456', 'run-789'),
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
          'files': [
            {
              'filename': 'good.csv',
              'url': 'https://example.test/good.csv',
            },
            {
              'filename': '',
              'url': 'https://example.test/empty',
            },
            {
              'filename': 'sub/file.txt',
              'url': 'https://example.test/sub.txt',
            },
            {
              'filename': 'no-url.csv',
            },
            <String, dynamic>{},
            'not a map',
            {
              'filename': 'also-good.csv',
              'url': 'https://example.test/also-good.csv',
            },
          ],
        },
      );

      final files =
          await api.getRunWorkdirFiles('room-123', 'thread-456', 'run-789');

      expect(files.map((f) => f.filename), ['good.csv', 'also-good.csv']);
    });

    test('uses /workdirs/{roomId}/thread/{threadId}/{runId} URL', () async {
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

      await api.getRunWorkdirFiles('room-abc', 'thread-xyz', 'run-999');

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

      expect(
        captured.path,
        endsWith('/workdirs/room-abc/thread/thread-xyz/run-999'),
      );
    });

    test('throws ArgumentError for empty roomId', () {
      expect(
        () => api.getRunWorkdirFiles('', 'thread-1', 'run-1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty threadId', () {
      expect(
        () => api.getRunWorkdirFiles('room-1', '', 'run-1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty runId', () {
      expect(
        () => api.getRunWorkdirFiles('room-1', 'thread-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('getRunWorkdirFile', () {
    test('returns the response bytes verbatim', () async {
      final payload = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      when(
        () => mockTransport.requestBytes(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => payload);

      final bytes = await api.getRunWorkdirFile(
        'room-123',
        'thread-456',
        'run-789',
        'output.bin',
      );

      expect(bytes, equals(payload));
    });

    test(
      'uses /workdirs/{roomId}/thread/{threadId}/run/{runId}/file/{filename} URL',
      () async {
        when(
          () => mockTransport.requestBytes(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => Uint8List(0));

        await api.getRunWorkdirFile(
          'room-abc',
          'thread-xyz',
          'run-999',
          'plot.png',
        );

        final captured = verify(
          () => mockTransport.requestBytes(
            'GET',
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).captured.single as Uri;

        expect(
          captured.path,
          endsWith(
            '/workdirs/room-abc/thread/thread-xyz/run/run-999/file/plot.png',
          ),
        );
      },
    );

    test('percent-encodes filenames with spaces and special characters',
        () async {
      when(
        () => mockTransport.requestBytes(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Uint8List(0));

      await api.getRunWorkdirFile(
        'room-1',
        'thread-1',
        'run-1',
        'my report (final).pdf',
      );

      final captured = verify(
        () => mockTransport.requestBytes(
          'GET',
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured.single as Uri;

      expect(captured.pathSegments.last, equals('my report (final).pdf'));
    });

    test(
        'percent-encodes ? and # in filenames so they cannot inject query '
        'or fragment', () async {
      when(
        () => mockTransport.requestBytes(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Uint8List(0));

      await api.getRunWorkdirFile(
        'room-1',
        'thread-1',
        'run-1',
        'a?b#c.txt',
      );

      final captured = verify(
        () => mockTransport.requestBytes(
          'GET',
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured.single as Uri;

      expect(captured.pathSegments.last, equals('a?b#c.txt'));
      expect(captured.query, isEmpty);
      expect(captured.fragment, isEmpty);
      expect(captured.toString(), contains('a%3Fb%23c.txt'));
    });

    test('propagates exceptions from the transport', () async {
      when(
        () => mockTransport.requestBytes(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async {
        throw const NotFoundException(
          message: 'No workdir file',
          resource: '/file',
        );
      });

      await expectLater(
        api.getRunWorkdirFile('room-1', 'thread-1', 'run-1', 'missing.txt'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('throws ArgumentError for empty roomId', () {
      expect(
        () => api.getRunWorkdirFile('', 'thread-1', 'run-1', 'a.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty threadId', () {
      expect(
        () => api.getRunWorkdirFile('room-1', '', 'run-1', 'a.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty runId', () {
      expect(
        () => api.getRunWorkdirFile('room-1', 'thread-1', '', 'a.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty filename', () {
      expect(
        () => api.getRunWorkdirFile('room-1', 'thread-1', 'run-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
