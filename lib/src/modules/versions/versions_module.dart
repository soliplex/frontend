import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/routes.dart';
import '../auth/require_connected_server.dart';
import '../auth/server_manager.dart';
import 'app_version_loader.dart';
import 'backend_version_fetcher.dart';
import 'server_versions_screen.dart';
import 'versions_screen.dart';

class VersionsAppModule extends AppModule {
  VersionsAppModule({
    required this.appName,
    required this.serverManager,
    AppVersionLoader? versionLoader,
    BackendVersionFetcher? versionFetcher,
  })  : _versionLoader = versionLoader ?? loadFlavorVersion,
        _versionFetcher = versionFetcher ?? fetchBackendVersionInfo;

  final String appName;
  final ServerManager serverManager;
  final AppVersionLoader _versionLoader;
  final BackendVersionFetcher _versionFetcher;

  @override
  String get namespace => 'versions';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(
            path: AppRoutes.versions,
            pageBuilder: (context, state) => NoTransitionPage(
              child: VersionsScreen(
                appName: appName,
                serverManager: serverManager,
                versionLoader: _versionLoader,
                versionFetcher: _versionFetcher,
              ),
            ),
          ),
          GoRoute(
            path: '/versions/server/:serverAlias',
            redirect: (context, state) => requireConnectedServer(
              serverManager,
              state.pathParameters['serverAlias'],
            ),
            pageBuilder: (context, state) {
              final alias = state.pathParameters['serverAlias']!;
              final entry = serverManager.entryByAlias(alias);
              if (entry == null) {
                // Redirect runs before the builder; the entry can disappear
                // in between.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => GoRouter.of(context).go(AppRoutes.versions),
                );
                return const NoTransitionPage(child: SizedBox.shrink());
              }
              return NoTransitionPage(
                child: ServerVersionsScreen(
                  serverEntry: entry,
                  versionFetcher: _versionFetcher,
                ),
              );
            },
          ),
        ],
      );
}
