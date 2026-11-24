import 'package:soliplex_client/soliplex_client.dart'
    show ServedFile, SoliplexApi;

import '../../../shared/pdf/pdf_source.dart';
import '../file_source.dart';
import 'pdf_quote.dart';

/// The PDF viewer's target for [file], listed by [source].
PdfOpenTarget pdfTargetFor(FileSource source, ServedFile file) =>
    switch (source) {
      RoomUploadSource(:final roomId) =>
        RoomUploadPdf(roomId: roomId, filename: file.filename),
      ThreadUploadSource(:final roomId, :final threadId) => ThreadUploadPdf(
          roomId: roomId,
          threadId: threadId,
          filename: file.filename,
        ),
      WorkspaceFileSource(:final roomId, :final threadId) =>
        WorkdirPdf(roomId: roomId, threadId: threadId, file: file),
    };

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
      LinkPdf(:final uri) => PdfViewerSource(
          title: target.title,
          origin: 'Linked from ${uri.host}',
          cacheKey: target.key,
          load: PdfLoadUri(uri),
        ),
    };

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
