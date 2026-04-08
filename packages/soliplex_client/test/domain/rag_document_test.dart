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
      test('single title produces equality filter', () {
        expect(
          buildDocumentFilter(['Report']),
          equals("title = 'Report'"),
        );
      });

      test('multiple titles produce IN filter', () {
        expect(
          buildDocumentFilter(['Report', 'Summary']),
          equals("title IN ('Report', 'Summary')"),
        );
      });

      test('escapes single quotes in titles', () {
        expect(
          buildDocumentFilter(["O'Brien Report"]),
          equals("title = 'O''Brien Report'"),
        );
      });

      test('escapes single quotes in multiple titles', () {
        expect(
          buildDocumentFilter(["O'Brien", "It's a test"]),
          equals("title IN ('O''Brien', 'It''s a test')"),
        );
      });

      test('deduplicates identical titles', () {
        expect(
          buildDocumentFilter(['Report', 'Report']),
          equals("title = 'Report'"),
        );
      });

      test('throws on empty list', () {
        expect(
          () => buildDocumentFilter([]),
          throwsArgumentError,
        );
      });
    });
  });
}
