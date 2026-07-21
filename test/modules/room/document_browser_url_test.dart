import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/document_browser_url.dart';

void main() {
  test('default resolver resolves nothing', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(
        c.read(documentBrowserUrlResolverProvider)('file:///x/a.pdf'), isNull);
  });

  test('an override supplies a resolver', () {
    final c = ProviderContainer(overrides: [
      documentBrowserUrlResolverProvider.overrideWithValue(
        (uri) => Uri.parse('https://example.test/a/view'),
      ),
    ]);
    addTearDown(c.dispose);
    expect(
      c.read(documentBrowserUrlResolverProvider)('file:///x/a.pdf'),
      Uri.parse('https://example.test/a/view'),
    );
  });
}
