import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import '../../helpers/test_server_entry.dart';

void main() {
  group('displayName', () {
    test('uses the human-readable name when present', () {
      final entry = createTestServerEntry(
        serverId: 'https://api.example.com',
        name: 'Demo Server',
      );
      expect(entry.displayName, 'Demo Server');
    });

    test('falls back to the formatted address when name is null', () {
      final entry = createTestServerEntry(serverId: 'https://api.example.com');
      expect(entry.displayName, 'https://api.example.com');
    });
  });

  group('listLabel', () {
    test('drops the scheme from an address', () {
      final entry = createTestServerEntry(serverId: 'https://api.example.com');
      expect(entry.listLabel, 'api.example.com');
    });

    test('never regexes a name that looks like a URL', () {
      // The bug this getter exists to avoid: running stripUrlScheme over
      // displayName mangles a name the operator actually chose.
      final entry = createTestServerEntry(
        serverId: 'https://api.example.com',
        name: 'https://prod (legacy)',
      );
      expect(entry.listLabel, 'https://prod (legacy)');
    });
  });

  group('bareAddress', () {
    test('is the address without its scheme, name or not', () {
      final named = createTestServerEntry(
        serverId: 'https://api.example.com',
        name: 'Demo Server',
      );
      expect(named.bareAddress, 'api.example.com');
    });
  });

  group('stripUrlScheme', () {
    test('drops a leading http(s) scheme', () {
      expect(stripUrlScheme('https://api.example.com'), 'api.example.com');
      expect(stripUrlScheme('http://localhost:8000'), 'localhost:8000');
    });

    test('leaves a label that carries no scheme alone', () {
      expect(stripUrlScheme('Demo Server'), 'Demo Server');
      expect(stripUrlScheme('localhost:8000'), 'localhost:8000');
    });

    test('only strips at the start, and only once', () {
      expect(
        stripUrlScheme('https://proxy.example.com/https://api.example.com'),
        'proxy.example.com/https://api.example.com',
      );
    });
  });

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

  group('serversInDisplayOrder', () {
    ServerEntry authSignedIn(String name) => createTestServerEntry(
          serverId: 'https://$name.example.com',
          requiresAuth: true,
          auth: authInActiveSession(),
          name: name,
        );
    ServerEntry authSignedOut(String name) => createTestServerEntry(
          serverId: 'https://$name.example.com',
          requiresAuth: true,
          name: name,
        );
    ServerEntry noAuth(String name) => createTestServerEntry(
          serverId: 'http://$name.local:8000',
          requiresAuth: false,
          name: name,
        );

    test('ranks signed-in auth, then signed-out auth, then no-auth', () {
      // Supplied in reverse rank order, and in reverse alphabetical order too,
      // so neither insertion order nor the name comparison alone can produce
      // the expected result.
      final ordered = serversInDisplayOrder([
        noAuth('zeta'),
        authSignedOut('yankee'),
        authSignedIn('xray'),
      ]);

      expect(
        ordered.map((e) => e.displayName),
        ['xray', 'yankee', 'zeta'],
      );
    });

    test('sorts alphabetically within a rank, ignoring case', () {
      final ordered = serversInDisplayOrder([
        authSignedIn('Charlie'),
        authSignedIn('alpha'),
        authSignedIn('Bravo'),
      ]);

      // Case-insensitive: a plain string sort would put every capitalised name
      // ahead of every lowercase one.
      expect(
        ordered.map((e) => e.displayName),
        ['alpha', 'Bravo', 'Charlie'],
      );
    });

    test('orders by the visible label, not the full address', () {
      // Same rank, different schemes, and no names — so the tiebreak reads the
      // address. Sorting the raw address instead of the label would compare
      // 'http:' against 'https:' before either host, putting zebra first.
      final ordered = serversInDisplayOrder([
        createTestServerEntry(serverId: 'http://zebra.example.com'),
        createTestServerEntry(serverId: 'https://apple.example.com'),
      ]);

      expect(
        ordered.map((e) => e.listLabel),
        ['apple.example.com', 'zebra.example.com'],
      );
    });
  });
}
