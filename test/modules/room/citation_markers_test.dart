import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/citation_markers.dart';

const _a = '0b1c9f4e-6a2d-4e8b-9a51-3f7d2c8e1a01';
const _b = '7e3a2b10-5c4d-4f6e-8a9b-0c1d2e3f4a02';
const _c = 'c4d5e6f7-1a2b-4c3d-9e8f-7a6b5c4d3e03';
const _earlier = 'e1e2e3e4-1111-4222-8333-944455556604';

SourceReference _ref(String chunkId, {int? index}) => SourceReference(
      documentId: 'doc-$chunkId',
      documentUri: 'file://$chunkId.pdf',
      content: 'Content of $chunkId',
      chunkId: chunkId,
      index: index,
    );

String _plain(String text) =>
    md.markdownToHtml(text, extensionSet: md.ExtensionSet.gitHubFlavored);

/// [text] parsed with the citation syntax and the bubble's extension set,
/// rendered as HTML.
String _render(String text, Map<String, int> numbers) => md.markdownToHtml(
      text,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [CitationMarkerSyntax(numbers)],
    );

void main() {
  const numbers = {_a: 4, _b: 2};

  group('CitationMarkerSyntax', () {
    test('renders a cited id as its number, as plain text', () {
      expect(_render('Boils [$_a].', numbers), '<p>Boils [4].</p>\n');
    });

    test('splits a group separated by commas, semicolons or spaces', () {
      for (final group in ['$_a, $_b', '$_a; $_b', '$_a $_b', ' $_a, $_b, ']) {
        expect(
          _render('x [$group]', numbers),
          '<p>x [4][2]</p>\n',
          reason: group,
        );
      }
    });

    test('shows a number once when a group repeats a source', () {
      expect(_render('x [$_a, $_a]', numbers), '<p>x [4]</p>\n');
    });

    test('labels adjacent markers each', () {
      expect(_render('x [$_a][$_b]', numbers), '<p>x [4][2]</p>\n');
    });

    test('leaves a group with an escaped bracket as written', () {
      for (final text in [
        r'x \[' '$_a]',
        r'x \[' '$_a' r'\]',
        'x [$_a' r'\]',
        r'[see \[' '$_a](https://example.test)',
      ]) {
        expect(_render(text, numbers), _plain(text), reason: text);
      }
    });

    test('labels a marker right after an exclamation mark', () {
      expect(_render('Boils![$_a]', numbers), '<p>Boils![4]</p>\n');
    });

    test('labels a marker followed by parentheses that are not a link', () {
      expect(
        _render('Boils [$_a](p. 4).', numbers),
        '<p>Boils [4](p. 4).</p>\n',
      );
    });

    test('leaves a group with an unknown id, prose, a damaged id or no id', () {
      final damaged = _a.substring(0, _a.length - 1);
      for (final text in [
        'x [$_a, $_c]',
        'see [the appendix]',
        'x [$damaged]',
        '[ ]',
      ]) {
        expect(_render(text, numbers), _plain(text), reason: text);
      }
    });

    test('leaves a group markdown reads as a link or an image to markdown', () {
      for (final text in [
        '[$_a](https://example.test)',
        '[$_a][r]\n\n[r]: https://example.test',
        '[$_a]\n\n[$_a]: https://example.test',
        '![$_a](https://example.test/a.png)',
      ]) {
        expect(_render(text, numbers), _plain(text), reason: text);
      }
    });
  });

  group('answerCitationNumbers', () {
    test("gives this answer's ids their badge numbers", () {
      expect(
        answerCitationNumbers(
          own: [_ref(_a, index: 4), _ref(_b)],
          thread: const {},
        ),
        {_a: 4, _b: 2},
      );
    });

    test("names another answer's source by the thread's number", () {
      expect(
        answerCitationNumbers(own: [_ref(_a, index: 4)], thread: {_earlier: 7}),
        {_a: 4, _earlier: 7},
      );
    });

    test("prefers this answer's own badge over the thread's number", () {
      expect(
        answerCitationNumbers(own: [_ref(_a), _ref(_b)], thread: {_b: 9})[_b],
        2,
      );
    });
  });

  group('threadCitationNumbers', () {
    test('maps every indexed id across turns', () {
      final numbers = threadCitationNumbers([
        [_ref(_a, index: 1)],
        [_ref(_b, index: 2), _ref(_earlier)],
      ]);
      expect(numbers, {_a: 1, _b: 2});
    });
  });
}
