import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client_native/soliplex_client_native.dart';

import '../core/shell_config.dart';
import '../core/signal_listenable.dart';
import '../modules/auth/auth_module.dart';
import '../modules/auth/secure_token_storage.dart';
import '../modules/auth/server_manager.dart';
import '../modules/diagnostics/diagnostics_module.dart';
import '../modules/diagnostics/network_inspector.dart';

Future<ShellConfig> standard({
  String appName = 'Soliplex',
  ThemeData? theme,
}) async {
  final inspector = NetworkInspector();
  final refreshClient = createAgentHttpClient(
    innerClient: createPlatformClient(),
    observers: [inspector],
  );
  final serverManager = ServerManager(
    refreshClient: refreshClient,
    inspector: inspector,
    storage: SecureTokenStorage(),
  );
  await serverManager.restoreServers();

  final authListenable = SignalListenable(serverManager.authState);

  return ShellConfig(
    appName: appName,
    theme: theme ?? ThemeData(),
    refreshListenable: authListenable,
    onDispose: () {
      authListenable.dispose();
      serverManager.dispose();
    },
    modules: [
      diagnosticsModule(inspector: inspector),
      authModule(serverManager: serverManager),
      ModuleContribution(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: Center(child: Text('Soliplex')),
            ),
          ),
        ],
      ),
    ],
  );
}
