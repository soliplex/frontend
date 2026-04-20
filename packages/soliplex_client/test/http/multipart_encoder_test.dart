import 'dart:convert';

import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('encodeMultipart', () {
    test('produces valid multipart body with correct structure', () {
      final fileBytes = utf8.encode('hello world');

      final result = encodeMultipart(
        fieldName: 'upload_file',
        filename: 'test.txt',
        fileBytes: fileBytes,
      );

      final bodyString = utf8.decode(result.bodyBytes);

      // Extract boundary from content type
      expect(result.contentType, startsWith('multipart/form-data; boundary='));
      final boundary = result.contentType.split('boundary=').last;

      // Must have correct multipart structure
      expect(bodyString, startsWith('--$boundary\r\n'));
      expect(bodyString, endsWith('--$boundary--\r\n'));
      expect(bodyString, contains('Content-Disposition: form-data'));
      expect(bodyString, contains('name="upload_file"'));
      expect(bodyString, contains('filename="test.txt"'));
      expect(bodyString, contains('Content-Type: application/octet-stream'));
      expect(bodyString, contains('hello world'));
    });

    test('handles non-ASCII filenames', () {
      final result = encodeMultipart(
        fieldName: 'upload_file',
        filename: '보고서_2026.pdf',
        fileBytes: [0],
      );

      final bodyString = utf8.decode(result.bodyBytes);
      expect(bodyString, contains('보고서_2026.pdf'));
    });

    test('escapes quotes and backslashes in filenames', () {
      final result = encodeMultipart(
        fieldName: 'upload_file',
        filename: r'my "file" with\slash.txt',
        fileBytes: [0],
      );

      final bodyString = utf8.decode(result.bodyBytes);
      expect(bodyString, contains(r'my \"file\" with\\slash.txt'));
    });

    test('preserves binary file content', () {
      final fileBytes = [0x00, 0x01, 0xFF, 0xFE, 0x80];

      final result = encodeMultipart(
        fieldName: 'upload_file',
        filename: 'data.bin',
        fileBytes: fileBytes,
      );

      // The file bytes must appear in the body in order
      expect(result.bodyBytes, containsAllInOrder(fileBytes));
    });

    test('uses custom MIME type when provided', () {
      final result = encodeMultipart(
        fieldName: 'upload_file',
        filename: 'doc.pdf',
        fileBytes: [0],
        mimeType: 'application/pdf',
      );

      final bodyString = utf8.decode(result.bodyBytes);
      expect(bodyString, contains('Content-Type: application/pdf'));
    });
  });
}
