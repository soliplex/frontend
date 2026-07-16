/// Modular Flutter frontend framework for Soliplex.
library;

// Design-system theming primitives, re-exported so consumers that depend only
// on this package can build and customize a brand theme without taking a direct
// dependency on soliplex_design.
export 'package:soliplex_design/soliplex_design.dart'
    show
        BrandColorScheme,
        BrandFontRole,
        BrandShape,
        BrandTheme,
        BrandTint,
        BrandTypography,
        BundledFontResolver,
        ClassificationLevel,
        ClassificationTheme,
        FontResolver,
        ResolvedFont,
        SoliplexColors,
        SoliplexRadii,
        TintSource,
        TypeScaleOverride,
        buildSoliplexThemeData,
        darkSoliplexColors,
        lightSoliplexColors,
        lowerBrandTheme,
        soliplexTextTheme;
export 'src/core/app_module.dart' show AppModule, ModuleRoutes;
export 'src/core/app_identity.dart' show AppIdentity, BrandLogo;
export 'src/core/flavor.dart' show Flavor, FlavorTheme;
export 'src/core/inactivity/inactivity_config.dart' show InactivityConfig;
export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ShellConfig;
export 'src/interfaces/auth_state.dart'
    show AuthState, Authenticated, Unauthenticated;
export 'src/modules/auth/auth_providers.dart'
    show inactivityLogoutFlagsProvider, serverManagerProvider;
export 'src/modules/auth/inactivity_logout_storage.dart'
    show InactivityLogoutFlagStorage, LocalInactivityLogoutFlagStorage;
export 'src/modules/auth/platform/callback_service.dart'
    show CallbackParamsCapture, clearCallbackUrl;
export 'src/modules/auth/consent_notice.dart' show ConsentNotice;
export 'src/modules/auth/server_manager.dart' show ServerManager;
