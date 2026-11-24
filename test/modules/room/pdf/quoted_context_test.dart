import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/quoted_context.dart';

void main() {
  const first = PdfQuote(
    text: 'Hybrid retrieval combining dense vectors with BM25 reduced it.',
    documentTitle: 'field-notes.pdf',
    pageNumber: 2,
  );
  const second = PdfQuote(
    text: 'Chunks shorter than 200 tokens lost the definitions.',
    documentTitle: 'field-notes.pdf',
    pageNumber: 4,
  );

  group('formatQuotedContext', () {
    test('writes a block closed by the file and page, then a blank line', () {
      expect(
        formatQuotedContext([first]),
        '> Hybrid retrieval combining dense vectors with BM25 reduced it.\n'
        '> — field-notes.pdf, p. 2\n'
        '\n',
      );
    });

    test('writes nothing for no quotes', () {
      expect(formatQuotedContext(const []), isEmpty);
    });

    test('collapses the line breaks a selection carries', () {
      const wrapped = PdfQuote(
          text: 'one\r\ntwo   three', documentTitle: 'a.pdf', pageNumber: 1);
      expect(formatQuotedContext([wrapped]), startsWith('> one two three\n'));
    });
  });

  group('parseQuotedContext', () {
    test('reads back several quotes and the question after them', () {
      final (:quotes, :rest) =
          parseQuotedContext('${formatQuotedContext([first, second])}Why?');
      expect(quotes, [first, second]);
      expect(rest, 'Why?');
    });

    test('reads back quotes sent with no question', () {
      final (:quotes, :rest) = parseQuotedContext(formatQuotedContext([first]));
      expect(quotes, [first]);
      expect(rest, isEmpty);
    });

    test('keeps a title that itself holds ", p. "', () {
      const odd = PdfQuote(
        text: 'x',
        documentTitle: 'Notes, p. 3 draft.pdf',
        pageNumber: 7,
      );
      final (:quotes, rest: _) = parseQuotedContext(formatQuotedContext([odd]));
      expect(quotes.single.documentTitle, 'Notes, p. 3 draft.pdf');
      expect(quotes.single.pageNumber, 7);
    });

    test("leaves a user's own quote, which names no file, in the text", () {
      const text = '> something I remember\n\nIs this right?';
      final (:quotes, :rest) = parseQuotedContext(text);
      expect(quotes, isEmpty);
      expect(rest, text);
    });

    test('stops at a block with no attribution after real quotes', () {
      final text = '${formatQuotedContext([first])}> my own aside\nOK?';
      final (:quotes, :rest) = parseQuotedContext(text);
      expect(quotes, [first]);
      expect(rest, '> my own aside\nOK?');
    });

    test('ignores an attribution line with no quote above it', () {
      const text = '> — a.pdf, p. 1\nhello';
      final (:quotes, :rest) = parseQuotedContext(text);
      expect(quotes, isEmpty);
      expect(rest, text);
    });

    test('a plain message is all text', () {
      final (:quotes, :rest) = parseQuotedContext('Just asking.');
      expect(quotes, isEmpty);
      expect(rest, 'Just asking.');
    });
  });

  group('splitQuotedParts', () {
    final image = ImagePart(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
      number: 1,
    );

    test('takes the quotes off the first text part', () {
      final (:quotes, :parts) = splitQuotedParts([
        TextPart(formatQuotedContext([first])),
        TextPart('What about '),
        image,
      ]);
      expect(quotes, [first]);
      expect(parts, hasLength(2), reason: 'the emptied part is dropped');
      expect((parts.first as TextPart).text, 'What about ');
    });

    test('keeps what follows the quotes in the same part', () {
      final (:quotes, :parts) = splitQuotedParts([
        TextPart('${formatQuotedContext([first])}Explain'),
        image,
      ]);
      expect(quotes, [first]);
      expect((parts.first as TextPart).text, 'Explain');
      expect(parts.last, same(image));
    });

    test('leaves parts without quotes alone', () {
      final original = <MessagePart>[TextPart('hi'), image];
      final (:quotes, :parts) = splitQuotedParts(original);
      expect(quotes, isEmpty);
      expect(parts, same(original));
    });

    test('leaves parts with no text alone', () {
      final original = <MessagePart>[image];
      expect(splitQuotedParts(original).parts, same(original));
    });
  });
}
