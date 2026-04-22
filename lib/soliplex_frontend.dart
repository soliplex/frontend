/// Modular Flutter frontend framework for Soliplex.
library;

export 'src/core/app_module.dart'
    show AppModule, AppModuleContext, ModuleRoutes;
export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ShellConfig;
export 'src/interfaces/auth_state.dart'
    show AuthState, Authenticated, Unauthenticated;
export 'src/modules/auth/auth_providers.dart' show serverManagerProvider;
export 'src/modules/auth/platform/callback_service.dart'
    show CallbackParamsCapture, clearCallbackUrl;
export 'src/modules/auth/consent_notice.dart' show ConsentNotice;
export 'src/modules/auth/server_manager.dart' show ServerManager;
