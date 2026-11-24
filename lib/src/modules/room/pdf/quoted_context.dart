import 'package:soliplex_client/soliplex_client.dart'
    show MessagePart, TextPart;

import 'pdf_quote.dart';

/// Collapses every run of whitespace, line breaks included, to one space.
String collapseWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The line that closes each quote block: `> — <file>, p. <page>`. The file
/// is matched greedily, so a title that itself holds ", p. " still parses.
/// The page is at most nine digits, past any real document, so it parses
/// exactly everywhere: a long enough run overflows an `int` on native and
/// loses precision on the web.
final _attribution = RegExp(r'^> — (.+), p\. (\d{1,9})$');

/// [quotes] as markdown quote blocks, each closed by an attribution line
/// naming its file and page and followed by a blank line; empty for none.
///
/// ```text
/// > Hybrid retrieval combining dense vectors with BM25 reduced …
/// > — retrieval-field-notes.pdf, p. 2
///
/// ```
///
/// Prepended to what the user typed, so the model reads the passages before
/// the question about them. The trailing blank line keeps the last block
/// apart from that text: parts are joined with no separator.
String formatQuotedContext(List<PdfQuote> quotes) {
  final buffer = StringBuffer();
  for (final quote in quotes) {
    buffer
      ..writeln('> ${collapseWhitespace(quote.text)}')
      ..writeln('> — ${quote.documentTitle}, p. ${quote.pageNumber}')
      ..writeln();
  }
  return buffer.toString();
}

/// Splits a sent message into the quote blocks [formatQuotedContext] put at
/// its start and the text after them.
///
/// Only a block closed by an attribution line counts, so a quote the user
/// typed themselves stays in the text.
({List<PdfQuote> quotes, String rest}) parseQuotedContext(String message) {
  final lines = message.split('\n');
  final quotes = <PdfQuote>[];
  var index = 0;
  while (index < lines.length) {
    final body = <String>[];
    var cursor = index;
    while (cursor < lines.length &&
        lines[cursor].startsWith('> ') &&
        !_attribution.hasMatch(lines[cursor])) {
      body.add(lines[cursor].substring(2));
      cursor++;
    }
    final match = cursor < lines.length && body.isNotEmpty
        ? _attribution.firstMatch(lines[cursor])
        : null;
    if (match == null) break;
    quotes.add(
      PdfQuote(
        text: body.join(' '),
        documentTitle: match.group(1)!,
        pageNumber: int.parse(match.group(2)!),
      ),
    );
    index = cursor + 1;
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
  }
  if (quotes.isEmpty) return (quotes: const [], rest: message);
  return (quotes: quotes, rest: lines.skip(index).join('\n'));
}

/// [parseQuotedContext] over a message that arrived as parts: the quotes
/// lead its first text part, which comes back without them — and is dropped
/// if they were all it held.
({List<PdfQuote> quotes, List<MessagePart> parts}) splitQuotedParts(
  List<MessagePart> parts,
) {
  final first = parts.indexWhere((part) => part is TextPart);
  if (first < 0) return (quotes: const [], parts: parts);
  final (:quotes, :rest) = parseQuotedContext((parts[first] as TextPart).text);
  if (quotes.isEmpty) return (quotes: const [], parts: parts);
  return (
    quotes: quotes,
    parts: [
      ...parts.take(first),
      if (rest.isNotEmpty) TextPart(rest),
      ...parts.skip(first + 1),
    ],
  );
}
