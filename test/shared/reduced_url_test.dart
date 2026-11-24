import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/reduced_url.dart';

void main() {
  test('keeps scheme, host, port and path', () {
    expect(
      reducedUrl('https://cdn.example.com:8443/files/a.pdf'),
      'https://cdn.example.com:8443/files/a.pdf',
    );
  });

  test('drops the query, the fragment and user info', () {
    expect(
      reducedUrl('https://user:secret@example.com/a.pdf?sig=abc&token=x#p=2'),
      'https://example.com/a.pdf',
    );
  });

  test('says <url> for what does not parse', () {
    expect(reducedUrl('http://[::1'), '<url>');
  });
}
