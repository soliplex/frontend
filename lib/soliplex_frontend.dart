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
// Logging primitives, re-exported so a host app needs no `soliplex_logging`
// dependency of its own. `LoggerFactory` carries `LogManager.getLogger`;
// without it `Logger` would be a name a host can write but never obtain, since
// its only constructor is private.
export 'package:soliplex_logging/soliplex_logging.dart'
    show
        ConsoleSink,
        LogLevel,
        LogManager,
        LogRecord,
        LogSink,
        Logger,
        LoggerFactory,
        MemorySink,
        StdoutSink;
export 'src/core/app_module.dart' show AppModule, ModuleRoutes;

// A module author declares routes with go_router's own types and navigates
// with its `context.go` extension, so the extension point is unusable without
// them. The list is the types the module-authoring API's own signatures are
// written in — `ModuleRoutes.routes`, `ModuleRoutes.redirect`, a `GoRoute`
// builder's arguments — plus what a widget test needs to drive one.
//
// It is curated, never the whole package: typed routes, `ShellRoute` and
// `StatefulShellRoute` are absent. No module here uses the shell routes, and
// `StatefulShellRoute` cannot be constructed without `StatefulShellBranch`
// anyway. Reaching past this list means depending on go_router directly.
//
// `GoRouterHelper` is the one entry whose absence is invisible until it bites:
// `show` gates extensions, so without it `context.go` does not resolve, and
// `test/barrel_module_authoring_test.dart` is the only thing in this repo that
// would notice. The other entries are needed to *name* a type — to construct a
// `GoRoute`, to annotate a builder's `GoRouterState`, to hold a `GoRouter`.
// Dart infers types without their names in scope, so a consumer who never
// writes an annotation needs fewer of these than are listed; they are here so
// that writing one is possible.
export 'package:go_router/go_router.dart'
    show
        GoRoute,
        GoRouter,
        GoRouterHelper,
        GoRouterRedirect,
        GoRouterState,
        NoTransitionPage,
        RouteBase;
// Builds the router the shell itself runs on, public paths and module
// redirects included — this is the composition `shell.dart` boots. A test that
// assembles a GoRouter by hand from ModuleRoutes reproduces it, and a
// reproduction that omits the public-path step turns the sign-in guard on
// paths that are meant to be exempt.
export 'src/core/router.dart' show buildRouter;
export 'src/core/app_identity.dart' show AppIdentity, BrandLogo;
export 'src/core/flavor.dart' show Flavor, FlavorTheme;
export 'src/core/log_sinks.dart' show installLogSinks;
export 'src/core/inactivity/inactivity_config.dart' show InactivityConfig;
export 'src/core/shell.dart' show runSoliplexShell;
export 'src/core/shell_config.dart' show ShellConfig;
export 'src/core/status_message_config.dart' show StatusMessageConfig;
export 'src/core/uncaught_errors.dart' show installUncaughtErrorLogging;
export 'src/flavors/standard.dart' show standard, standardFlavor;
export 'src/flavors/standard_kit.dart' show buildStandardKit, StandardKit;
// The resolver type for `standard(documentBrowserUrl: ...)`; the provider that
// installs it stays internal.
export 'src/modules/room/document_browser_url.dart'
    show DocumentBrowserUrlResolver;
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
