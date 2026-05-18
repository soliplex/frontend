import 'dart:typed_data';

class ImageDataUri {
  const ImageDataUri({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

ImageDataUri? tryDecodeImageDataUri(String src) {
  final uri = Uri.tryParse(src);
  if (uri == null || uri.scheme != 'data') return null;

  final data = uri.data;
  if (data == null) return null;

  if (!data.mimeType.startsWith('image/')) return null;

  // Validate length on the raw source string. UriData's accessors normalize
  // the payload (URL-decoding, base64 padding), so `data.contentText.length`
  // is not a reliable proxy for the raw base64 input.
  if (data.isBase64) {
    final commaIdx = src.indexOf(',');
    if (commaIdx < 0) return null;
    final rawPayload = src.substring(commaIdx + 1);
    if (rawPayload.isEmpty || rawPayload.length % 4 != 0) return null;
  }

  try {
    return ImageDataUri(
      bytes: Uint8List.fromList(data.contentAsBytes()),
      mimeType: data.mimeType,
    );
  } on FormatException {
    return null;
  }
}
