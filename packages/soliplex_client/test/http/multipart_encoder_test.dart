import 'dart:async';
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
      expect(
        result.contentType,
        startsWith('multipart/form-data; boundary='),
      );
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

  group('encodeMultipartStream', () {
    test('yields preamble, file chunks, then footer in order', () async {
      final fileChunks = <List<int>>[
        utf8.encode('hello '),
        utf8.encode('world'),
      ];
      const fileLength = 11; // 'hello world'

      final result = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'test.txt',
        openStream: () => Stream<List<int>>.fromIterable(fileChunks),
        contentLength: fileLength,
      );

      final emitted = <List<int>>[];
      await for (final chunk in result.bodyStream) {
        emitted.add(chunk);
      }

      final flatBody = utf8.decode(emitted.expand((c) => c).toList());
      final boundary = result.contentType.split('boundary=').last;

      expect(flatBody, startsWith('--$boundary\r\n'));
      expect(flatBody, endsWith('--$boundary--\r\n'));
      expect(flatBody, contains('filename="test.txt"'));
      expect(flatBody, contains('Content-Type: application/octet-stream'));
      expect(flatBody, contains('hello world'));
    });

    test('reports total contentLength as preamble + file + footer', () async {
      const fileLength = 11;
      final result = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'test.txt',
        openStream: () => Stream.value(utf8.encode('hello world')),
        contentLength: fileLength,
      );

      // Drain the stream to confirm reported length matches actual.
      final actualLength = await result.bodyStream
          .fold<int>(0, (acc, chunk) => acc + chunk.length);

      expect(result.contentLength, equals(actualLength));
    });

    test('contentLength uses UTF-8 byte length for non-ASCII filenames',
        () async {
      const fileLength = 1;
      // Korean filename — multi-byte characters in the preamble.
      final result = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: '보고서_2026.pdf',
        openStream: () => Stream.value([0]),
        contentLength: fileLength,
      );

      final actualLength = await result.bodyStream
          .fold<int>(0, (acc, chunk) => acc + chunk.length);

      // The reported contentLength must match the actual byte length,
      // not the code-unit length of the filename string.
      expect(result.contentLength, equals(actualLength));
      expect(result.contentLength, greaterThan('보고서_2026.pdf'.length));
    });

    test('openStream factory can be called multiple times', () async {
      var callCount = 0;
      Stream<List<int>> open() {
        callCount++;
        return Stream.value(utf8.encode('data'));
      }

      final result1 = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'a.txt',
        openStream: open,
        contentLength: 4,
      );
      await result1.bodyStream.drain<void>();

      final result2 = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'a.txt',
        openStream: open,
        contentLength: 4,
      );
      await result2.bodyStream.drain<void>();

      // openStream is called once when bodyStream is drained.
      expect(callCount, equals(2));
    });

    test('mid-stream error in openStream propagates through bodyStream',
        () async {
      final controller = StreamController<List<int>>()
        ..add(utf8.encode('partial'))
        ..addError(StateError('mid-stream failure'));
      unawaited(controller.close());

      final result = encodeMultipartStream(
        fieldName: 'upload_file',
        filename: 'broken.bin',
        openStream: () => controller.stream,
        contentLength: 100,
      );

      await expectLater(
        result.bodyStream.drain<void>(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
