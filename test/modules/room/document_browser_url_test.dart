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
}
