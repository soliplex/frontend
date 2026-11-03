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

/// [text] parsed the way the answer bubble parses it, rendered as HTML.
String _render(String text, Map<String, int> numbers) => md.markdownToHtml(
      text,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [CitationMarkerSyntax(numbers)],
    );

void main() {
  const numbers = {_a: 4, _b: 2};

  group('labelCitationMarkers', () {
    test('shows a cited id as its number', () {
      expect(
        labelCitationMarkers('Boils at 100 °C [$_a].', numbers),
        'Boils at 100 °C [4].',
      );
    });

    test('splits a group separated by commas, semicolons or spaces', () {
      for (final group in ['$_a, $_b', '$_a; $_b', '$_a $_b']) {
        expect(
          labelCitationMarkers('x [$group]', numbers),
          'x [4][2]',
          reason: group,
        );
      }
    });

    test('shows a number once when a group repeats a source', () {
      expect(labelCitationMarkers('x [$_a, $_a]', numbers), 'x [4]');
    });

    test('labels adjacent markers each', () {
      expect(labelCitationMarkers('x [$_a][$_b]', numbers), 'x [4][2]');
    });

    test('labels a marker whose bracket is escaped', () {
      expect(labelCitationMarkers(r'x \[' '$_a]', numbers), 'x [4]');
    });

    test('leaves a group alone when one id in it is unknown', () {
      final text = 'x [$_a, $_c]';
      expect(labelCitationMarkers(text, numbers), text);
    });

    test('leaves bracketed prose and damaged ids alone', () {
      final damaged = _a.substring(0, _a.length - 1);
      for (final text in ['see [the appendix]', 'x [$damaged]', '[ ]']) {
        expect(labelCitationMarkers(text, numbers), text);
      }
    });

    test('leaves markdown link text alone', () {
      final text = '[$_a](https://example.test)';
      expect(labelCitationMarkers(text, numbers), text);
    });

    test('labels every marker in the text, code included', () {
      expect(
        labelCitationMarkers('run `lookup [$_a]`', numbers),
        'run `lookup [4]`',
      );
    });
  });

  group('CitationMarkerSyntax', () {
    test('renders a cited id as its number, as plain text', () {
      expect(_render('Boils [$_a, $_b].', numbers), '<p>Boils [4][2].</p>\n');
    });

    test('renders a number right after inline code', () {
      expect(
        _render('set `timeout`[$_a]', numbers),
        '<p>set <code>timeout</code>[4]</p>\n',
      );
    });

    test('leaves ids in code spans and code blocks as written', () {
      final html = _render(
        [
          'run `lookup [$_a]`',
          '',
          '    indented [$_a]',
          '',
          '```md',
          '```python',
          '[$_a]',
          '```',
        ].join('\n'),
        numbers,
      );
      expect(html, isNot(contains('[4]')));
      expect('[$_a]'.allMatches(html), hasLength(3));
    });

    test('leaves an unknown group to the rest of the parser', () {
      expect(
        _render('[$_c](https://example.test) and [prose]', numbers),
        '<p><a href="https://example.test">$_c</a> and [prose]</p>\n',
      );
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

    test('a source cited again in a later turn keeps its number', () {
      final numbers = threadCitationNumbers([
        [_ref(_a, index: 1)],
        [_ref(_b, index: 2), _ref(_a, index: 1)],
      ]);
      expect(numbers[_a], 1);
    });
  });

  test('citationBadgeNumber prefers the index over the position', () {
    expect(citationBadgeNumber(_ref(_a, index: 9), 0), 9);
    expect(citationBadgeNumber(_ref(_a), 2), 3);
  });
}
