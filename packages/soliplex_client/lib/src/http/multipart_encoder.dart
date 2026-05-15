import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Result of encoding a file as multipart form-data.
class MultipartEncoded {
  /// Creates a [MultipartEncoded] with the given body bytes and content type.
  MultipartEncoded({required this.bodyBytes, required this.contentType});

  /// The complete multipart body bytes ready to send.
  final List<int> bodyBytes;

  /// The Content-Type header value including boundary.
  final String contentType;
}

/// Result of encoding a file as a streamed multipart form-data body.
///
/// The body is emitted as a [Stream] of byte chunks so callers can pipe
/// large files through `http.StreamedRequest` without buffering the
/// entire payload in memory.
class MultipartStreamEncoded {
  /// Creates a [MultipartStreamEncoded] with the given body stream,
  /// total content length, and content type.
  MultipartStreamEncoded({
    required this.bodyStream,
    required this.contentLength,
    required this.contentType,
  });

  /// The multipart body as a stream of byte chunks (preamble → file
  /// content → footer).
  final Stream<List<int>> bodyStream;

  /// Total byte length of [bodyStream]. Set this on the HTTP request's
  /// `Content-Length` header so the request uses an exact length rather
  /// than chunked transfer encoding.
  final int contentLength;

  /// The Content-Type header value including boundary.
  final String contentType;
}

/// Encodes a file as multipart form-data.
///
/// Returns the complete body bytes and Content-Type header. The entire
/// file is buffered in memory — suitable for typical document uploads.
///
/// The backend field name is `upload_file` (matching the Python endpoint).
MultipartEncoded encodeMultipart({
  required String fieldName,
  required String filename,
  required List<int> fileBytes,
  String mimeType = 'application/octet-stream',
}) {
  final boundary = _generateBoundary();
  final escapedFilename = filename
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');

  final preamble = '--$boundary\r\n'
      'Content-Disposition: form-data; '
      'name="$fieldName"; '
      'filename="$escapedFilename"\r\n'
      'Content-Type: $mimeType\r\n'
      '\r\n';
  final footer = '\r\n--$boundary--\r\n';

  final bodyBytes = <int>[
    ...utf8.encode(preamble),
    ...fileBytes,
    ...utf8.encode(footer),
  ];

  return MultipartEncoded(
    bodyBytes: bodyBytes,
    contentType: 'multipart/form-data; boundary=$boundary',
  );
}

String _generateBoundary() {
  final random = Random();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix =
      List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  return 'dart-multipart-$suffix';
}

/// Encodes a file as a streamed multipart form-data body.
///
/// Unlike [encodeMultipart], the file content is delivered chunk-by-chunk
/// from [openStream] — suitable for large uploads where buffering the
/// whole file in memory would be prohibitive.
///
/// [contentLength] is the size in bytes of the file content (NOT the
/// total multipart body). The returned [MultipartStreamEncoded] reports
/// the total body length including preamble and footer.
///
/// The backend field name is `upload_file` (matching the Python endpoint).
MultipartStreamEncoded encodeMultipartStream({
  required String fieldName,
  required String filename,
  required Stream<List<int>> Function() openStream,
  required int contentLength,
  String mimeType = 'application/octet-stream',
}) {
  final boundary = _generateBoundary();
  final escapedFilename = filename
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');

  final preambleBytes = utf8.encode(
    '--$boundary\r\n'
    'Content-Disposition: form-data; '
    'name="$fieldName"; '
    'filename="$escapedFilename"\r\n'
    'Content-Type: $mimeType\r\n'
    '\r\n',
  );
  final footerBytes = utf8.encode('\r\n--$boundary--\r\n');

  // UTF-8 byte length, not String.length — non-ASCII filenames or
  // boundary values would otherwise drift the Content-Length.
  final totalContentLength =
      preambleBytes.length + contentLength + footerBytes.length;

  Stream<List<int>> body() async* {
    yield preambleBytes;
    yield* openStream();
    yield footerBytes;
  }

  return MultipartStreamEncoded(
    bodyStream: body(),
    contentLength: totalContentLength,
    contentType: 'multipart/form-data; boundary=$boundary',
  );
}
