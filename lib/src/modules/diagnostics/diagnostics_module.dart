import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import 'bus_inspector.dart';
import 'diagnostics_providers.dart';
import 'network_inspector.dart';
import 'ui/bus_inspector_screen.dart';
import 'ui/network_inspector_screen.dart';

class DiagnosticsAppModule extends AppModule {
  DiagnosticsAppModule({
    required this.inspector,
    required this.busInspector,
  });

  final NetworkInspector inspector;
  final BusInspector busInspector;

  @override
  String get namespace => 'diagnostics';

  @override
  ModuleRoutes build() => ModuleRoutes(
        overrides: [
          networkInspectorProvider.overrideWithValue(inspector),
          busInspectorProvider.overrideWithValue(busInspector),
        ],
        routes: [
          GoRoute(
            path: '/diagnostics/network',
            builder: (context, state) =>
                NetworkInspectorScreen(inspector: inspector),
          ),
          GoRoute(
            path: '/diagnostics/bus',
            builder: (context, state) =>
                BusInspectorScreen(inspector: busInspector),
          ),
        ],
      );

  @override
  Future<void> onDispose() async {
    inspector.dispose();
    busInspector.dispose();
  }
}
