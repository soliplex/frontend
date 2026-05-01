import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/routes.dart';
import 'diagnostics_providers.dart';
import 'network_inspector.dart';
import 'ui/network_inspector_screen.dart';

class DiagnosticsAppModule extends AppModule {
  DiagnosticsAppModule({required this.inspector});

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
            path: AppRoutes.networkInspector,
            builder: (context, state) =>
                NetworkInspectorScreen(inspector: inspector),
          ),
        ],
      );

  @override
  Future<void> onDispose() async => inspector.dispose();
}
