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

      expect(found, greaterThan(perMessageOverhead));
      expect(found, lessThan(perMessageOverhead + 5));
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
        perImageTokens,
      );
    });

    test('charges long runs more than one token', () {
      // Real BPE splits a long word further; a piece count alone would
      // read it as a single token.
      final one = estimateDraftTokens('a' * 6);
      final many = estimateDraftTokens('a' * 60);

      expect(many, greaterThan(one + 5));
    });
  });
}
