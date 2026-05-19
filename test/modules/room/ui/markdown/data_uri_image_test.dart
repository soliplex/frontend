import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/markdown/data_uri_image.dart';

// 1x1 transparent PNG. Same byte source as other tests in this repo.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
  '2mP8/58BAwAI/AL+hc2rNAAAAABJRU5ErkJggg==',
);
final _pngBase64 = base64Encode(_pngBytes);

void main() {
  group('tryDecodeImageDataUri', () {
    test('decodes a valid image/png data URI', () {
      final result = tryDecodeImageDataUri('data:image/png;base64,$_pngBase64');
      expect(result, isNotNull);
      expect(result!.mimeType, 'image/png');
      expect(result.bytes, _pngBytes);
    });

    test('returns null for a non-image MIME type', () {
      final src =
          'data:text/plain;base64,${base64Encode(utf8.encode('hello'))}';
      expect(tryDecodeImageDataUri(src), isNull);
    });

    test('returns null when the base64 payload contains invalid characters',
        () {
      // The `@` characters are not part of the base64 alphabet so decoding
      // throws a FormatException; the helper must swallow it and return null.
      final result = tryDecodeImageDataUri('data:image/png;base64,@@@@@@@@');
      expect(result, isNull);
    });

    test(
        'returns null when the payload length is not a multiple of 4 '
        '(reproduces the live red-screen bug)', () {
      // Six base64 chars (mod 4 == 2) is the same shape as the truncated
      // 682-char payload seen in production: the chunk before the implicit
      // padding is incomplete, so the decoder throws FormatException. The
      // helper must catch it.
      final result = tryDecodeImageDataUri('data:image/png;base64,AAAAAA');
      expect(result, isNull);
    });

    test('returns null for a non-data URI', () {
      expect(
        tryDecodeImageDataUri('https://example.com/foo.png'),
        isNull,
      );
    });
  });
}
