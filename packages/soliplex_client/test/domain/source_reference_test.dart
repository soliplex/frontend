import 'dart:typed_data';

import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:test/test.dart';

void main() {
  group('SourceReference', () {
    test('creates with required fields only', () {
      const ref = SourceReference(
        documentId: 'doc-1',
        documentUri: 'https://example.com/doc.pdf',
        content: 'Test content',
        chunkId: 'chunk-1',
      );

      expect(ref.documentId, 'doc-1');
      expect(ref.documentUri, 'https://example.com/doc.pdf');
      expect(ref.content, 'Test content');
      expect(ref.chunkId, 'chunk-1');
      expect(ref.documentTitle, isNull);
      expect(ref.headings, isEmpty);
      expect(ref.pageNumbers, isEmpty);
      expect(ref.index, isNull);
    });

    test('creates with all fields', () {
      const ref = SourceReference(
        documentId: 'doc-1',
        documentUri: 'https://example.com/doc.pdf',
        content: 'Test content',
        chunkId: 'chunk-1',
        documentTitle: 'Test Document',
        headings: ['Chapter 1', 'Section 2'],
        pageNumbers: [1, 2, 3],
        index: 5,
      );

      expect(ref.documentId, 'doc-1');
      expect(ref.documentUri, 'https://example.com/doc.pdf');
      expect(ref.content, 'Test content');
      expect(ref.chunkId, 'chunk-1');
      expect(ref.documentTitle, 'Test Document');
      expect(ref.headings, ['Chapter 1', 'Section 2']);
      expect(ref.pageNumbers, [1, 2, 3]);
      expect(ref.index, 5);
    });

    group('equality', () {
      test('equal references are equal', () {
        const ref1 = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Test content',
          chunkId: 'chunk-1',
        );
        const ref2 = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Test content',
          chunkId: 'chunk-1',
        );

        expect(ref1, equals(ref2));
        expect(ref1.hashCode, equals(ref2.hashCode));
      });

      test('different chunkId makes references unequal', () {
        const ref1 = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Test content',
          chunkId: 'chunk-1',
        );
        const ref2 = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Test content',
          chunkId: 'chunk-2',
        );

        expect(ref1, isNot(equals(ref2)));
      });

      test('different sourceUrl makes references unequal', () {
        final ref1 = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Test content',
          chunkId: 'chunk-1',
          sourceUrl: Uri.parse('https://example.test/a'),
        );
        final ref2 = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Test content',
          chunkId: 'chunk-1',
          sourceUrl: Uri.parse('https://example.test/b'),
        );

        expect(ref1, isNot(equals(ref2)));
      });

      final png = Uint8List.fromList([1, 2, 3]);

      SourceReference figureRef({
        List<Figure> figures = const [],
        List<String> chunkIds = const [],
      }) =>
          SourceReference(
            documentId: 'doc-1',
            documentUri: 'https://example.com/doc.pdf',
            content: 'Test content',
            chunkId: 'chunk-1',
            figures: figures,
            chunkIds: chunkIds,
          );

      test('figures differing only in bytes are equal', () {
        expect(
          figureRef(figures: [Figure(ref: '#/pictures/0', bytes: png)]),
          equals(
            figureRef(
              figures: [Figure(ref: '#/pictures/0', bytes: Uint8List(1))],
            ),
          ),
        );
      });

      test('different figure ref makes references unequal', () {
        expect(
          figureRef(figures: [Figure(ref: '#/pictures/0', bytes: png)]),
          isNot(
            equals(
              figureRef(figures: [Figure(ref: '#/pictures/1', bytes: png)]),
            ),
          ),
        );
      });

      test('different figure caption makes references unequal', () {
        expect(
          figureRef(figures: [Figure(ref: '#/pictures/0', bytes: png)]),
          isNot(
            equals(
              figureRef(
                figures: [
                  Figure(ref: '#/pictures/0', bytes: png, caption: 'c'),
                ],
              ),
            ),
          ),
        );
      });

      test('different chunkIds make references unequal', () {
        expect(
          figureRef(chunkIds: const ['chunk-1']),
          isNot(equals(figureRef(chunkIds: const ['chunk-1', 'chunk-2']))),
        );
      });
    });
  });

  group('Figure', () {
    final png = Uint8List.fromList([1, 2, 3]);

    test('same ref and caption but different bytes are equal', () {
      final a = Figure(ref: '#/pictures/0', bytes: png, caption: 'c');
      final b = Figure(
        ref: '#/pictures/0',
        bytes: Uint8List.fromList([9, 9]),
        caption: 'c',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different caption makes figures unequal', () {
      expect(
        Figure(ref: '#/pictures/0', bytes: png, caption: 'a'),
        isNot(equals(Figure(ref: '#/pictures/0', bytes: png, caption: 'b'))),
      );
    });

    test('different ref makes figures unequal', () {
      expect(
        Figure(ref: '#/pictures/0', bytes: png),
        isNot(equals(Figure(ref: '#/pictures/1', bytes: png))),
      );
    });
  });

  group('formatting', () {
    group('formattedPageNumbers', () {
      test('returns null for empty page numbers', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.formattedPageNumbers, isNull);
      });

      test('formats single page', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
          pageNumbers: [5],
        );

        expect(ref.formattedPageNumbers, 'p.5');
      });

      test('formats consecutive pages as range', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
          pageNumbers: [1, 2, 3],
        );

        expect(ref.formattedPageNumbers, 'p.1-3');
      });

      test('formats non-consecutive pages as list', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
          pageNumbers: [1, 5, 10],
        );

        expect(ref.formattedPageNumbers, 'p.1, 5, 10');
      });

      test('sorts unsorted page numbers', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
          pageNumbers: [3, 1, 2],
        );

        expect(ref.formattedPageNumbers, 'p.1-3');
      });
    });

    group('displayTitle', () {
      test('prefers the filename from the uri over documentTitle', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
          documentTitle: 'My Document',
        );

        expect(ref.displayTitle, 'doc.pdf');
      });

      test('names the attachment, not the document containing it', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.displayTitle, 'budget.xlsx');
      });

      test('falls back to documentTitle when the uri is empty', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: '',
          content: 'content',
          chunkId: 'chunk-1',
          documentTitle: 'My Document',
        );

        expect(ref.displayTitle, 'My Document');
      });

      test('extracts filename from URI when no title', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/path/to/document.pdf',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.displayTitle, 'document.pdf');
      });

      test('extracts filename from file URI', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///Users/test/docs/report.md',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.displayTitle, 'report.md');
      });

      test('falls back rather than labelling a directory uri with nothing', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///docs/',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.displayTitle, 'Unknown Document');
      });

      test('returns Unknown Document when neither uri nor title names one', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: '',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.displayTitle, 'Unknown Document');
      });

      test('prefers documentTitle over a uri that is a bare id', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: '4e8bf0c7-f504-4ffc-b647-a9f8f255bea5',
          content: 'content',
          chunkId: 'chunk-1',
          documentTitle: 'Question 1',
        );

        expect(ref.displayTitle, 'Question 1');
      });

      test('ignores a documentTitle that reads blank', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///docs/',
          content: 'content',
          chunkId: 'chunk-1',
          documentTitle: '   ',
        );

        expect(ref.displayTitle, 'Unknown Document');
      });

      test('ignores empty documentTitle', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
          documentTitle: '',
        );

        expect(ref.displayTitle, 'doc.pdf');
      });
    });

    group('isPdf', () {
      test('returns true for .pdf extension', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.isPdf, isTrue);
      });

      test('returns true for .PDF extension (case insensitive)', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.PDF',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.isPdf, isTrue);
      });

      test('returns false for non-pdf extension', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.md',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.isPdf, isFalse);
      });

      test('reads the extension off the name, not the raw uri', () {
        // A page fragment leaves the uri no longer ending in .pdf, but the
        // row is still labelled handbook.pdf and still has pages to preview.
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///docs/handbook.pdf#page=3',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.isPdf, isTrue);
      });

      test('types an embedded file as itself, not its container', () {
        const ref = SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
          content: 'content',
          chunkId: 'chunk-1',
        );

        expect(ref.isPdf, isFalse);
      });
    });
  });
}
