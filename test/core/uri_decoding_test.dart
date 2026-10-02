import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/uri_decoding.dart';

void main() {
  group('isDecodable', () {
    test('accepts plain and stray-escape routes', () {
      expect(isDecodable(Uri.parse('/room/a/b?x=1')), isTrue);
      expect(isDecodable(Uri.parse('/room/%25ZZ/x')), isTrue);
    });

    test('rejects an undecodable path', () {
      expect(isDecodable(Uri.parse('/room/%FF/x')), isFalse);
    });

    test('rejects an undecodable query', () {
      expect(isDecodable(Uri.parse('/lobby?server=%FF')), isFalse);
    });
  });
}
