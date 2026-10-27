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

  void stubListing(Map<String, dynamic> payload) {
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
    ).thenAnswer((_) async => payload);
  }

  void stubBytes(Future<Uint8List> Function() answer) {
    when(
      () => mockTransport.requestBytes(
        'GET',
        any(),
        cancelToken: any(named: 'cancelToken'),
        headers: any(named: 'headers'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer((_) => answer());
  }

  Uri capturedBytesUri() => verify(
        () => mockTransport.requestBytes(
          'GET',
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured.single as Uri;

  group('getThreadWorkdirFiles', () {
    test('returns WorkdirFile entries from server payload', () async {
      stubListing({
        'room_id': 'room-123',
        'thread_id': 'thread-456',
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
      });

      final files = await api.getThreadWorkdirFiles('room-123', 'thread-456');

      expect(files, hasLength(2));
      expect(files[0].filename, 'output.csv');
      expect(files[0].url, Uri.parse('https://example.test/output.csv'));
      expect(files[1].filename, 'plot.png');
      expect(files[1].url, Uri.parse('https://example.test/plot.png'));
    });

    test('returns empty list when files array is empty', () async {
      stubListing({
        'room_id': 'room-123',
        'thread_id': 'thread-456',
        'files': <dynamic>[],
      });

      final files = await api.getThreadWorkdirFiles('room-123', 'thread-456');

      expect(files, isEmpty);
    });

    test('returns empty list when files field is missing', () async {
      stubListing({'room_id': 'room-123'});

      final files = await api.getThreadWorkdirFiles('room-123', 'thread-456');

      expect(files, isEmpty);
    });

    test('throws UnexpectedException when files field is not a list', () async {
      stubListing({'room_id': 'room-123', 'files': 'not-a-list'});

      await expectLater(
        api.getThreadWorkdirFiles('room-123', 'thread-456'),
        throwsA(isA<UnexpectedException>()),
      );
    });

    test('skips malformed entries and returns valid ones', () async {
      stubListing({
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
            'filename': 'sub/../file.txt',
            'url': 'https://example.test/sub.txt',
          },
          {
            'filename': 'dir/file.txt',
            'url': 'https://example.test/dir/file.txt',
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
      });

      final files = await api.getThreadWorkdirFiles('room-123', 'thread-456');

      expect(
        files.map((f) => f.filename),
        ['good.csv', 'dir/file.txt', 'also-good.csv'],
      );
    });

    test(
        'warns of a skipped entry with its room, thread, value and reason, '
        "without a parser's source window", () async {
      final warnings = <String>[];
      final warningApi = SoliplexApi(
        transport: mockTransport,
        urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
        onWarning: warnings.add,
      );
      stubListing({
        'files': [
          {'filename': 'dir/../file.txt', 'url': 'https://example.test/a'},
          // Uri.parse fails on the port.
          {'filename': 'file.txt', 'url': 'https://example.test:port/b'},
        ],
      });

      await warningApi.getThreadWorkdirFiles('room-123', 'thread-456');

      expect(warnings, hasLength(2));
      for (final warning in warnings) {
        expect(warning, contains('roomId=room-123'));
        expect(warning, contains('threadId=thread-456'));
      }
      expect(warnings.first, contains('dir/../file.txt'));
      expect(warnings.last, contains('https://example.test:port/b'));
      expect(warnings.last, contains('Invalid port'));
      // Not the multi-line source window FormatException.toString() draws.
      expect(warnings, everyElement(isNot(contains('\n'))));
    });

    test('uses /workdirs/{roomId}/thread/{threadId} URL', () async {
      stubListing(<String, dynamic>{});

      await api.getThreadWorkdirFiles('room-abc', 'thread-xyz');

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

      expect(captured.path, endsWith('/workdirs/room-abc/thread/thread-xyz'));
    });

    test('throws ArgumentError for empty roomId', () {
      expect(
        () => api.getThreadWorkdirFiles('', 'thread-1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty threadId', () {
      expect(
        () => api.getThreadWorkdirFiles('room-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('getThreadWorkdirFile', () {
    test('returns the response bytes verbatim', () async {
      final payload = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      stubBytes(() async => payload);

      final bytes = await api.getThreadWorkdirFile(
        'room-123',
        'thread-456',
        'output.bin',
      );

      expect(bytes, equals(payload));
    });

    test('uses /workdirs/{roomId}/thread/{threadId}/file/{filename} URL',
        () async {
      stubBytes(() async => Uint8List(0));

      await api.getThreadWorkdirFile('room-1', 'thread-1', 'out.csv');

      final captured = capturedBytesUri();

      expect(
        captured.path,
        endsWith('/workdirs/room-1/thread/thread-1/file/out.csv'),
      );
    });

    test('sends a nested filename as separate path segments', () async {
      // A proxy may reject or rewrite an encoded '%2F', so each directory
      // must travel as its own segment.
      stubBytes(() async => Uint8List(0));

      await api.getThreadWorkdirFile('room-1', 'thread-1', 'dir/file.txt');

      expect(
        capturedBytesUri().path,
        endsWith('/workdirs/room-1/thread/thread-1/file/dir/file.txt'),
      );
    });

    test('percent-encodes filenames with spaces and special characters',
        () async {
      stubBytes(() async => Uint8List(0));

      await api.getThreadWorkdirFile(
        'room-1',
        'thread-1',
        'my report (final).pdf',
      );

      expect(
        capturedBytesUri().pathSegments.last,
        equals('my report (final).pdf'),
      );
    });

    test(
        'percent-encodes ? and # in filenames so they cannot inject query '
        'or fragment', () async {
      stubBytes(() async => Uint8List(0));

      await api.getThreadWorkdirFile('room-1', 'thread-1', 'a?b#c.txt');

      final captured = capturedBytesUri();

      expect(captured.pathSegments.last, equals('a?b#c.txt'));
      expect(captured.query, isEmpty);
      expect(captured.fragment, isEmpty);
      expect(captured.toString(), contains('a%3Fb%23c.txt'));
    });

    test('propagates exceptions from the transport', () async {
      stubBytes(() async {
        throw const NotFoundException(
          message: 'No workdir file',
          resource: '/file',
        );
      });

      await expectLater(
        api.getThreadWorkdirFile('room-1', 'thread-1', 'missing.txt'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('throws ArgumentError for empty roomId', () {
      expect(
        () => api.getThreadWorkdirFile('', 'thread-1', 'a.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty threadId', () {
      expect(
        () => api.getThreadWorkdirFile('room-1', '', 'a.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty filename', () {
      expect(
        () => api.getThreadWorkdirFile('room-1', 'thread-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Each would reach the server as a different path: the URL resolves a dot
    // segment and drops an empty one.
    for (final filename in ['dir/../file.txt', 'dir//file.txt']) {
      test('throws ArgumentError for "$filename"', () {
        expect(
          () => api.getThreadWorkdirFile('room-1', 'thread-1', filename),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'filename'),
          ),
        );
      });
    }
  });
}
