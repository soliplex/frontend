import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/require_connected_server.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  group('requireConnectedServer', () {
    late ServerManager serverManager;

    setUp(() {
      serverManager = _createManager();
    });

    test('returns /lobby when alias is null', () {
      expect(requireConnectedServer(serverManager, null), '/lobby');
    });

    test('returns /lobby when alias not found', () {
      expect(
        requireConnectedServer(serverManager, 'nonexistent'),
        '/lobby',
      );
    });

    test('returns /lobby when server exists but not connected', () {
      final entry = serverManager.addServer(
        serverId: 'srv-1',
        serverUrl: Uri.parse('https://example.com'),
      );

      expect(entry.isConnected, isFalse);
      expect(requireConnectedServer(serverManager, entry.alias), '/lobby');
    });

    test('returns null when server is connected', () {
      final entry = serverManager.addServer(
        serverId: 'srv-1',
        serverUrl: Uri.parse('https://example.com'),
        requiresAuth: false,
      );

      expect(entry.isConnected, isTrue);
      expect(requireConnectedServer(serverManager, entry.alias), isNull);
    });
  });
}
