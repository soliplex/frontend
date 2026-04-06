/// Modular Flutter frontend framework for Soliplex.
library;

export 'src/core/models/color_config.dart' show ColorPalette, ColorConfig;
export 'src/core/models/font_config.dart' show FontConfig;
export 'src/core/models/theme_config.dart' show ThemeConfig;
export 'src/core/providers/theme_provider.dart'
    show themeModeProvider, initializeTheme;
export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ModuleContribution, ShellConfig;
export 'src/design/design.dart';
export 'src/interfaces/auth_state.dart'
    show AuthState, Authenticated, Unauthenticated;
export 'src/modules/auth/auth_providers.dart' show serverManagerProvider;
export 'src/modules/auth/platform/callback_service.dart'
    show CallbackParamsCapture, clearCallbackUrl;
export 'src/modules/auth/consent_notice.dart' show ConsentNotice;
export 'src/modules/auth/server_manager.dart' show ServerManager;
