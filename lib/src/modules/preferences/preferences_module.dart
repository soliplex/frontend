import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/routes.dart';
import '../auth/server_manager.dart';
import 'bandwidth_preference.dart';
import 'preferences_screen.dart';

class PreferencesAppModule extends AppModule {
  PreferencesAppModule({
    required this.appName,
    required this.preference,
    required this.serverManager,
    this.logo,
  }) : _stopTracking = preference.trackServers(serverManager.servers);

  final String appName;
  final Widget? logo;
  final BandwidthPreference preference;
  final ServerManager serverManager;
  final void Function() _stopTracking;

  @override
  Future<void> onDispose() async => _stopTracking();

  @override
  String get namespace => 'preferences';

  @override
  ModuleRoutes build() => ModuleRoutes(
        // The connect screen's menu offers this page before any server is
        // connected, and the setting is the device's, not a session's.
        publicPaths: const {AppRoutes.preferences},
        routes: [
          GoRoute(
            path: AppRoutes.preferences,
            pageBuilder: (context, state) => NoTransitionPage(
              child: PreferencesScreen(
                appName: appName,
                logo: logo,
                preference: preference,
                servers: serverManager.servers,
              ),
            ),
          ),
        ],
      );
}
