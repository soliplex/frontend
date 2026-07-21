// test/shared/browser_url_link_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';

void main() {
  group('browserUrlDisplay', () {
    test('strips scheme, keeps host and path', () {
      expect(
        browserUrlDisplay(Uri.parse('https://example.test/a/b.pdf/view')),
        'example.test/a/b.pdf/view',
      );
    });

    test('drops query and fragment', () {
      expect(
        browserUrlDisplay(Uri.parse('https://example.test/a?x=1#f')),
        'example.test/a',
      );
    });
  });

  group('sourceUrlFromMetadata', () {
    test('parses an http(s) source_url', () {
      expect(
        sourceUrlFromMetadata({'source_url': 'https://example.test/a/view'}),
        Uri.parse('https://example.test/a/view'),
      );
    });

    test('returns null when key is absent', () {
      expect(sourceUrlFromMetadata({'other': 'x'}), isNull);
    });

    test('returns null for empty, non-string, or non-http values', () {
      expect(sourceUrlFromMetadata({'source_url': ''}), isNull);
      expect(sourceUrlFromMetadata({'source_url': 42}), isNull);
      expect(sourceUrlFromMetadata({'source_url': 'file:///x/a.pdf'}), isNull);
    });
  });
}
