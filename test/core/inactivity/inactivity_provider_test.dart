import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Signal;
import 'package:soliplex_frontend/src/core/inactivity/inactivity_config.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_provider.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_inactivity_sessions.dart';

void main() {
  group('inactivityMonitorProvider', () {
    test('is null when nothing supplies the sessions', () {
      // No auth module: the shell stays bootable with inactivity logout
      // disabled.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(inactivityMonitorProvider), isNull);
    });

    test('builds a monitor over the supplied sessions', () {
      final container = ProviderContainer(
        overrides: [
          inactivitySessionsProvider.overrideWithValue(
            ServerInactivitySessions(
              servers: Signal<Map<String, ServerEntry>>({}),
            ),
          ),
          inactivityConfigProvider.overrideWithValue(InactivityConfig.disabled),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(inactivityMonitorProvider), isNotNull);
    });
  });
}
