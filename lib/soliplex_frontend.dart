/// Modular Flutter frontend framework for Soliplex.
library;

export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ModuleContribution, ShellConfig;
export 'src/interfaces/auth_state.dart'
    show AuthState, Authenticated, Unauthenticated, authStateProvider;
export 'src/modules/auth/auth_module.dart' show authModule;
