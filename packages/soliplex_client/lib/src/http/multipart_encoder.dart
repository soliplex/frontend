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
