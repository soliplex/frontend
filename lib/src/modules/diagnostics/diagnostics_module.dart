import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import 'diagnostics_providers.dart';
import 'network_inspector.dart';
import 'ui/network_inspector_screen.dart';

ModuleContribution diagnosticsModule({required NetworkInspector inspector}) {
  return ModuleContribution(
    overrides: [networkInspectorProvider.overrideWithValue(inspector)],
    routes: [
      GoRoute(
        path: '/diagnostics/network',
        builder:
            (context, state) => NetworkInspectorScreen(inspector: inspector),
      ),
    ],
  );
}
