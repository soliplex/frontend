import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/shared/file_type_icons.dart';

void main() {
  group('getFileTypeIcon', () {
    group('PDF files', () {
      test('returns PDF icon for .pdf extension', () {
        expect(getFileTypeIcon('document.pdf'), equals(Icons.picture_as_pdf));
      });

      test('handles full path with .pdf', () {
        expect(
          getFileTypeIcon('/path/to/document.pdf'),
          equals(Icons.picture_as_pdf),
        );
      });

      test('handles file:// URI with .pdf', () {
        expect(
          getFileTypeIcon('file:///path/to/document.pdf'),
          equals(Icons.picture_as_pdf),
        );
      });
    });

    group('Word documents', () {
      test('returns description icon for .doc extension', () {
        expect(getFileTypeIcon('document.doc'), equals(Icons.description));
      });

      test('returns description icon for .docx extension', () {
        expect(getFileTypeIcon('document.docx'), equals(Icons.description));
      });
    });

    group('Excel spreadsheets', () {
      test('returns table_chart icon for .xls extension', () {
        expect(getFileTypeIcon('spreadsheet.xls'), equals(Icons.table_chart));
      });

      test('returns table_chart icon for .xlsx extension', () {
        expect(getFileTypeIcon('spreadsheet.xlsx'), equals(Icons.table_chart));
      });
    });

    group('PowerPoint presentations', () {
      test('returns slideshow icon for .ppt extension', () {
        expect(getFileTypeIcon('presentation.ppt'), equals(Icons.slideshow));
      });

      test('returns slideshow icon for .pptx extension', () {
        expect(getFileTypeIcon('presentation.pptx'), equals(Icons.slideshow));
      });
    });

    group('Image files', () {
      test('returns image icon for .png extension', () {
        expect(getFileTypeIcon('image.png'), equals(Icons.image));
      });

      test('returns image icon for .jpg extension', () {
        expect(getFileTypeIcon('photo.jpg'), equals(Icons.image));
      });

      test('returns image icon for .jpeg extension', () {
        expect(getFileTypeIcon('photo.jpeg'), equals(Icons.image));
      });

      test('returns image icon for .gif extension', () {
        expect(getFileTypeIcon('animation.gif'), equals(Icons.image));
      });

      test('returns image icon for .webp extension', () {
        expect(getFileTypeIcon('photo.webp'), equals(Icons.image));
      });

      test('returns image icon for .bmp extension', () {
        expect(getFileTypeIcon('bitmap.bmp'), equals(Icons.image));
      });
    });

    group('Text files', () {
      test('returns article icon for .txt extension', () {
        expect(getFileTypeIcon('notes.txt'), equals(Icons.article));
      });

      test('returns article icon for .md extension', () {
        expect(getFileTypeIcon('readme.md'), equals(Icons.article));
      });
    });

    group('Unknown/generic files', () {
      test('returns generic file icon for unknown extension', () {
        expect(getFileTypeIcon('data.xyz'), equals(Icons.insert_drive_file));
      });

      test('returns generic file icon for no extension', () {
        expect(getFileTypeIcon('README'), equals(Icons.insert_drive_file));
      });

      test('returns generic file icon for empty string', () {
        expect(getFileTypeIcon(''), equals(Icons.insert_drive_file));
      });

      test('returns generic file icon for path ending in slash', () {
        expect(getFileTypeIcon('/path/to/'), equals(Icons.insert_drive_file));
      });

      test('returns generic file icon for file ending with dot', () {
        expect(getFileTypeIcon('file.'), equals(Icons.insert_drive_file));
      });
    });

    group('case-insensitive matching', () {
      test('handles uppercase .PDF', () {
        expect(getFileTypeIcon('document.PDF'), equals(Icons.picture_as_pdf));
      });

      test('handles mixed case .PdF', () {
        expect(getFileTypeIcon('document.PdF'), equals(Icons.picture_as_pdf));
      });

      test('handles uppercase .DOCX', () {
        expect(getFileTypeIcon('document.DOCX'), equals(Icons.description));
      });

      test('handles uppercase .TXT', () {
        expect(getFileTypeIcon('notes.TXT'), equals(Icons.article));
      });

      test('handles uppercase .PNG', () {
        expect(getFileTypeIcon('image.PNG'), equals(Icons.image));
      });
    });

    group('edge cases', () {
      test('handles path with query string', () {
        expect(
          getFileTypeIcon('document.pdf?version=1'),
          equals(Icons.picture_as_pdf),
        );
      });

      test('handles path with fragment', () {
        expect(
          getFileTypeIcon('document.pdf#page=5'),
          equals(Icons.picture_as_pdf),
        );
      });

      test('handles filename with multiple dots', () {
        expect(
          getFileTypeIcon('report.final.v2.pdf'),
          equals(Icons.picture_as_pdf),
        );
      });

      test('handles hidden file with extension', () {
        expect(getFileTypeIcon('.hidden.txt'), equals(Icons.article));
      });

      test('handles hidden file without extension', () {
        expect(getFileTypeIcon('.gitignore'), equals(Icons.insert_drive_file));
      });
    });
  });

  group('documentDisplayName', () {
    test('returns filename from uri for file-path uri', () {
      const doc = RagDocument(
        id: 'doc-1',
        title: 'COMPLIANCE WITH THIS PUBLICATION IS MANDATORY',
        uri: 'airpubs/27sog/foo/afman_10-206.pdf',
      );
      expect(documentDisplayName(doc), equals('afman_10-206.pdf'));
    });

    test('falls back to title when uri is empty', () {
      const doc = RagDocument(id: 'doc-2', title: 'Question 1');
      expect(documentDisplayName(doc), equals('Question 1'));
    });

    test('falls back to title when uri is a UUID', () {
      const doc = RagDocument(
        id: 'doc-3',
        title: 'Question 1',
        uri: '4e8bf0c7-f504-4ffc-b647-a9f8f255bea5',
      );
      expect(documentDisplayName(doc), equals('Question 1'));
    });

    test('handles file:// prefixed uri', () {
      const doc = RagDocument(
        id: 'doc-4',
        title: 'BY ORDER OF THE SECRETARY OF THE AIR FORCE',
        uri: 'file:///data/airpubs/27sog/afman_10-206.pdf',
      );
      expect(documentDisplayName(doc), equals('afman_10-206.pdf'));
    });

    test('returns just filename for short uri', () {
      const doc = RagDocument(
        id: 'doc-5',
        title: 'PowerPoint Presentation',
        uri: 'slides.pptx',
      );
      expect(documentDisplayName(doc), equals('slides.pptx'));
    });

    test('handles uppercase UUID', () {
      const doc = RagDocument(
        id: 'doc-6',
        title: 'Question 2',
        uri: '4E8BF0C7-F504-4FFC-B647-A9F8F255BEA5',
      );
      expect(documentDisplayName(doc), equals('Question 2'));
    });
  });

  group('documentIconPath', () {
    test('returns uri when it is a file path', () {
      const doc = RagDocument(
        id: 'doc-1',
        title: 'COMPLIANCE',
        uri: 'airpubs/foo/afman.pdf',
      );
      expect(documentIconPath(doc), equals('airpubs/foo/afman.pdf'));
    });

    test('falls back to title when uri is empty', () {
      const doc = RagDocument(id: 'doc-2', title: 'report.pdf');
      expect(documentIconPath(doc), equals('report.pdf'));
    });

    test('falls back to title when uri is a UUID', () {
      const doc = RagDocument(
        id: 'doc-3',
        title: 'Question 1',
        uri: '4e8bf0c7-f504-4ffc-b647-a9f8f255bea5',
      );
      expect(documentIconPath(doc), equals('Question 1'));
    });
  });
}
