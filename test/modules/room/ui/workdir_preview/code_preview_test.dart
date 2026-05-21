import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/code_preview.dart';

void main() {
  group('wrapInCodeFence', () {
    test('uses 3 backticks for content without backticks', () {
      final wrapped = wrapInCodeFence('print("hi")\n', 'python');
      expect(wrapped, '```python\nprint("hi")\n\n```');
    });

    test('extends the fence past the longest backtick run in the content', () {
      final wrapped =
          wrapInCodeFence('text with ```three``` then ``two``', 'plaintext');
      expect(wrapped.startsWith('````plaintext\n'), isTrue);
      expect(wrapped.endsWith('\n````'), isTrue);
    });

    test('preserves content verbatim between fences', () {
      const content = 'line 1\nline 2\nline 3';
      final wrapped = wrapInCodeFence(content, 'plaintext');
      // Sandwiched between opening "```plaintext\n" and closing "\n```".
      expect(wrapped, contains('\n$content\n'));
    });

    test('content ending with N backticks uses N+1 backticks for the fence',
        () {
      // CommonMark §4.5 requires the closing fence be strictly longer
      // than any backtick run inside. Content ending in exactly the
      // default 3-backtick fence length is the off-by-one trap: the
      // count must round up to 4, not stay at 3.
      final wrapped = wrapInCodeFence('payload ```', 'plaintext');
      expect(wrapped.startsWith('````plaintext\n'), isTrue,
          reason: 'opening fence must be 4 backticks: $wrapped');
      expect(wrapped.endsWith('\n````'), isTrue,
          reason: 'closing fence must be 4 backticks: $wrapped');
    });
  });
}
