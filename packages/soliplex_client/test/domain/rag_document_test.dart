import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:test/test.dart';

void main() {
  group('RagDocument', () {
    group('equality', () {
      test('equals by id only', () {
        const doc1 = RagDocument(id: 'doc-123', title: 'Title A');
        const doc2 = RagDocument(id: 'doc-123', title: 'Title B');

        expect(doc1, equals(doc2));
      });

      test('not equals with different id', () {
        const doc1 = RagDocument(id: 'doc-123', title: 'Title');
        const doc2 = RagDocument(id: 'doc-456', title: 'Title');

        expect(doc1, isNot(equals(doc2)));
      });
    });

    group('hashCode', () {
      test('same hashCode for same id', () {
        const doc1 = RagDocument(id: 'doc-123', title: 'Title A');
        const doc2 = RagDocument(id: 'doc-123', title: 'Title B');

        expect(doc1.hashCode, equals(doc2.hashCode));
      });
    });

    group('buildDocumentFilter', () {
      test('single document produces equality filter', () {
        expect(
          buildDocumentFilter(
            [const RagDocument(id: 'abc-123', title: 'Report')],
          ),
          equals("id = 'abc-123'"),
        );
      });

      test('multiple documents produce IN filter', () {
        expect(
          buildDocumentFilter([
            const RagDocument(id: 'abc-123', title: 'Report'),
            const RagDocument(id: 'def-456', title: 'Summary'),
          ]),
          equals("id IN ('abc-123', 'def-456')"),
        );
      });

      test('escapes single quotes in ids', () {
        expect(
          buildDocumentFilter(
            [const RagDocument(id: "id'inject", title: 'Report')],
          ),
          equals("id = 'id''inject'"),
        );
      });

      test('escapes multiple single quotes in one id', () {
        expect(
          buildDocumentFilter(
            [const RagDocument(id: "o'connor's", title: 'Report')],
          ),
          equals("id = 'o''connor''s'"),
        );
      });

      test('deduplicates by id', () {
        expect(
          buildDocumentFilter([
            const RagDocument(id: 'abc-123', title: 'Report'),
            const RagDocument(id: 'abc-123', title: 'Report Copy'),
          ]),
          equals("id = 'abc-123'"),
        );
      });

      test('works with blank titles', () {
        expect(
          buildDocumentFilter(
            [const RagDocument(id: 'abc-123', title: '')],
          ),
          equals("id = 'abc-123'"),
        );
      });

      test('throws on empty list', () {
        expect(
          () => buildDocumentFilter([]),
          throwsArgumentError,
        );
      });
    });

    group('parseDocumentFilter', () {
      test('parses a single-id equality filter', () {
        expect(parseDocumentFilter("id = 'abc-123'"), equals(['abc-123']));
      });

      test('parses a multi-id IN filter', () {
        expect(
          parseDocumentFilter("id IN ('abc-123', 'def-456')"),
          equals(['abc-123', 'def-456']),
        );
      });

      test('unescapes doubled single quotes', () {
        expect(parseDocumentFilter("id = 'id''inject'"), equals(["id'inject"]));
      });

      test('round-trips buildDocumentFilter output', () {
        const docs = [
          RagDocument(id: 'abc-123', title: 'A'),
          RagDocument(id: 'def-456', title: 'B'),
        ];
        expect(
          parseDocumentFilter(buildDocumentFilter(docs)),
          equals(['abc-123', 'def-456']),
        );
      });

      test('returns empty list for empty or unrecognized input', () {
        expect(parseDocumentFilter(''), isEmpty);
        expect(parseDocumentFilter('   '), isEmpty);
        expect(parseDocumentFilter('not a filter'), isEmpty);
      });

      test('returns empty list for unterminated quote', () {
        expect(parseDocumentFilter("id = 'abc"), isEmpty);
      });

      test('returns empty list for lone quote', () {
        expect(parseDocumentFilter("'"), isEmpty);
      });

      test('round-trips id containing escaped quote', () {
        const docs = [
          RagDocument(id: "a'b", title: 'X'),
        ];
        expect(
          parseDocumentFilter(buildDocumentFilter(docs)),
          equals(["a'b"]),
        );
      });
    });
  });
}
