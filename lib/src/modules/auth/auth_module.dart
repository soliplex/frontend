import '../../core/shell_config.dart';
import 'auth_providers.dart';
import 'server_manager.dart';

ModuleContribution authModule({required ServerManager serverManager}) {
  return ModuleContribution(
    overrides: [
      serverManagerProvider.overrideWithValue(serverManager),
    ],
  );
}
