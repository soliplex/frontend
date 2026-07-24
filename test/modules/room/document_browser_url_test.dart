import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/document_browser_url.dart';

void main() {
  test('the default resolver resolves nothing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(documentBrowserUrlResolverProvider)('file:///x/a.pdf'),
      isNull,
    );
  });

  group('resolveDocumentBrowserUrl', () {
    Uri? noResolve(String _) => null;

    test('prefers the source_url', () {
      expect(
        resolveDocumentBrowserUrl(
          noResolve,
          sourceUrl: Uri.parse('https://viewer.test/view'),
          documentUri: 'file:///x/a.pdf',
        ),
        Uri.parse('https://viewer.test/view'),
      );
    });

    test('uses a resolver-derived web url when source_url is absent', () {
      expect(
        resolveDocumentBrowserUrl(
          (_) => Uri.parse('https://viewer.test/derived'),
          sourceUrl: null,
          documentUri: 'file:///x/a.pdf',
        ),
        Uri.parse('https://viewer.test/derived'),
      );
    });

    test('is null when the resolver returns nothing', () {
      expect(
        resolveDocumentBrowserUrl(
          noResolve,
          sourceUrl: null,
          documentUri: 'file:///x/a.pdf',
        ),
        isNull,
      );
    });

    test('rejects a resolver result that is not a web url', () {
      expect(
        resolveDocumentBrowserUrl(
          (_) => Uri.parse('file:///nope.pdf'),
          sourceUrl: null,
          documentUri: 'file:///x/a.pdf',
        ),
        isNull,
      );
    });

    test('degrades to null when the resolver throws', () {
      expect(
        resolveDocumentBrowserUrl(
          (_) => throw const FormatException('bad derived url'),
          sourceUrl: null,
          documentUri: 'file:///x/a.pdf',
        ),
        isNull,
      );
    });
  });
}
