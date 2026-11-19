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

  ({Uri uri, Duration? timeout, CancelToken? cancelToken}) captured() {
    final call = verify(
      () => mockTransport.requestBytes(
        'GET',
        captureAny(),
        cancelToken: captureAny(named: 'cancelToken'),
        headers: any(named: 'headers'),
        timeout: captureAny(named: 'timeout'),
      ),
    ).captured;
    return (
      uri: call[0] as Uri,
      cancelToken: call[1] as CancelToken?,
      timeout: call[2] as Duration?,
    );
  }

  // Each method under test, called with a file name, so the name rules can
  // be checked once for both.
  final fetchers = <String, Future<Uint8List> Function(String filename)>{
    'getRoomUploadFile': (name) => api.getRoomUploadFile('room-1', name),
    'getThreadUploadFile': (name) =>
        api.getThreadUploadFile('room-1', 'thread-1', name),
  };

  group('getRoomUploadFile', () {
    test('returns the response bytes verbatim', () async {
      final payload = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      stubBytes(() async => payload);

      expect(await api.getRoomUploadFile('room-1', 'a.pdf'), equals(payload));
    });

    test('uses /uploads/{roomId}/file/{filename}', () async {
      stubBytes(() async => Uint8List(0));

      await api.getRoomUploadFile('room-1', 'a.pdf');

      expect(
        captured().uri.toString(),
        'https://api.example.com/api/v1/uploads/room-1/file/a.pdf',
      );
    });

    test('forwards the timeout and the cancel token', () async {
      stubBytes(() async => Uint8List(0));
      final token = CancelToken();

      await api.getRoomUploadFile(
        'room-1',
        'a.pdf',
        timeout: const Duration(seconds: 30),
        cancelToken: token,
      );

      final call = captured();
      expect(call.timeout, const Duration(seconds: 30));
      expect(call.cancelToken, same(token));
    });

    test('rejects an empty room id', () {
      expect(
        () => api.getRoomUploadFile('', 'a.pdf'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('getThreadUploadFile', () {
    test('returns the response bytes verbatim', () async {
      final payload = Uint8List.fromList([1, 2, 3]);
      stubBytes(() async => payload);

      expect(
        await api.getThreadUploadFile('room-1', 'thread-1', 'a.pdf'),
        equals(payload),
      );
    });

    test('uses /uploads/{roomId}/thread/{threadId}/file/{filename}', () async {
      stubBytes(() async => Uint8List(0));

      await api.getThreadUploadFile('room-1', 'thread-1', 'a.pdf');

      expect(
        captured().uri.toString(),
        'https://api.example.com/api/v1/uploads/room-1/thread/thread-1/file/'
        'a.pdf',
      );
    });

    test('forwards the timeout and the cancel token', () async {
      stubBytes(() async => Uint8List(0));
      final token = CancelToken();

      await api.getThreadUploadFile(
        'room-1',
        'thread-1',
        'a.pdf',
        timeout: const Duration(seconds: 30),
        cancelToken: token,
      );

      final call = captured();
      expect(call.timeout, const Duration(seconds: 30));
      expect(call.cancelToken, same(token));
    });

    test('rejects an empty room or thread id', () {
      expect(
        () => api.getThreadUploadFile('', 'thread-1', 'a.pdf'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => api.getThreadUploadFile('room-1', '', 'a.pdf'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  for (final MapEntry(key: method, value: fetch) in fetchers.entries) {
    group('$method file names', () {
      test('percent-encodes spaces and parentheses', () async {
        stubBytes(() async => Uint8List(0));

        await fetch('my report (final).pdf');

        expect(captured().uri.pathSegments.last, 'my report (final).pdf');
      });

      test('keeps ? and # in the path, not the query or fragment', () async {
        stubBytes(() async => Uint8List(0));

        await fetch('what?#.pdf');

        final uri = captured().uri;
        expect(uri.pathSegments.last, 'what?#.pdf');
        expect(uri.hasQuery, isFalse);
        expect(uri.hasFragment, isFalse);
      });

      for (final name in ['', '.', '..', 'dir/a.pdf', '../a.pdf']) {
        test('rejects "$name"', () {
          expect(() => fetch(name), throwsA(isA<ArgumentError>()));
          verifyNever(
            () => mockTransport.requestBytes(
              any(),
              any(),
              cancelToken: any(named: 'cancelToken'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          );
        });
      }

      test('passes transport errors through', () async {
        stubBytes(
          () async => throw const NotFoundException(message: 'gone'),
        );

        await expectLater(
          fetch('a.pdf'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });
  }
}
