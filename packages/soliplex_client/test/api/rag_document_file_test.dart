import 'dart:convert';
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

  group('getRagDocumentFile', () {
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

    test('returns the response bytes verbatim', () async {
      final payload = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      stubBytes(() async => payload);

      expect(await api.getRagDocumentFile('room-1', 'doc-1'), payload);
    });

    test('uses /rooms/{roomId}/documents/{documentId}/file', () async {
      stubBytes(() async => Uint8List(0));
      final token = CancelToken();

      await api.getRagDocumentFile(
        'room 1',
        'doc 1',
        timeout: const Duration(seconds: 5),
        cancelToken: token,
      );

      final call = captured();
      expect(
        call.uri.toString(),
        'https://api.example.com/api/v1/rooms/room%201/documents/doc%201/file',
      );
      expect(call.timeout, const Duration(seconds: 5));
      expect(call.cancelToken, same(token));
    });

    test('names the database when given one', () async {
      stubBytes(() async => Uint8List(0));

      await api.getRagDocumentFile('room-1', 'doc-1', database: 'notes');

      expect(captured().uri.queryParameters, {'database': 'notes'});
    });

    test('leaves an empty database out', () async {
      stubBytes(() async => Uint8List(0));

      await api.getRagDocumentFile('room-1', 'doc-1', database: '');

      expect(captured().uri.hasQuery, isFalse);
    });

    test('rejects an empty roomId or documentId', () {
      expect(
        () => api.getRagDocumentFile('', 'doc-1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => api.getRagDocumentFile('room-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('propagates a 404', () {
      stubBytes(
        () async => throw const NotFoundException(message: 'not local'),
      );

      expect(
        api.getRagDocumentFile('room-1', 'doc-1'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('getDocumentBoxes', () {
    final boxes = DocumentBoxes(
      documentId: 'doc-1',
      anchor: const [
        PassageBox(page: 1, left: 10, top: 700, right: 300, bottom: 650),
      ],
      context: const [],
    );

    void stubBoxes() {
      when(
        () => mockTransport.request<DocumentBoxes>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => boxes);
    }

    ({Uri uri, Object? fromJson}) captured() {
      final call = verify(
        () => mockTransport.request<DocumentBoxes>(
          'GET',
          captureAny(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: captureAny(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured;
      return (uri: call[0] as Uri, fromJson: call[1]);
    }

    test('sends every chunk id, the context refs and the database', () async {
      stubBoxes();

      final result = await api.getDocumentBoxes(
        'room-1',
        'doc-1',
        chunkIds: const ['c1', 'c2'],
        contextRefs: const ['#/texts/1', '#/texts/2'],
        database: 'notes',
      );

      expect(result, boxes);
      final call = captured();
      expect(call.uri.path, '/api/v1/rooms/room-1/documents/doc-1/boxes');
      expect(call.uri.queryParametersAll, {
        'chunk_ids': ['c1', 'c2'],
        'context_refs': [
          jsonEncode(['#/texts/1', '#/texts/2']),
        ],
        'database': ['notes'],
      });
      expect(call.fromJson, isNotNull);
    });

    test('leaves out empty context refs and database', () async {
      stubBoxes();

      await api.getDocumentBoxes(
        'room-1',
        'doc-1',
        chunkIds: const ['c1'],
        database: '',
      );

      expect(captured().uri.queryParametersAll, {
        'chunk_ids': ['c1'],
      });
    });

    test('rejects empty ids', () {
      expect(
        () => api.getDocumentBoxes('', 'doc-1', chunkIds: const ['c1']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => api.getDocumentBoxes('room-1', '', chunkIds: const ['c1']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => api.getDocumentBoxes('room-1', 'doc-1', chunkIds: const []),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('getDocumentText', () {
    final text = DocumentText(
      documentId: 'doc-1',
      blocks: const [
        DocumentTextBlock(
          box: PassageBox(page: 1, left: 10, top: 700, right: 300, bottom: 650),
          text: 'Chunking',
          label: 'section_header',
        ),
      ],
    );

    void stubText() {
      when(
        () => mockTransport.request<DocumentText>(
          'GET',
          any(),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => text);
    }

    ({Uri uri, CancelToken? cancelToken, Object? fromJson}) captured() {
      final call = verify(
        () => mockTransport.request<DocumentText>(
          'GET',
          captureAny(),
          cancelToken: captureAny(named: 'cancelToken'),
          fromJson: captureAny(named: 'fromJson'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
        ),
      ).captured;
      return (
        uri: call[0] as Uri,
        cancelToken: call[1] as CancelToken?,
        fromJson: call[2],
      );
    }

    test('uses /rooms/{roomId}/documents/{documentId}/text', () async {
      stubText();
      final token = CancelToken();

      final result = await api.getDocumentText(
        'room-1',
        'doc-1',
        database: 'notes',
        cancelToken: token,
      );

      expect(result, text);
      final call = captured();
      expect(call.uri.path, '/api/v1/rooms/room-1/documents/doc-1/text');
      expect(call.uri.queryParameters, {'database': 'notes'});
      expect(call.cancelToken, same(token));
      expect(call.fromJson, isNotNull);
    });

    test('leaves an empty database out', () async {
      stubText();

      await api.getDocumentText('room-1', 'doc-1', database: '');

      expect(captured().uri.hasQuery, isFalse);
    });

    test('rejects empty ids', () {
      expect(
        () => api.getDocumentText('', 'doc-1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => api.getDocumentText('room-1', ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DocumentText.fromJson', () {
    Map<String, dynamic> json({
      Object? origin = 'BOTTOMLEFT',
      Object? blocks,
    }) =>
        {
          'source': {'source_type': 'skill', 'name': 'rag'},
          'database': 'notes',
          'document_id': 'doc-1',
          'coord_origin': origin,
          'blocks': blocks ??
              [
                {
                  'page': 2,
                  'left': 56.8,
                  'top': 700,
                  'right': 561.6,
                  'bottom': 586.4,
                  'text': 'Most published guidance',
                  'label': 'text',
                },
              ],
        };

    test('parses the blocks', () {
      final text = DocumentText.fromJson(json());

      expect(
        text,
        DocumentText(
          documentId: 'doc-1',
          blocks: const [
            DocumentTextBlock(
              box: PassageBox(
                page: 2,
                left: 56.8,
                top: 700,
                right: 561.6,
                bottom: 586.4,
              ),
              text: 'Most published guidance',
              label: 'text',
            ),
          ],
        ),
      );
      expect(text.hashCode, DocumentText.fromJson(json()).hashCode);
      expect(text.toString(), 'DocumentText(doc-1, 1 blocks)');
      expect(
        text.blocks.single.toString(),
        'DocumentTextBlock(PassageBox(p.2, 56.8, 700.0, 561.6, 586.4), '
        'text, 23 chars)',
      );
      expect(text.blocks.single.hashCode, isA<int>());
      expect(text, isNot(DocumentText.fromJson(json(blocks: const []))));
    });

    final malformed = <String, Map<String, dynamic>>{
      'a top-left origin': json(origin: 'TOPLEFT'),
      'blocks not a list': json(blocks: 'x'),
      'a block not an object': json(blocks: ['x']),
      'a block without text': json(
        blocks: [
          {
            'page': 1,
            'left': 1,
            'top': 2,
            'right': 3,
            'bottom': 0,
            'label': 'text',
          },
        ],
      ),
      'a block without a page': json(
        blocks: [
          {'left': 1, 'top': 2, 'right': 3, 'bottom': 0, 'text': 'x'},
        ],
      ),
    };

    for (final MapEntry(key: name, value: body) in malformed.entries) {
      test('throws on $name', () {
        expect(
          () => DocumentText.fromJson(body),
          throwsA(
            isA<MalformedResponseException>().having(
              (e) => e.message,
              'message',
              startsWith('DocumentText:'),
            ),
          ),
        );
      });
    }
  });

  group('DocumentBoxes.fromJson', () {
    Map<String, dynamic> json({
      Object? documentId = 'doc-1',
      Object? origin = 'BOTTOMLEFT',
      Object? anchor,
      Object? context = const <Object>[],
    }) =>
        {
          'source': {'source_type': 'skill', 'name': 'rag'},
          'database': 'notes',
          'document_id': documentId,
          'coord_origin': origin,
          'anchor': anchor ??
              [
                {
                  'page': 2,
                  'left': 56.8,
                  'top': 700,
                  'right': 561.6,
                  'bottom': 586.4,
                },
              ],
          'context': context,
        };

    test('parses the boxes', () {
      final boxes = DocumentBoxes.fromJson(json());

      expect(
        boxes,
        DocumentBoxes(
          documentId: 'doc-1',
          anchor: const [
            PassageBox(
              page: 2,
              left: 56.8,
              top: 700,
              right: 561.6,
              bottom: 586.4,
            ),
          ],
          context: const [],
        ),
      );
      expect(boxes.hashCode, DocumentBoxes.fromJson(json()).hashCode);
      expect(boxes.toString(), 'DocumentBoxes(doc-1, 1 anchor, 0 context)');
      expect(
        boxes.anchor.single.toString(),
        'PassageBox(p.2, 56.8, 700.0, 561.6, 586.4)',
      );
      expect(boxes.anchor.single.hashCode, isA<int>());
    });

    test('differs when a box differs', () {
      expect(
        DocumentBoxes.fromJson(json()),
        isNot(DocumentBoxes.fromJson(json(context: json()['anchor']))),
      );
    });

    final malformed = <String, Map<String, dynamic>>{
      'no document_id': json(documentId: null),
      'a top-left origin': json(origin: 'TOPLEFT'),
      'no origin': json(origin: null),
      'anchor not a list': json(anchor: 'x'),
      'a box not an object': json(anchor: ['x']),
      'a box without a page': json(
        anchor: [
          {'left': 1, 'top': 2, 'right': 3, 'bottom': 0},
        ],
      ),
      'an edge not a number': json(
        anchor: [
          {'page': 1, 'left': '1', 'top': 2, 'right': 3, 'bottom': 0},
        ],
      ),
    };

    for (final MapEntry(key: name, value: body) in malformed.entries) {
      test('throws on $name', () {
        expect(
          () => DocumentBoxes.fromJson(body),
          throwsA(isA<MalformedResponseException>()),
        );
      });
    }
  });
}
