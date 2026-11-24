import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/file_source.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_targets.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_source.dart';

class _MockApi extends Mock implements SoliplexApi {}

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

  group('pdfTargetFor', () {
    test('a room upload opens as that room upload', () {
      final file =
          FileUpload(filename: 'a.pdf', url: Uri.parse('https://x/a.pdf'));
      expect(
        pdfTargetFor(const RoomUploadSource(roomId: 'r'), file),
        const RoomUploadPdf(roomId: 'r', filename: 'a.pdf'),
      );
    });

    test('a thread upload opens as that thread upload', () {
      final file =
          FileUpload(filename: 'a.pdf', url: Uri.parse('https://x/a.pdf'));
      expect(
        pdfTargetFor(
            const ThreadUploadSource(roomId: 'r', threadId: 't'), file),
        const ThreadUploadPdf(roomId: 'r', threadId: 't', filename: 'a.pdf'),
      );
    });

    test('a workspace file opens as that workspace file, titled by its name',
        () {
      final file = WorkdirFile(
        filename: 'out/a.pdf',
        url: Uri.parse('https://x/out/a.pdf'),
        sizeBytes: 7,
      );
      final target = pdfTargetFor(
        const WorkspaceFileSource(roomId: 'r', threadId: 't'),
        file,
      );
      expect(target, WorkdirPdf(roomId: 'r', threadId: 't', file: file));
      expect(target.title, 'a.pdf');
    });
  });

  group('fileSourceOf', () {
    final file = WorkdirFile(
      filename: 'out/a.pdf',
      url: Uri.parse('https://x/out/a.pdf'),
      sizeBytes: 7,
    );

    for (final source in const <FileSource>[
      RoomUploadSource(roomId: 'r'),
      ThreadUploadSource(roomId: 'r', threadId: 't'),
      WorkspaceFileSource(roomId: 'r', threadId: 't'),
    ]) {
      test('finds the ${source.runtimeType} a file opened from', () {
        expect(fileSourceOf(pdfTargetFor(source, file)), source);
      });
    }

    test('finds none for a link', () {
      expect(fileSourceOf(LinkPdf(Uri.parse('https://x/a.pdf'))), isNull);
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
}
