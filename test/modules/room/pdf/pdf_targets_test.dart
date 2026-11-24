import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_targets.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_source.dart';

class _MockApi extends Mock implements SoliplexApi {}

SourceReference _cited(
  String chunkId, {
  String documentId = 'doc-1',
  String database = 'notes',
}) =>
    SourceReference(
      documentId: documentId,
      documentUri: 'file:///srv/notes.pdf',
      content: 'Passage $chunkId',
      chunkId: chunkId,
      documentTitle: 'notes.pdf',
      database: database,
    );

void main() {
  final server = Uri.parse('https://chat.example.com');

  group('pdfTargetForHref', () {
    test("opens the server's room upload route as that upload", () {
      final target = pdfTargetForHref(
        'https://chat.example.com/api/v1/uploads/room-1/file/brief.pdf',
        serverUrl: server,
      );
      expect(
        target,
        const RoomUploadPdf(roomId: 'room-1', filename: 'brief.pdf'),
      );
    });

    test("opens the server's thread upload route as that upload", () {
      final target = pdfTargetForHref(
        'https://chat.example.com/api/v1/uploads/r/thread/t/file/a%20b.pdf',
        serverUrl: server,
      );
      expect(
        target,
        const ThreadUploadPdf(roomId: 'r', threadId: 't', filename: 'a b.pdf'),
      );
    });

    test('an upload route on another origin is only a link', () {
      for (final href in [
        'https://evil.example.com/api/v1/uploads/r/file/a.pdf',
        'http://chat.example.com/api/v1/uploads/r/file/a.pdf',
        'https://chat.example.com:8443/api/v1/uploads/r/file/a.pdf',
      ]) {
        expect(pdfTargetForHref(href, serverUrl: server), isA<LinkPdf>(),
            reason: href);
      }
    });

    test('any other http(s) PDF is a public link', () {
      final target = pdfTargetForHref('https://arxiv.org/pdf/2401.1.PDF',
          serverUrl: server);
      expect(target, isA<LinkPdf>());
      expect(target!.title, '2401.1.PDF');
    });

    test('leaves everything else to the browser', () {
      for (final href in [
        'https://example.com/page.html',
        'https://example.com/a.pdf.html',
        'mailto:someone@example.com',
        'file:///etc/a.pdf',
        'not a url %%%',
      ]) {
        expect(pdfTargetForHref(href, serverUrl: server), isNull, reason: href);
      }
    });
  });

  group('targets', () {
    test('are equal when they name the same file', () {
      expect(
        const RoomUploadPdf(roomId: 'r', filename: 'a.pdf'),
        const RoomUploadPdf(roomId: 'r', filename: 'a.pdf'),
      );
      expect(
        const RoomUploadPdf(roomId: 'r', filename: 'a.pdf'),
        isNot(const ThreadUploadPdf(
            roomId: 'r', threadId: 't', filename: 'a.pdf')),
      );
    });

    test("a link's key leaves out its query", () {
      final link = LinkPdf(Uri.parse('https://e.com/a.pdf?token=secret'));
      expect(link.key, 'link:e.com/a.pdf');
    });

    test('only thread files are thread-scoped', () {
      final file = WorkdirFile(
        filename: 'out/report.pdf',
        url: Uri.parse('https://e.com/x'),
      );
      expect(
        WorkdirPdf(roomId: 'r', threadId: 't', file: file).isThreadScoped,
        isTrue,
      );
      expect(
        const ThreadUploadPdf(roomId: 'r', threadId: 't', filename: 'a')
            .isThreadScoped,
        isTrue,
      );
      expect(
        const RoomUploadPdf(roomId: 'r', filename: 'a').isThreadScoped,
        isFalse,
      );
      expect(LinkPdf(Uri.parse('https://e.com/a.pdf')).isThreadScoped, isFalse);
    });
  });

  group('pdfViewerSourceFor', () {
    late _MockApi api;
    final bytes = Uint8List.fromList([1]);

    setUp(() => api = _MockApi());

    test('fetches a room upload through the API', () async {
      when(() => api.getRoomUploadFile('r', 'a.pdf'))
          .thenAnswer((_) async => bytes);
      final source = pdfViewerSourceFor(
        const RoomUploadPdf(roomId: 'r', filename: 'a.pdf'),
        api,
      );
      expect(source.title, 'a.pdf');
      expect(source.origin, 'Room upload');
      expect(await (source.load as PdfLoadBytes).fetch(), bytes);
    });

    test("fetches a cited document from the room's RAG database", () async {
      when(() => api.getRagDocumentFile('r', 'doc-1', database: 'notes'))
          .thenAnswer((_) async => bytes);
      final source = pdfViewerSourceFor(
        CitationPdfTarget(roomId: 'r', citations: [_cited('c1')]),
        api,
      );
      expect(source.title, 'notes.pdf');
      expect(source.origin, 'Cited document');
      expect(source.cacheKey, 'rag-document:r/notes/doc-1');
      expect(await (source.load as PdfLoadBytes).fetch(), bytes);
    });

    test('fetches a thread upload through the API', () async {
      when(() => api.getThreadUploadFile('r', 't', 'a.pdf'))
          .thenAnswer((_) async => bytes);
      final source = pdfViewerSourceFor(
        const ThreadUploadPdf(roomId: 'r', threadId: 't', filename: 'a.pdf'),
        api,
      );
      expect(source.origin, 'Thread upload');
      expect(await (source.load as PdfLoadBytes).fetch(), bytes);
    });

    test('fetches a workspace file by its path, and knows its size', () async {
      when(() => api.getThreadWorkdirFile('r', 't', 'out/report.pdf'))
          .thenAnswer((_) async => bytes);
      final file = WorkdirFile(
        filename: 'out/report.pdf',
        url: Uri.parse('https://e.com/x'),
        sizeBytes: 2048,
      );
      final source = pdfViewerSourceFor(
        WorkdirPdf(roomId: 'r', threadId: 't', file: file),
        api,
      );
      expect(source.title, 'report.pdf');
      expect(source.sizeBytes, 2048);
      expect(await (source.load as PdfLoadBytes).fetch(), bytes);
    });

    test('loads a link as itself, naming its host', () {
      final uri = Uri.parse('https://arxiv.org/pdf/x.pdf');
      final source = pdfViewerSourceFor(LinkPdf(uri), api);
      expect(source.origin, 'Linked from arxiv.org');
      expect((source.load as PdfLoadUri).uri, uri);
      verifyZeroInteractions(api);
    });
  });

  group('resolveQuoteTarget', () {
    const opened = RoomUploadPdf(roomId: 'r', filename: 'shared.pdf');
    const threadFile =
        ThreadUploadPdf(roomId: 'r', threadId: 't', filename: 'shared.pdf');
    const roomFile = RoomUploadPdf(roomId: 'r', filename: 'only-room.pdf');

    test('prefers a file opened this session', () {
      expect(
        resolveQuoteTarget(
          'shared.pdf',
          opened: const [opened],
          threadUploads: const [threadFile],
          roomUploads: const [],
          workdirFiles: const [],
        ),
        same(opened),
      );
    });

    test('then the thread, then the room', () {
      expect(
        resolveQuoteTarget(
          'shared.pdf',
          opened: const [],
          threadUploads: const [threadFile],
          roomUploads: const [roomFile],
          workdirFiles: const [],
        ),
        same(threadFile),
      );
      expect(
        resolveQuoteTarget(
          'only-room.pdf',
          opened: const [],
          threadUploads: const [threadFile],
          roomUploads: const [roomFile],
          workdirFiles: const [],
        ),
        same(roomFile),
      );
    });

    test('is null for a file no longer there', () {
      expect(
        resolveQuoteTarget(
          'gone.pdf',
          opened: const [],
          threadUploads: const [threadFile],
          roomUploads: const [roomFile],
          workdirFiles: const [],
        ),
        isNull,
      );
    });
  });

  group('citationTargetFor', () {
    test("gathers the thread's citations of the document, each chunk once", () {
      final target = citationTargetFor(
        _cited('c2'),
        [
          _cited('c1'),
          _cited('c9', documentId: 'doc-2'),
          _cited('c8', database: 'other'),
          _cited('c2'),
          _cited('c1'),
        ],
        roomId: 'r',
      );

      expect(target.citations.map((ref) => ref.chunkId), ['c1', 'c2']);
      expect(target.active, 1);
      expect(target.isThreadScoped, isTrue);
      expect(target.documentId, 'doc-1');
      expect(target.database, 'notes');
    });

    test('keeps a citation the thread does not list yet', () {
      final target = citationTargetFor(_cited('c3'), [], roomId: 'r');

      expect(target.citations.single.chunkId, 'c3');
      expect(target.active, 0);
    });

    test('every citation of a document opens the same file', () {
      final first = citationTargetFor(_cited('c1'), [], roomId: 'r');
      final second = citationTargetFor(_cited('c2'), [], roomId: 'r');

      expect(first, second);
      expect(first.key, second.key);
    });
  });
}
