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
              'url':
                  'https://example.com/workdirs/room-123/thread-456/run-789/output.csv',
            },
            {
              'filename': 'plot.png',
              'url':
                  'https://example.com/workdirs/room-123/thread-456/run-789/plot.png',
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
      expect(
        files[0].url.toString(),
        'https://example.com/workdirs/room-123/thread-456/run-789/output.csv',
      );
      expect(files[1].filename, 'plot.png');
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
            {'filename': 'good.csv', 'url': 'https://example.com/good'},
            {'filename': 'missing-url'},
            'not a map',
            {'filename': 'also-good.csv', 'url': 'https://example.com/good2'},
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
}
