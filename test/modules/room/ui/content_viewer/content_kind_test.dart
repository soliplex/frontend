import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/content_kind.dart';

void main() {
  group('contentKindOf', () {
    test('svg is case-insensitive', () {
      expect(contentKindOf('svg'), ContentKind.svg);
      expect(contentKindOf('SVG'), ContentKind.svg);
    });

    test('every other language is code', () {
      for (final language in const [
        'json',
        'python',
        'plaintext',
        'mermaid',
      ]) {
        expect(contentKindOf(language), ContentKind.code, reason: language);
      }
    });
  });

  group('fenceLanguage', () {
    test('lower-cases the language', () {
      expect(fenceLanguage('JSON'), 'json');
    });

    test('keeps only the first word of the info string', () {
      expect(fenceLanguage('svg title="x"'), 'svg');
    });

    test('a missing or empty info string is plaintext', () {
      expect(fenceLanguage(null), 'plaintext');
      expect(fenceLanguage(''), 'plaintext');
    });
  });
}
