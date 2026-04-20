import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/interfaces/auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';

import '../../helpers/fakes.dart';

const _provider = OidcProvider(
  discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
  clientId: 'test-client',
);

AuthTokens _tokens() => AuthTokens(
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

ServerManager _createManager({InMemoryServerStorage? storage}) {
  return ServerManager(
    authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
    clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
    storage: storage ?? InMemoryServerStorage(),
  );
}

void main() {
  group('addServer', () {
    test('creates entry and updates servers signal', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      expect(entry.serverId, 'test');
      expect(manager.servers.value, hasLength(1));
      expect(manager.servers.value['test'], same(entry));
    });

    test('adds to registry', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      expect(manager.registry['test'], isNotNull);
    });

    test('duplicate serverId returns existing entry', () {
      final manager = _createManager();

      final first = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      final second = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api2.example.com'),
      );

      expect(second, same(first));
      expect(manager.servers.value, hasLength(1));
    });
  });

  group('alias', () {
    test('assigns alias from server URL', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'http://localhost:8000',
        serverUrl: Uri.parse('http://localhost:8000'),
      );

      expect(entry.alias, 'localhost-8000');
    });

    test('appends suffix on collision', () {
      final manager = _createManager();

      final first = manager.addServer(
        serverId: 'http://example.com',
        serverUrl: Uri.parse('http://example.com'),
      );
      final second = manager.addServer(
        serverId: 'https://example.com',
        serverUrl: Uri.parse('https://example.com'),
      );

      expect(first.alias, 'example-com');
      expect(second.alias, 'example-com-2');
    });

    test('entryByAlias returns matching entry', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'http://localhost:8000',
        serverUrl: Uri.parse('http://localhost:8000'),
      );

      expect(manager.entryByAlias('localhost-8000'), same(entry));
    });

    test('entryByAlias returns null for unknown alias', () {
      final manager = _createManager();
      expect(manager.entryByAlias('nonexistent'), isNull);
    });

    test('removeServer frees alias for reuse', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'http://example.com',
        serverUrl: Uri.parse('http://example.com'),
      );
      manager.removeServer('http://example.com');

      final reused = manager.addServer(
        serverId: 'https://example.com',
        serverUrl: Uri.parse('https://example.com'),
      );

      expect(reused.alias, 'example-com');
    });
  });

  group('removeServer', () {
    test('removes entry from servers and registry', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      manager.removeServer('test');

      expect(manager.servers.value, isEmpty);
      expect(manager.registry['test'], isNull);
    });

    test('missing serverId throws StateError', () {
      final manager = _createManager();

      expect(() => manager.removeServer('nonexistent'), throwsStateError);
    });
  });

  group('dispose', () {
    test('removes all servers', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'a',
        serverUrl: Uri.parse('https://a.example.com'),
      );
      manager.addServer(
        serverId: 'b',
        serverUrl: Uri.parse('https://b.example.com'),
      );

      manager.dispose();

      expect(manager.servers.value, isEmpty);
      expect(manager.registry.isEmpty, isTrue);
    });
  });

  group('authState', () {
    test('unauthenticated when no servers', () {
      final manager = _createManager();
      expect(manager.authState.value, isA<Unauthenticated>());
    });

    test('unauthenticated when servers exist but none authenticated', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      expect(manager.authState.value, isA<Unauthenticated>());
    });

    test('authenticated after login', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());

      expect(manager.authState.value, isA<Authenticated>());
    });

    test('unauthenticated after logout', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());
      entry.auth.logout();

      expect(manager.authState.value, isA<Unauthenticated>());
    });

    test('authenticated when no-auth server is added', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      expect(manager.authState.value, isA<Authenticated>());
    });
  });

  group('requiresAuth', () {
    test('defaults to true', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      expect(entry.requiresAuth, isTrue);
    });

    test('can be set to false', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      expect(entry.requiresAuth, isFalse);
    });

    test('isConnected is true when requiresAuth is false', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      expect(entry.isConnected, isTrue);
    });

    test(
      'isConnected is false when requiresAuth is true and not authenticated',
      () {
        final manager = _createManager();

        final entry = manager.addServer(
          serverId: 'test',
          serverUrl: Uri.parse('https://api.example.com'),
        );

        expect(entry.isConnected, isFalse);
      },
    );

    test('isConnected is true when requiresAuth is true and authenticated', () {
      final manager = _createManager();

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());

      expect(entry.isConnected, isTrue);
    });
  });

  group('persistence', () {
    test('login saves to storage', () async {
      final storage = InMemoryServerStorage();
      final manager = _createManager(storage: storage);

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());

      // Persistence is queued asynchronously
      await Future<void>.delayed(Duration.zero);
      final stored = await storage.loadAll();
      expect(stored, hasLength(1));
      expect(stored['test']!.serverUrl, Uri.parse('https://api.example.com'));
    });

    test('logout persists server without tokens', () async {
      final storage = InMemoryServerStorage();
      final manager = _createManager(storage: storage);

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());
      entry.auth.logout();

      await Future<void>.delayed(Duration.zero);
      final stored = await storage.loadAll();
      expect(stored, hasLength(1));
      expect(stored['test']!.serverUrl, Uri.parse('https://api.example.com'));
      expect(stored['test'], isA<KnownServer>());
    });

    test('removeServer deletes from storage', () async {
      final storage = InMemoryServerStorage();
      final manager = _createManager(storage: storage);

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());
      await Future<void>.delayed(Duration.zero);
      manager.removeServer('test');

      await Future<void>.delayed(Duration.zero);
      final stored = await storage.loadAll();
      expect(stored, isEmpty);
    });

    test('persists alias in storage', () async {
      final storage = InMemoryServerStorage();
      final manager = _createManager(storage: storage);

      final entry = manager.addServer(
        serverId: 'http://localhost:8000',
        serverUrl: Uri.parse('http://localhost:8000'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());

      await Future<void>.delayed(Duration.zero);
      final stored = await storage.loadAll();
      expect(stored['http://localhost:8000']!.alias, 'localhost-8000');
    });
  });

  group('restoreServers', () {
    test('recreates entries from storage', () async {
      final storage = InMemoryServerStorage();
      final tokens = _tokens();

      // Pre-populate storage
      await storage.save(
        'restored',
        AuthenticatedServer(
          serverUrl: Uri.parse('https://restored.example.com'),
          provider: _provider,
          tokens: tokens,
        ),
      );

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      expect(manager.servers.value, hasLength(1));
      expect(manager.servers.value['restored'], isNotNull);
      expect(manager.servers.value['restored']!.auth.isAuthenticated, isTrue);
    });

    test('does not re-persist restored data', () async {
      final storage = InMemoryServerStorage();

      await storage.save(
        'restored',
        AuthenticatedServer(
          serverUrl: Uri.parse('https://restored.example.com'),
          provider: _provider,
          tokens: _tokens(),
        ),
      );
      storage.saveCount = 0;

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      await Future<void>.delayed(Duration.zero);
      expect(storage.saveCount, 0);
    });

    test('restores logged-out server without authentication', () async {
      final storage = InMemoryServerStorage();

      await storage.save(
        'logged-out',
        KnownServer(serverUrl: Uri.parse('https://logged-out.example.com')),
      );

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      expect(manager.servers.value, hasLength(1));
      final entry = manager.servers.value['logged-out']!;
      expect(entry.auth.isAuthenticated, isFalse);
      expect(entry.serverUrl, Uri.parse('https://logged-out.example.com'));
    });

    test('restores requiresAuth flag', () async {
      final storage = InMemoryServerStorage();

      await storage.save(
        'no-auth',
        KnownServer(
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        ),
      );

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      final entry = manager.servers.value['no-auth']!;
      expect(entry.requiresAuth, isFalse);
      expect(entry.isConnected, isTrue);
    });

    test('restores persisted alias', () async {
      final storage = InMemoryServerStorage();

      await storage.save(
        'http://localhost:8000',
        KnownServer(
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
          alias: 'localhost-8000',
        ),
      );

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      final entry = manager.servers.value['http://localhost:8000']!;
      expect(entry.alias, 'localhost-8000');
    });

    test('generates alias when restoring legacy data without alias', () async {
      final storage = InMemoryServerStorage();

      await storage.save(
        'http://localhost:8000',
        KnownServer(
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        ),
      );

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      final entry = manager.servers.value['http://localhost:8000']!;
      expect(entry.alias, 'localhost-8000');
    });
  });
}
