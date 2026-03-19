import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/interfaces/auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/token_storage.dart';

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

ServerManager _createManager({InMemoryTokenStorage? storage}) {
  return ServerManager(
    authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
    clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
    storage: storage ?? InMemoryTokenStorage(),
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

    test('duplicate serverId throws StateError', () {
      final manager = _createManager();

      manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      expect(
        () => manager.addServer(
          serverId: 'test',
          serverUrl: Uri.parse('https://api2.example.com'),
        ),
        throwsStateError,
      );
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

      expect(
        () => manager.removeServer('nonexistent'),
        throwsStateError,
      );
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
  });

  group('persistence', () {
    test('login saves to storage', () async {
      final storage = InMemoryTokenStorage();
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

    test('logout deletes from storage', () async {
      final storage = InMemoryTokenStorage();
      final manager = _createManager(storage: storage);

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(provider: _provider, tokens: _tokens());
      entry.auth.logout();

      await Future<void>.delayed(Duration.zero);
      final stored = await storage.loadAll();
      expect(stored, isEmpty);
    });

    test('removeServer deletes from storage', () async {
      final storage = InMemoryTokenStorage();
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
  });

  group('restoreServers', () {
    test('recreates entries from storage', () async {
      final storage = InMemoryTokenStorage();
      final tokens = _tokens();

      // Pre-populate storage
      await storage.save(
        'restored',
        PersistedServer(
          serverUrl: Uri.parse('https://restored.example.com'),
          provider: _provider,
          tokens: tokens,
        ),
      );

      final manager = _createManager(storage: storage);
      await manager.restoreServers();

      expect(manager.servers.value, hasLength(1));
      expect(manager.servers.value['restored'], isNotNull);
      expect(
        manager.servers.value['restored']!.auth.isAuthenticated,
        isTrue,
      );
    });

    test('does not re-persist restored data', () async {
      final storage = InMemoryTokenStorage();

      await storage.save(
        'restored',
        PersistedServer(
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
  });
}
