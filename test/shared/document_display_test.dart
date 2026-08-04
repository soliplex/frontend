import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/shared/document_display.dart';

void main() {
  group('DocumentDisplay.icon file-type mapping', () {
    // The title carries no extension, so a fallback to it would surface as the
    // generic glyph rather than silently matching the expected one.
    IconData iconFor(String uri) => DocumentDisplay(
          RagDocument(id: 'doc-1', title: 'untitled', uri: uri),
        ).icon;

    // One representative per glyph family. A case per alias would restate the
    // switch it is checking, so a typo there would be copied into the
    // expectation rather than caught by it.
    test('maps a file family to its glyph', () {
      expect(iconFor('document.pdf'), equals(Icons.picture_as_pdf));
      expect(iconFor('document.docx'), equals(Icons.description));
      expect(iconFor('document.xlsx'), equals(Icons.table_chart));
      expect(iconFor('document.pptx'), equals(Icons.slideshow));
      expect(iconFor('document.png'), equals(Icons.image));
      expect(iconFor('document.md'), equals(Icons.article));
    });

    test('falls back to a generic glyph for an unrecognised extension', () {
      expect(iconFor('document.xyz'), equals(Icons.insert_drive_file));
    });

    test('matches the extension case-insensitively', () {
      expect(iconFor('document.PdF'), equals(Icons.picture_as_pdf));
    });

    test('reads the last of several dots', () {
      expect(iconFor('report.final.v2.pdf'), equals(Icons.picture_as_pdf));
    });

    test('reads the extension of a dotfile that has one', () {
      expect(iconFor('.hidden.txt'), equals(Icons.article));
    });

    group('names with no usable extension', () {
      test('no dot at all', () {
        expect(iconFor('README'), equals(Icons.insert_drive_file));
      });

      test('nothing after the dot', () {
        expect(iconFor('file.'), equals(Icons.insert_drive_file));
      });

      test('a leading dot and nothing else', () {
        expect(iconFor('.gitignore'), equals(Icons.insert_drive_file));
      });
    });
  });

  group('DocumentDisplay.name', () {
    test('returns filename from uri for file-path uri', () {
      const doc = RagDocument(
        id: 'doc-1',
        title: 'Facilities Handbook',
        uri: 'manuals/facilities/handbook.pdf',
      );
      expect(DocumentDisplay(doc).name, equals('handbook.pdf'));
    });

    test('falls back to title when uri is empty', () {
      const doc = RagDocument(id: 'doc-2', title: 'Question 1');
      expect(DocumentDisplay(doc).name, equals('Question 1'));
    });

    test('falls back to title when uri is a UUID', () {
      const doc = RagDocument(
        id: 'doc-3',
        title: 'Question 1',
        uri: '4e8bf0c7-f504-4ffc-b647-a9f8f255bea5',
      );
      expect(DocumentDisplay(doc).name, equals('Question 1'));
    });

    test('handles file:// prefixed uri', () {
      const doc = RagDocument(
        id: 'doc-4',
        title: 'Facilities Handbook',
        uri: 'file:///data/manuals/facilities/handbook.pdf',
      );
      expect(DocumentDisplay(doc).name, equals('handbook.pdf'));
    });

    test('returns just filename for short uri', () {
      const doc = RagDocument(
        id: 'doc-5',
        title: 'PowerPoint Presentation',
        uri: 'slides.pptx',
      );
      expect(DocumentDisplay(doc).name, equals('slides.pptx'));
    });

    test('handles uppercase UUID', () {
      const doc = RagDocument(
        id: 'doc-6',
        title: 'Question 2',
        uri: '4E8BF0C7-F504-4FFC-B647-A9F8F255BEA5',
      );
      expect(DocumentDisplay(doc).name, equals('Question 2'));
    });

    test('names an attachment, not the document containing it', () {
      const doc = RagDocument(
        id: 'doc-7',
        title: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
        uri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
      );
      expect(DocumentDisplay(doc).name, equals('budget.xlsx'));
    });

    test('falls back to title when the uri names no file', () {
      const doc = RagDocument(
        id: 'doc-11',
        title: 'Annual Report',
        uri: 'file:///docs/',
      );
      expect(DocumentDisplay(doc).name, equals('Annual Report'));
    });

    test('falls back to the uri when there is no title and no filename', () {
      // The least bad label available: it names no file and carries no title,
      // so the path is the only thing that distinguishes this row from another.
      const doc = RagDocument(
        id: 'doc-12',
        title: null,
        uri: 'file:///docs/',
      );
      expect(DocumentDisplay(doc).name, equals('file:///docs/'));
    });

    test('reads as untitled when the document carries no uri or title', () {
      const doc = RagDocument(id: 'doc-13', title: null);
      expect(DocumentDisplay(doc).name, equals('Untitled'));
    });

    test('reads a title of only whitespace as absent', () {
      // Taking it would label the row with something that renders as nothing,
      // and the tooltip meant to recover a truncated name would be blank too.
      const doc = RagDocument(
        id: 'doc-14',
        title: '   ',
        uri: 'file:///docs/',
      );
      expect(DocumentDisplay(doc).name, equals('file:///docs/'));
    });
  });

  group('DocumentDisplay.icon', () {
    test('resolves a regular document from its uri', () {
      const doc = RagDocument(
        id: 'doc-1',
        title: 'Facilities Handbook',
        uri: 'manuals/facilities/handbook.pdf',
      );
      expect(DocumentDisplay(doc).icon, equals(Icons.picture_as_pdf));
    });

    test('falls back to title when uri is empty', () {
      const doc = RagDocument(id: 'doc-2', title: 'report.pdf');
      expect(DocumentDisplay(doc).icon, equals(Icons.picture_as_pdf));
    });

    test('falls back to title when uri is a UUID', () {
      const doc = RagDocument(
        id: 'doc-3',
        title: 'Question 1.docx',
        uri: '4e8bf0c7-f504-4ffc-b647-a9f8f255bea5',
      );
      expect(DocumentDisplay(doc).icon, equals(Icons.description));
    });

    test('resolves an attachment to its own file type', () {
      const doc = RagDocument(
        id: 'doc-4',
        title: 'attachment',
        uri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
      );
      expect(DocumentDisplay(doc).icon, equals(Icons.table_chart));
    });

    test('falls back to title when the uri names no file', () {
      // The row is labelled from the title here, so the glyph has to come
      // from the title too or it would describe a different file.
      const doc = RagDocument(
        id: 'doc-9',
        title: 'Budget.xlsx',
        uri: 'file:///docs/',
      );
      expect(DocumentDisplay(doc).name, equals('Budget.xlsx'));
      expect(DocumentDisplay(doc).icon, equals(Icons.table_chart));
    });

    test('resolves an attachment whose name contains a literal hash', () {
      // A decoded name is not a URI: splitting it at '#' would strip the
      // extension and fall through to the generic glyph.
      const doc = RagDocument(
        id: 'doc-6',
        title: 'hashed',
        uri: 'file:///docs/a.pdf#attachment=invoice%231234.xlsx',
      );
      expect(DocumentDisplay(doc).name, equals('invoice#1234.xlsx'));
      expect(DocumentDisplay(doc).icon, equals(Icons.table_chart));
    });

    test('ignores a page fragment on a regular document', () {
      const doc = RagDocument(
        id: 'doc-8',
        title: 'paged',
        uri: 'file:///docs/handbook.pdf#page=3',
      );
      expect(DocumentDisplay(doc).icon, equals(Icons.picture_as_pdf));
    });
  });

  group('name derivation across surfaces', () {
    // The value once, then the agreement: each surface's own tests pin the
    // value, so what only these cases catch is the two ladders drifting apart —
    // one side gaining a guard the other does not.
    //
    // Their last resort differs by design and is deliberately not asserted
    // here: a citation with no name left reads `Unknown Document`, where a
    // listing row shows its URI, the only string that still tells two rows
    // apart.
    test('the document list and a citation name an attachment identically', () {
      const uri = 'file:///docs/annual-report.pdf#attachment=budget.xlsx';
      const doc = RagDocument(id: 'doc-1', title: null, uri: uri);
      const ref = SourceReference(
        documentId: 'doc-1',
        documentUri: uri,
        content: 'content',
        chunkId: 'chunk-1',
      );

      expect(DocumentDisplay(doc).name, equals('budget.xlsx'));
      expect(ref.displayTitle, equals(DocumentDisplay(doc).name));
    });

    test('both take the title when the uri names no file', () {
      const uri = 'file:///docs/';
      const doc = RagDocument(id: 'doc-2', title: 'Annual Report', uri: uri);
      const ref = SourceReference(
        documentId: 'doc-2',
        documentUri: uri,
        documentTitle: 'Annual Report',
        content: 'content',
        chunkId: 'chunk-1',
      );

      expect(DocumentDisplay(doc).name, equals('Annual Report'));
      expect(ref.displayTitle, equals(DocumentDisplay(doc).name));
    });

    test('both pass over a title that reads blank', () {
      const uri = 'file:///docs/report.pdf';
      const doc = RagDocument(id: 'doc-3', title: '   ', uri: uri);
      const ref = SourceReference(
        documentId: 'doc-3',
        documentUri: uri,
        documentTitle: '   ',
        content: 'content',
        chunkId: 'chunk-1',
      );

      expect(DocumentDisplay(doc).name, equals('report.pdf'));
      expect(ref.displayTitle, equals(DocumentDisplay(doc).name));
    });
  });

  group('filterDocuments', () {
    const container = RagDocument(
      id: 'doc-1',
      title: 'container',
      uri: 'file:///docs/annual-report.pdf',
    );
    const attachment = RagDocument(
      id: 'doc-2',
      title: 'attachment',
      uri: 'file:///docs/annual-report.pdf#attachment=my%20budget.xlsx',
    );

    test('matches an attachment by its decoded name', () {
      // 'my budget' appears in neither uri: the container's name does not
      // contain it and the attachment's is escaped. Matching depends on the
      // display name, which is what lets search work with no custom matcher.
      expect(
        filterDocuments(const [container, attachment], 'my budget'),
        equals(const [attachment]),
      );
    });
  });
}
