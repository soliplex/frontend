import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/markdown/sanitize_markdown.dart';

void main() {
  group('sanitizeMarkdown', () {
    test('replaces <br/> with newline', () {
      expect(sanitizeMarkdown('line1<br/>line2'), 'line1\nline2');
    });

    test('replaces <br /> (space before slash) with newline', () {
      expect(sanitizeMarkdown('line1<br />line2'), 'line1\nline2');
    });

    test('replaces multiple br tags', () {
      expect(sanitizeMarkdown('a<br/>b<br />c'), 'a\nb\nc');
    });

    test('returns unchanged string when no br tags present', () {
      expect(sanitizeMarkdown('plain text'), 'plain text');
    });
  });
}
