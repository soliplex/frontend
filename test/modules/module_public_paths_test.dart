import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_module.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/diagnostics_module.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/network_inspector.dart';

import '../helpers/fakes.dart';

ServerManager _serverManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  testWidgets('a signed-out user reaches the inspector through the shell',
      (tester) async {
    // The behaviour the diagnostics comment defends: a user who cannot sign in
    // is unauthenticated by definition, and this screen is where the failure is
    // visible. Composed end to end, because no single module decides it any
    // more — the module declares, the shell admits.
    final serverManager = _serverManager();
    final config = ShellConfig.fromModules(
      modules: [
        AuthAppModule(
          serverManager: serverManager,
          probeClient: FakeHttpClient(),
          authFlow: FakeAuthFlow(),
          appName: 'Soliplex',
          inactivityLogoutFlags: InMemoryInactivityLogoutFlagStorage(),
        ),
        DiagnosticsAppModule(
          appName: 'Soliplex',
          inspector: NetworkInspector(),
        ),
      ],
      appName: 'Soliplex',
      lightTheme: buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      ),
    );
    addTearDown(config.dispose);

    final router = buildRouter(config);
    await tester.pumpWidget(
      ProviderScope(
        overrides: config.overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go(AppRoutes.diagnostics);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.diagnostics,
    );
  });
}
