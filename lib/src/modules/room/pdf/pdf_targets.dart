import 'package:soliplex_client/soliplex_client.dart'
    show RagDocument, SoliplexApi, SourceReference;

import '../../../shared/document_display.dart';
import '../../../shared/pdf/pdf_document_view.dart';
import '../../../shared/pdf/pdf_source.dart';
import 'pdf_quote.dart';

/// How the viewer opens [target]: room files through [api], with this
/// client's credentials; a link as itself, with none.
PdfViewerSource pdfViewerSourceFor(PdfOpenTarget target, SoliplexApi api) =>
    switch (target) {
      RoomUploadPdf(:final roomId, :final filename) => PdfViewerSource(
          title: filename,
          origin: 'Room upload',
          cacheKey: target.key,
          load: PdfLoadBytes(() => api.getRoomUploadFile(roomId, filename)),
        ),
      ThreadUploadPdf(:final roomId, :final threadId, :final filename) =>
        PdfViewerSource(
          title: filename,
          origin: 'Thread upload',
          cacheKey: target.key,
          load: PdfLoadBytes(
            () => api.getThreadUploadFile(roomId, threadId, filename),
          ),
        ),
      WorkdirPdf(:final roomId, :final threadId, :final file) =>
        PdfViewerSource(
          title: file.basename,
          origin: 'Workspace file',
          cacheKey: target.key,
          sizeBytes: file.sizeBytes,
          load: PdfLoadBytes(
            () => api.getThreadWorkdirFile(roomId, threadId, file.filename),
          ),
        ),
      RagDocumentPdf(:final roomId, :final documentId, :final database) =>
        PdfViewerSource(
          title: target.title,
          origin: 'Room document',
          cacheKey: target.key,
          whenGone: _noStoredPdf,
          load: PdfLoadBytes(
            () => api.getRagDocumentFile(
              roomId,
              documentId,
              database: database,
            ),
          ),
        ),
      CitationPdfTarget(:final roomId, :final documentId, :final database) =>
        PdfViewerSource(
          title: target.title,
          origin: 'Cited document',
          cacheKey: target.key,
          whenGone: _noStoredPdf,
          load: PdfLoadBytes(
            () => api.getRagDocumentFile(
              roomId,
              documentId,
              database: database,
            ),
          ),
        ),
      LinkPdf(:final uri) => PdfViewerSource(
          title: target.title,
          origin: 'Linked from ${uri.host}',
          cacheKey: target.key,
          load: PdfLoadUri(uri),
        ),
    };

/// The server lists a document but keeps no PDF of it: its original was
/// not stored when it was indexed, or is not a PDF.
const _noStoredPdf = (
  heading: 'No PDF of this document is available',
  detail: "The server didn't keep the file it was indexed from.",
);

/// Whether [document] was indexed from a PDF, as far as the listing says:
/// the content type the server recorded when it indexed the document, or,
/// where it recorded none, a `.pdf` at the end of its URI's path.
bool isPdfDocument(RagDocument document) {
  final type = document.metadata['content_type'];
  if (type is String && type.isNotEmpty) {
    return type.split(';').first.trim().toLowerCase() == 'application/pdf';
  }
  final path = Uri.tryParse(document.uri)?.path ?? document.uri;
  return path.toLowerCase().endsWith('.pdf');
}

/// [document] as the viewer opens it, or null when it was not indexed from
/// a PDF ([isPdfDocument]).
RagDocumentPdf? ragDocumentPdf(RagDocument document,
        {required String roomId}) =>
    isPdfDocument(document)
        ? RagDocumentPdf(
            roomId: roomId,
            documentId: document.id,
            title: DocumentDisplay(document).name,
          )
        : null;

/// A RAG document's text as the server indexed it — by OCR, for a scan —
/// for the viewer to offer where the PDF has none, and to show what the
/// LLM can find.
Future<List<PdfTextBlock>> loadIndexedText(
  SoliplexApi api, {
  required String roomId,
  required String documentId,
  String? database,
}) async {
  final text = await api.getDocumentText(
    roomId,
    documentId,
    database: database,
  );
  return [
    for (final block in text.blocks)
      PdfTextBlock(
        box: PdfPassageBox(
          page: block.box.page,
          left: block.box.left,
          top: block.box.top,
          right: block.box.right,
          bottom: block.box.bottom,
        ),
        text: block.text,
      ),
  ];
}

/// The PDF a link in a message names, or null for a link the viewer should
/// leave to the browser.
///
/// A link to one of [serverUrl]'s own upload routes — same scheme, host and
/// port — opens as that upload, fetched with this client's credentials.
/// Any other `http(s)` link whose path ends in `.pdf` opens as a public
/// document, with none: credentials never follow a link off the server.
PdfOpenTarget? pdfTargetForHref(String href, {required Uri serverUrl}) {
  final uri = Uri.tryParse(href);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  if (!uri.path.toLowerCase().endsWith('.pdf')) return null;
  if (_sameOrigin(uri, serverUrl)) {
    final upload = _uploadTarget(uri.pathSegments);
    if (upload != null) return upload;
  }
  return LinkPdf(uri);
}

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// Reads `…/uploads/{room}/file/{name}` and
/// `…/uploads/{room}/thread/{thread}/file/{name}`, the backend's upload
/// routes, from the end of [segments].
PdfOpenTarget? _uploadTarget(List<String> segments) {
  final n = segments.length;
  if (n >= 4 && segments[n - 4] == 'uploads' && segments[n - 2] == 'file') {
    return RoomUploadPdf(roomId: segments[n - 3], filename: segments[n - 1]);
  }
  if (n >= 6 &&
      segments[n - 6] == 'uploads' &&
      segments[n - 4] == 'thread' &&
      segments[n - 2] == 'file') {
    return ThreadUploadPdf(
      roomId: segments[n - 5],
      threadId: segments[n - 3],
      filename: segments[n - 1],
    );
  }
  return null;
}

/// The file a quote read back from a sent message came from, found by its
/// [title] — which is all such a quote records.
///
/// Files opened this session come first, as the likeliest; then the
/// thread's uploads, the room's, and the thread's workspace. Null when none
/// carries the name, as when the file has since been removed.
PdfOpenTarget? resolveQuoteTarget(
  String title, {
  required Iterable<PdfOpenTarget> opened,
  required Iterable<PdfOpenTarget> threadUploads,
  required Iterable<PdfOpenTarget> roomUploads,
  required Iterable<PdfOpenTarget> workdirFiles,
}) {
  for (final candidates in [opened, threadUploads, roomUploads, workdirFiles]) {
    for (final target in candidates) {
      if (target.title == title) return target;
    }
  }
  return null;
}

/// [cited]'s document, opened at it, with every other citation of the same
/// document in [threadCitations] to step through: in order, each chunk once.
CitationPdfTarget citationTargetFor(
  SourceReference cited,
  Iterable<SourceReference> threadCitations, {
  required String roomId,
}) {
  final citations = <SourceReference>[];
  final seen = <String>{};
  for (final ref in [...threadCitations, cited]) {
    if (ref.documentId == cited.documentId &&
        ref.database == cited.database &&
        seen.add(ref.chunkId)) {
      citations.add(ref);
    }
  }
  return CitationPdfTarget(
    roomId: roomId,
    citations: citations,
    active: citations.indexWhere((ref) => ref.chunkId == cited.chunkId),
  );
}
