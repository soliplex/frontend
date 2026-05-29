import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_config.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_monitor.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_provider.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

ServerManager _serverManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  group('inactivityMonitorProvider', () {
    test('is null when the auth-module providers are not overridden', () {
      // Their defaults throw UnimplementedError; the shell stays bootable
      // with inactivity logout disabled.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(inactivityMonitorProvider), isNull);
    });

    test('returns a monitor when the dependencies are configured', () {
      final container = ProviderContainer(
        overrides: [
          inactivityConfigProvider.overrideWithValue(const InactivityConfig()),
          serverManagerProvider.overrideWithValue(_serverManager()),
          inactivityLogoutFlagsProvider
              .overrideWithValue(InMemoryInactivityLogoutFlagStorage()),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(inactivityMonitorProvider),
        isA<InactivityMonitor>(),
      );
    });
  });
}
