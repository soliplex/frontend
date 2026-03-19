import '../../core/shell_config.dart';
import 'diagnostics_providers.dart';
import 'network_inspector.dart';

ModuleContribution diagnosticsModule({required NetworkInspector inspector}) {
  return ModuleContribution(
    overrides: [
      networkInspectorProvider.overrideWithValue(inspector),
    ],
  );
}
