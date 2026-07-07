import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/keyed_storage.dart';

void main() {
  const p = 'soliplex_thread_read_marker';

  test('round-trips simple components', () {
    final key = encodeKey(p, ['s1', 'u1', 'r1', 't1']);
    expect(decodeKey(p, key), ['s1', 'u1', 'r1', 't1']);
  });

  test('round-trips components containing :, /, and #', () {
    final server = 'https://foo.com';
    final user = 'https://sso/realm#alice';
    final key = encodeKey(p, [server, user, 'r1']);
    // No raw delimiter leaks into the encoded key.
    expect(key.contains('https://'), isFalse);
    expect(decodeKey(p, key), [server, user, 'r1']);
  });

  test('decodeKey returns null for a different prefix', () {
    final key = encodeKey(p, ['s1']);
    expect(decodeKey('other_prefix', key), isNull);
  });

  test('decodeKey is not fooled by a prefix that is a substring', () {
    // 'pre' must not decode a 'prefix:...' key.
    final key = encodeKey('prefix', ['s1']);
    expect(decodeKey('pre', key), isNull);
  });

  test('serverKeyPrefix disambiguates a portless origin from an explicit port',
      () {
    // The colon-collision bug: origins omit default ports, so
    // "https://foo.com" is a raw-string prefix of "https://foo.com:8443".
    final portless = encodeKey(p, ['https://foo.com', 'r1']);
    final withPort = encodeKey(p, ['https://foo.com:8443', 'r1']);
    final sweep = serverKeyPrefix(p, 'https://foo.com');

    expect(portless.startsWith(sweep), isTrue);
    expect(withPort.startsWith(sweep), isFalse); // the fix
  });

  test('serverKeyPrefix matches encodeKey with serverId first', () {
    final key = encodeKey(p, ['s1', 'u1', 'r1']);
    expect(key.startsWith(serverKeyPrefix(p, 's1')), isTrue);
  });
}
