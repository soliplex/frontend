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

    test('grows monotonically with added text', () {
      const short = 'one two three';
      const long = '$short four five six seven eight';

      expect(
        estimateDraftTokens(long),
        greaterThan(estimateDraftTokens(short)),
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
