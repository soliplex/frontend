import 'package:flutter_test/flutter_test.dart';
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

String _markdown(String text, List<SourceReference> own,
        [Map<String, int> thread = const {}]) =>
    labelCitationMarkers(text, own: own, thread: thread, markdown: true);

String _plain(String text, List<SourceReference> own,
        [Map<String, int> thread = const {}]) =>
    labelCitationMarkers(text, own: own, thread: thread, markdown: false);

void main() {
  final own = [_ref(_a, index: 4), _ref(_b, index: 2)];

  group('labelCitationMarkers', () {
    test('shows a cited id as its badge number, without a link', () {
      expect(
        _markdown('Water boils at 100 °C [$_a].', own),
        'Water boils at 100 °C &#91;4&#93;.',
      );
    });

    test('plain text for the clipboard', () {
      expect(_plain('Boils [$_a].', own), 'Boils [4].');
    });

    test('splits a group separated by commas, semicolons or spaces', () {
      for (final group in ['$_a, $_b', '$_a; $_b', '$_a $_b']) {
        expect(
          _markdown('x [$group]', own),
          'x &#91;4&#93;&#91;2&#93;',
          reason: group,
        );
        expect(_plain('x [$group]', own), 'x [4][2]', reason: group);
      }
    });

    test('labels adjacent markers each', () {
      expect(_plain('x [$_a][$_b]', own), 'x [4][2]');
    });

    test('leaves a group alone when one id in it is unknown', () {
      final text = 'x [$_a, $_c]';
      expect(_markdown(text, own), text);
    });

    test('leaves bracketed prose and damaged ids alone', () {
      final damaged = _a.substring(0, _a.length - 1);
      for (final text in ['see [the appendix]', 'x [$damaged]', '[ ]']) {
        expect(_markdown(text, own), text);
      }
    });

    test('falls back to the list position when the index is missing', () {
      expect(_plain('x [$_b]', [_ref(_a), _ref(_b)]), 'x [2]');
    });

    test("names an earlier turn's source by its number", () {
      final thread = {_earlier: 7};
      expect(_markdown('x [$_earlier]', own, thread), 'x &#91;7&#93;');
      expect(_plain('x [$_earlier]', own, thread), 'x [7]');
    });

    test("prefers this answer's own badge over the thread's number", () {
      expect(_plain('x [$_b]', [_ref(_a), _ref(_b)], {_b: 9}), 'x [2]');
    });

    test("mixes this answer's and earlier-turn sources in one group", () {
      expect(
        _markdown('x [$_a, $_earlier]', own, {_earlier: 7}),
        'x &#91;4&#93;&#91;7&#93;',
      );
    });

    test('leaves markdown link text alone', () {
      final text = '[$_a](https://example.test)';
      expect(_markdown(text, own), text);
    });

    test('leaves inline code spans alone', () {
      final text = 'run `lookup [$_a]` then [$_a]';
      expect(
        _plain(text, own),
        'run `lookup [$_a]` then [4]',
      );
    });

    test('leaves fenced code blocks alone', () {
      final text = [
        'before [$_a]',
        '```json',
        '{"ids": [$_a]}',
        '```',
        'after [$_b]',
      ].join('\n');
      expect(
        _plain(text, own),
        [
          'before [4]',
          '```json',
          '{"ids": [$_a]}',
          '```',
          'after [2]',
        ].join('\n'),
      );
    });

    test('keeps a tilde fence open past a backtick line', () {
      final text = ['~~~', '```', '[$_a]', '~~~', '[$_a]'].join('\n');
      expect(
        _plain(text, own),
        ['~~~', '```', '[$_a]', '~~~', '[4]'].join('\n'),
      );
    });

    test('returns the text unchanged with nothing to label against', () {
      final text = 'x [$_a]';
      expect(_markdown(text, const []), text);
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
