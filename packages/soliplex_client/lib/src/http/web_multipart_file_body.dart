/// Body marker for a file upload backed by a browser File/Blob.
///
/// When the HTTP client receives a body of this type, it constructs a
/// `multipart/form-data` request from the underlying blob natively
/// (e.g. via `FormData` + `XMLHttpRequest` on web). This bypasses
/// Dart-side multipart encoding so the file's bytes never enter the
/// Dart/JS heap — the browser streams from the blob's disk-backed
/// storage directly to the network.
///
/// Only the web HTTP client recognizes this type. Native HTTP clients
/// should throw `ArgumentError` when handed one — uploads on native
/// platforms continue to use the `Stream<List<int>>` body path through
/// the manual multipart encoder.
///
/// The [fileBlob] field is `Object` because `soliplex_client` is pure
/// Dart and cannot depend on `package:web`. Web clients downcast at
/// the point of use.
class WebMultipartFileBody {
  /// Creates a body marker pointing at an opaque browser File/Blob.
  const WebMultipartFileBody({
    required this.fieldName,
    required this.filename,
    required this.fileBlob,
    required this.mimeType,
    required this.contentLength,
    this.onProgress,
  });

  /// Form-data field name, typically `'file'`.
  final String fieldName;

  /// Filename to send. Already mangled by the picker for folder uploads.
  final String filename;

  /// Opaque reference to a browser File/Blob. Concrete type is
  /// `web.File` on web; ignored on other platforms.
  final Object fileBlob;

  /// MIME type for the file part.
  final String mimeType;

  /// File length in bytes. Used for the part's `Content-Length` and
  /// for upload-progress denominators.
  final int contentLength;

  /// Optional progress callback. The web HTTP client invokes this with
  /// `(bytesSent, totalBytes)` as the browser reports upload progress
  /// from `xhr.upload.onprogress`. Native HTTP clients ignore this —
  /// progress on native is reported via the byte-counting wrapper on
  /// the streaming-multipart pipeline instead.
  final void Function(int sent, int total)? onProgress;
}
