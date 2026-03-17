import '../../core/shell_config.dart';
import '../../interfaces/auth_state.dart';

ModuleContribution authModule({required AuthState auth}) {
  return ModuleContribution(
    overrides: [authStateProvider.overrideWithValue(auth)],
  );
}
