import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/routes.dart';
import 'diagnostics_providers.dart';
import 'network_inspector.dart';
import 'ui/diagnostics_screen.dart';

class DiagnosticsAppModule extends AppModule {
  DiagnosticsAppModule({
    required this.appName,
    required this.inspector,
    this.logo,
  });

  final String appName;
  final Widget? logo;
  final NetworkInspector inspector;

  @override
  String get namespace => 'diagnostics';

  @override
  ModuleRoutes build() => ModuleRoutes(
        overrides: [
          networkInspectorProvider.overrideWithValue(inspector),
        ],
        routes: [
          GoRoute(
            path: AppRoutes.diagnostics,
            builder: (context, state) => DiagnosticsScreen(
              appName: appName,
              logo: logo,
              initialRunId: state.uri.queryParameters['run'],
              inspector: inspector,
            ),
          ),
        ],
      );

  @override
  Future<void> onDispose() async => inspector.dispose();
}
