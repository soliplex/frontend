import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('ChunkVisualization', () {
    group('construction', () {
      test('creates with all required fields', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['abc123', 'def456'],
        );

        expect(visualization.chunkId, equals('chunk-123'));
        expect(visualization.documentUri, equals('doc.pdf'));
        expect(visualization.imagesBase64, equals(['abc123', 'def456']));
      });

      test('creates with null documentUri', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const ['abc123'],
        );

        expect(visualization.documentUri, isNull);
      });

      test('creates with empty images list', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const [],
        );

        expect(visualization.imagesBase64, isEmpty);
      });
    });

    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'chunk_id': 'chunk-abc',
          'document_uri': 'file.pdf',
          'images_base_64': ['img1', 'img2'],
        };

        final visualization = ChunkVisualization.fromJson(json);

        expect(visualization.chunkId, equals('chunk-abc'));
        expect(visualization.documentUri, equals('file.pdf'));
        expect(visualization.imagesBase64, equals(['img1', 'img2']));
      });

      test('parses JSON with null document_uri', () {
        final json = {
          'chunk_id': 'chunk-abc',
          'document_uri': null,
          'images_base_64': ['img1'],
        };

        final visualization = ChunkVisualization.fromJson(json);

        expect(visualization.documentUri, isNull);
      });

      test('parses JSON with empty images array', () {
        final json = {
          'chunk_id': 'chunk-abc',
          'document_uri': 'doc.pdf',
          'images_base_64': <String>[],
        };

        final visualization = ChunkVisualization.fromJson(json);

        expect(visualization.imagesBase64, isEmpty);
      });

      test('throws MalformedResponseException when chunk_id is missing', () {
        expect(
          () => ChunkVisualization.fromJson(const {
            'document_uri': 'doc.pdf',
            'images_base_64': <String>[],
          }),
          throwsA(isA<MalformedResponseException>()),
        );
      });

      test('throws MalformedResponseException when chunk_id is not a String',
          () {
        expect(
          () => ChunkVisualization.fromJson(const {
            'chunk_id': 42,
            'images_base_64': <String>[],
          }),
          throwsA(isA<MalformedResponseException>()),
        );
      });

      test(
          'throws MalformedResponseException when document_uri is not a String',
          () {
        expect(
          () => ChunkVisualization.fromJson(const {
            'chunk_id': 'chunk-abc',
            'document_uri': 42,
            'images_base_64': <String>[],
          }),
          throwsA(isA<MalformedResponseException>()),
        );
      });

      test('throws MalformedResponseException when images_base_64 is missing',
          () {
        expect(
          () => ChunkVisualization.fromJson(const {'chunk_id': 'chunk-abc'}),
          throwsA(isA<MalformedResponseException>()),
        );
      });

      test(
          'throws MalformedResponseException when an images_base_64 entry is '
          'not a String', () {
        expect(
          () => ChunkVisualization.fromJson(const {
            'chunk_id': 'chunk-abc',
            'images_base_64': [1, 2],
          }),
          throwsA(isA<MalformedResponseException>()),
        );
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['abc', 'def'],
        );

        final json = visualization.toJson();

        expect(json['chunk_id'], equals('chunk-123'));
        expect(json['document_uri'], equals('doc.pdf'));
        expect(json['images_base_64'], equals(['abc', 'def']));
      });

      test('serializes null document_uri', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const [],
        );

        final json = visualization.toJson();

        expect(json['document_uri'], isNull);
      });
    });

    group('roundtrip', () {
      test('fromJson/toJson preserves all data', () {
        final original = ChunkVisualization(
          chunkId: 'chunk-roundtrip',
          documentUri: 'test.pdf',
          imagesBase64: const ['img1', 'img2', 'img3'],
        );

        final json = original.toJson();
        final restored = ChunkVisualization.fromJson(json);

        expect(restored.chunkId, equals(original.chunkId));
        expect(restored.documentUri, equals(original.documentUri));
        expect(restored.imagesBase64, equals(original.imagesBase64));
      });
    });

    group('computed properties', () {
      test('hasImages returns true when images exist', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const ['img1'],
        );

        expect(visualization.hasImages, isTrue);
      });

      test('hasImages returns false when images empty', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const [],
        );

        expect(visualization.hasImages, isFalse);
      });

      test('imageCount returns correct count', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const ['a', 'b', 'c'],
        );

        expect(visualization.imageCount, equals(3));
      });

      test('imageCount returns zero for empty list', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: null,
          imagesBase64: const [],
        );

        expect(visualization.imageCount, equals(0));
      });
    });

    group('equality', () {
      test('equal when all fields match', () {
        final a = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1', 'img2'],
        );
        final b = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1', 'img2'],
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('not equal when chunkId differs', () {
        final a = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1'],
        );
        final b = ChunkVisualization(
          chunkId: 'chunk-456',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1'],
        );

        expect(a, isNot(equals(b)));
      });

      test('not equal when documentUri differs', () {
        final a = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc1.pdf',
          imagesBase64: const ['img1'],
        );
        final b = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc2.pdf',
          imagesBase64: const ['img1'],
        );

        expect(a, isNot(equals(b)));
      });

      test('not equal when imagesBase64 differs', () {
        final a = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1'],
        );
        final b = ChunkVisualization(
          chunkId: 'chunk-123',
          documentUri: 'doc.pdf',
          imagesBase64: const ['img1', 'img2'],
        );

        expect(a, isNot(equals(b)));
      });
    });

    group('toString', () {
      test('includes chunkId and image count', () {
        final visualization = ChunkVisualization(
          chunkId: 'chunk-test',
          documentUri: null,
          imagesBase64: const ['a', 'b'],
        );

        expect(visualization.toString(), contains('chunk-test'));
        expect(visualization.toString(), contains('2'));
      });
    });
  });
}
