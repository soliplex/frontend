/// Modular Flutter frontend framework for Soliplex.
library;

export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ModuleContribution, ShellConfig;
export 'src/interfaces/auth_state.dart'
    show AuthState, Authenticated, Unauthenticated;
export 'src/modules/auth/auth_providers.dart' show serverManagerProvider;
export 'src/modules/auth/server_manager.dart' show ServerManager;
