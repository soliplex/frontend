import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentRef.parse', () {
    test('treats a uri with no fragment as a plain document', () {
      final ref = DocumentRef.parse('file:///docs/annual-report.pdf');

      expect(ref.rootUri, 'file:///docs/annual-report.pdf');
      expect(ref.attachmentPath, isEmpty);
      expect(ref.isAttachment, isFalse);
      expect(ref.displayName, 'annual-report.pdf');
      expect(ref.ancestorNames, isEmpty);
    });

    test('splits a single attachment segment off the root uri', () {
      final ref = DocumentRef.parse(
        'file:///docs/annual-report.pdf#attachment=budget.xlsx',
      );

      expect(ref.rootUri, 'file:///docs/annual-report.pdf');
      expect(ref.attachmentPath, ['budget.xlsx']);
      expect(ref.isAttachment, isTrue);
      expect(ref.displayName, 'budget.xlsx');
      expect(ref.ancestorNames, ['annual-report.pdf']);
    });

    test('splits both segments of a nested attachment uri', () {
      final ref = DocumentRef.parse(
        'file:///docs/a.pdf#attachment=b.pdf#attachment=inner.xlsx',
      );

      expect(ref.rootUri, 'file:///docs/a.pdf');
      expect(ref.attachmentPath, ['b.pdf', 'inner.xlsx']);
      expect(ref.displayName, 'inner.xlsx');
      expect(ref.ancestorNames, ['a.pdf', 'b.pdf']);
    });

    test('decodes percent-escaped spaces and parentheses', () {
      final ref = DocumentRef.parse(
        'file:///docs/annual-report.pdf'
        '#attachment=my%20report%20%28final%29.pdf',
      );

      expect(ref.displayName, 'my report (final).pdf');
    });

    test('decodes a non-ASCII name delivered decomposed', () {
      final ref = DocumentRef.parse(
        'file:///docs/annual-report.pdf#attachment=resume%CC%81.pdf',
      );

      // This name arrives decomposed: `e` plus combining acute U+0301, which
      // renders as an accented e but does not equal the precomposed form. The
      // expectation spells the combining mark out so the two cannot be
      // confused by a reader or an editor that normalises the file.
      expect(ref.displayName, 'resume\u0301.pdf');
    });

    test('keeps a segment verbatim when it is not valid percent-encoding', () {
      final ref = DocumentRef.parse('file:///docs/a.pdf#attachment=100%.xlsx');

      expect(ref.displayName, '100%.xlsx');
    });

    test('substitutes bytes that are not legal utf-8', () {
      // Correct escape syntax, so these decode to bytes, but %FF is not a legal
      // UTF-8 byte and %C3 opens a sequence that never finishes. Each bad byte
      // becomes U+FFFD rather than aborting the whole name.
      expect(
        DocumentRef.parse('file:///docs/a.pdf#attachment=%FF.xlsx').displayName,
        '\uFFFD.xlsx',
      );
      expect(
        DocumentRef.parse('file:///docs/%C3.pdf').displayName,
        '\uFFFD.pdf',
      );
    });

    test('decodes lowercase escapes', () {
      // Escape matching is case-insensitive: the backend's `quote` emits
      // uppercase, but an ingested http URL can carry either.
      final ref = DocumentRef.parse('file:///docs/caf%c3%a9.pdf');

      expect(ref.displayName, 'café.pdf');
    });

    test('keeps a raw non-ASCII character', () {
      final ref = DocumentRef.parse('file:///docs/\u{1F642}.pdf');

      expect(ref.displayName, '\u{1F642}.pdf');
    });

    test('ignores an empty attachment name', () {
      final ref = DocumentRef.parse('file:///docs/a.pdf#attachment=');

      expect(ref.rootUri, 'file:///docs/a.pdf');
      expect(ref.attachmentPath, isEmpty);
      expect(ref.isAttachment, isFalse);
      expect(ref.displayName, 'a.pdf');
    });

    test('has no name for an attachment named only whitespace', () {
      // Unlike the empty segment above, this is a real name, so the level is
      // kept and the ancestors still say where the file came from. Only the
      // label is unusable, and it has to read as absent rather than as a name
      // that happens to render as nothing.
      final ref = DocumentRef.parse('file:///docs/a.pdf#attachment=%20%20');

      expect(ref.isAttachment, isTrue);
      expect(ref.displayName, isNull);
      expect(ref.ancestorNames, ['a.pdf']);
    });

    test('trims a name padded with escaped whitespace', () {
      // The padding is invisible in a label, and it would otherwise reach the
      // extension logic, which reads 'xlsx ' and matches no file-type glyph.
      expect(
        DocumentRef.parse('file:///docs/a.pdf#attachment=%20budget.xlsx%20')
            .displayName,
        'budget.xlsx',
      );
      expect(
        DocumentRef.parse('file:///docs/report.pdf%20').displayName,
        'report.pdf',
      );
    });

    test('parses a string that is not a valid uri', () {
      final ref = DocumentRef.parse('::not a uri::#attachment=budget.xlsx');

      expect(ref.rootUri, '::not a uri::');
      expect(ref.displayName, 'budget.xlsx');
    });

    test('does not treat a page fragment as an attachment', () {
      final ref = DocumentRef.parse('file:///docs/a.pdf#page=3');

      expect(ref.isAttachment, isFalse);
      expect(ref.attachmentPath, isEmpty);
      expect(ref.displayName, 'a.pdf');
      // The fragment stays on rootUri: only attachment segments are stripped,
      // so a resolver receives the URI it was given.
      expect(ref.rootUri, 'file:///docs/a.pdf#page=3');
    });

    test('drops a query string from the name', () {
      final ref = DocumentRef.parse('https://example.test/docs/doc.pdf?v=1');

      expect(ref.displayName, 'doc.pdf');
    });

    test('keeps an escaped delimiter inside a plain document name', () {
      // The split must run on the encoded form. Decoding first would turn
      // these escapes into delimiters and truncate both names to 'my'.
      expect(
        DocumentRef.parse('file:///docs/my%23file.pdf').displayName,
        'my#file.pdf',
      );
      expect(
        DocumentRef.parse('file:///docs/my%3Ffile.pdf').displayName,
        'my?file.pdf',
      );
    });

    test('truncates a name at an unescaped delimiter', () {
      // Pins the trade documented on `_rootFileName`: the same split that
      // resolves `a.pdf#page=3` to `a.pdf` also ends a name at a `#` that was
      // really part of it.
      expect(
        DocumentRef.parse('https://dav.test/docs/report #2.pdf').displayName,
        'report',
      );
      expect(
        DocumentRef.parse('s3://bucket/summary#final.pdf').displayName,
        'summary',
      );
    });

    test('does not fabricate a nesting level from an escaped marker', () {
      // `parse` splits before decoding for the same reason the name logic
      // does. Decoding first would read this single attachment as two levels.
      final ref = DocumentRef.parse(
        'file:///docs/a.pdf#attachment=notes%23attachment%3Dx.pdf',
      );

      expect(ref.attachmentPath, ['notes#attachment=x.pdf']);
      expect(ref.displayName, 'notes#attachment=x.pdf');
      expect(ref.ancestorNames, ['a.pdf']);
    });

    test('has no name when the root names no file', () {
      // Callers supply their own label; nothing here invents one.
      expect(DocumentRef.parse('file:///docs/').displayName, isNull);
      expect(DocumentRef.parse('').displayName, isNull);
    });

    test('ancestorNames omits a level with a blank name', () {
      // A blank entry would render as a dangling separator once these are
      // joined, so it is dropped at every level, not only at the root.
      expect(
        DocumentRef.parse('file:///docs/#attachment=b.xlsx').ancestorNames,
        isEmpty,
      );
      expect(
        DocumentRef.parse(
          'file:///docs/a.pdf#attachment=%20%20#attachment=c.xlsx',
        ).ancestorNames,
        ['a.pdf'],
      );
    });

    test('reads a bare filename with no path separator', () {
      final ref = DocumentRef.parse('slides.pptx');

      expect(ref.displayName, 'slides.pptx');
    });
  });
}
