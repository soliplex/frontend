import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('estimateDraftTokens', () {
    test('an empty draft costs nothing', () {
      // Not the per-message overhead: a composer nobody is typing into
      // should not make the gauge twitch.
      expect(estimateDraftTokens(''), 0);
    });

    test('a short draft costs its overhead plus a little', () {
      final found = estimateDraftTokens('hello');

      expect(found, greaterThan(8));
      expect(found, lessThan(8 + 5));
    });

    test('reads high on English prose rather than low', () {
      // 'chars / 4' is the usual approximation for English. The estimate
      // must sit above it, because under-counting is the failure that
      // lets someone type into a window that is already full.
      const text = 'The quick brown fox jumps over the lazy dog, and then does '
          'it again because the first time was not convincing enough.';
      const naive = text.length ~/ 4;

      expect(estimateDraftTokens(text), greaterThan(naive));
    });

    test('does not read low on CJK', () {
      // A run of Han matches '\p{L}+' as one piece, which is where a
      // pre-tokenizer-shaped estimate would say "1 token" for text that
      // really costs about one token per character.
      const han = '这是一段中文文本用来测试分词器的行为';

      expect(estimateDraftTokens(han), greaterThanOrEqualTo(han.length));
    });

    test('counts JSON structure rather than collapsing it', () {
      // Tool results are JSON, and 'chars / 4' is badly wrong on it.
      const json = '{"id":1,"name":"widget","tags":["a","b"],"ok":true}';

      expect(estimateDraftTokens(json), greaterThan(json.length ~/ 4));
    });

    test('charges an image sent with no caption', () {
      // An image on its own is a message someone is writing. Read as an
      // empty draft it costs nothing, and a picture reaches the model
      // with the gauge saying the thread gained no tokens.
      expect(estimateDraftTokens('', images: 1), greaterThan(1000));
    });

    test('charges an image what a model will, not what its marker costs', () {
      // The composer names an image with a single code unit. Counted as
      // text that is a couple of tokens, against a real cost in the
      // thousands -- a picture read as a word.
      const draft = 'what do you make of this?';

      expect(estimateDraftTokens(draft), lessThan(30));
      expect(estimateDraftTokens(draft, images: 1), greaterThan(1000));
      expect(
        estimateDraftTokens(draft, images: 2) -
            estimateDraftTokens(draft, images: 1),
        2500,
      );
    });

    test('an image alone costs its flat price plus the message overhead', () {
      expect(estimateDraftTokens('', images: 1), 2500 + 8);
    });

    test('charges long runs more than one token', () {
      // Real BPE splits a long word further; a piece count alone would
      // read it as a single token.
      final one = estimateDraftTokens('a' * 6);
      final many = estimateDraftTokens('a' * 60);

      expect(many, greaterThan(one + 5));
    });

    group('exact estimates', () {
      // total = ceil(pieces * 1.2) + longRunPenalty + wideChars + images * 2500
      //         + 8, where a piece is a letter, digit or punctuation run with
      //         its leading space, a run over 6 characters adds
      //         (length - 6) ~/ 6, and every code unit past U+024F adds 1.

      test('plain English: nine pieces, margin 1.2', () {
        // 'The', ' quick', ' brown', ' fox', ' jumps', ' over', ' the',
        // ' lazy', ' dog': 9 pieces, none over 6 characters.
        // ceil(9 * 1.2) = ceil(10.8) = 11, plus the overhead of 8.
        expect(
          estimateDraftTokens('The quick brown fox jumps over the lazy dog'),
          11 + 8,
        );
      });

      test('a long run adds one token per six characters past six', () {
        // One piece each, so ceil(1.2) = 2 plus the overhead of 8.
        expect(estimateDraftTokens('a' * 6), 2 + 0 + 8);
        expect(estimateDraftTokens('a' * 11), 2 + (11 - 6) ~/ 6 + 8);
        expect(estimateDraftTokens('a' * 12), 2 + (12 - 6) ~/ 6 + 8);
        expect(estimateDraftTokens('a' * 60), 2 + (60 - 6) ~/ 6 + 8);
      });

      test('CJK charges every character again', () {
        // Eight Han characters are one piece of length 8: ceil(1.2) = 2,
        // penalty (8 - 6) ~/ 6 = 0, eight code units past U+024F, plus 8.
        expect(estimateDraftTokens('这是一段中文文本'), 2 + 0 + 8 + 8);
      });

      test('the extra charge starts just past Latin Extended-B', () {
        // One letter is one piece: ceil(1.2) = 2, plus the overhead of 8,
        // plus 1 only for a code unit above U+024F.
        expect(estimateDraftTokens('\u00E9'), 2 + 8);
        expect(estimateDraftTokens('\u024F'), 2 + 8);
        expect(estimateDraftTokens('\u0250'), 2 + 1 + 8);
      });

      test('an astral character is charged for both of its code units', () {
        // One punctuation-class piece: ceil(1.2) = 2, two surrogate units,
        // plus 8.
        expect(estimateDraftTokens('\u{1F600}'), 2 + 2 + 8);
      });

      test('a caption and an image add up', () {
        // 'what', ' is', ' this', '?': 4 pieces, ceil(4.8) = 5.
        expect(
          estimateDraftTokens('what is this?', images: 1),
          5 + 2500 + 8,
        );
      });
    });
  });
}
