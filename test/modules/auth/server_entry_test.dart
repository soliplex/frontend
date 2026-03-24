import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

void main() {
  group('aliasFromUrl', () {
    test('localhost with explicit port', () {
      expect(
        aliasFromUrl(Uri.parse('http://localhost:8000')),
        'localhost-8000',
      );
    });

    test('domain with default https port omitted', () {
      expect(
        aliasFromUrl(Uri.parse('https://api.example.com')),
        'api-example-com',
      );
    });

    test('domain with explicit non-default port', () {
      expect(
        aliasFromUrl(Uri.parse('https://foo.bar.com:9090')),
        'foo-bar-com-9090',
      );
    });

    test('IP address with port', () {
      expect(
        aliasFromUrl(Uri.parse('http://192.168.1.1:3000')),
        '192-168-1-1-3000',
      );
    });

    test('domain with default http port omitted', () {
      expect(
        aliasFromUrl(Uri.parse('http://example.com')),
        'example-com',
      );
    });
  });
}
