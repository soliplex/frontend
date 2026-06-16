import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client_native/soliplex_client_native.dart';
import 'package:soliplex_logging/soliplex_logging.dart' show LoggerFactory;

import '../core/branding.dart';
import '../core/inactivity/inactivity_config.dart';
import '../core/routes.dart';
import '../core/shell_config.dart';
import 'package:soliplex_design/soliplex_design.dart';
import '../interfaces/auth_state.dart' show Authenticated;
import '../modules/auth/auth_module.dart';
import '../modules/auth/consent_notice.dart';
import '../modules/auth/default_backend_url.dart';
import '../modules/auth/auth_session.dart';
import '../modules/auth/inactivity_logout_storage.dart';
import '../modules/auth/platform/auth_flow.dart';
import '../modules/auth/platform/callback_params.dart';
import '../modules/auth/secure_server_storage.dart';
import '../modules/auth/server_manager.dart';
import '../modules/auth/server_storage.dart';
import '../modules/diagnostics/diagnostics_module.dart';
import '../modules/diagnostics/network_inspector.dart';
import '../modules/lobby/lobby_module.dart';
import '../modules/quiz/quiz_module.dart';
import '../modules/room/agent_runtime_manager.dart';
import '../modules/room/execution_tracker_extension.dart';
import '../modules/room/human_approval_extension.dart';
import '../modules/room/room_module.dart';
import '../modules/room/run_registry.dart';
import '../modules/room/tool_calls_extension.dart';
import '../modules/versions/versions_module.dart';

Future<ShellConfig> standard({
  SoliplexBranding? branding,
  ClassificationTheme? classifications,
  ThemeMode themeMode = ThemeMode.system,
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  Duration inactivityWarningDuration = InactivityConfig.defaultWarningDuration,
  Duration inactivityGraceDuration = InactivityConfig.defaultGraceDuration,
}) async {
  final brand = branding ?? SoliplexBranding.soliplex;
  // Markings don't flip with brightness — the same instance feeds both
  // themes. Omitted → the design system's neutral built-in (no pills).
  // This is the adopter's configuration point for deployment vocabularies.
  final lightTheme = soliplexLightTheme(
    colors: SoliplexColors.fromAccent(
      brand.accentLight,
      brightness: Brightness.light,
    ),
    classifications: classifications,
  );
  final darkTheme = soliplexDarkTheme(
    colors: SoliplexColors.fromAccent(
      brand.accentDark,
      brightness: Brightness.dark,
    ),
    classifications: classifications,
  );
  final brandLogo = BrandLogo(branding: brand);

  final inspector = NetworkInspector();
  final httpLogger = LogManager.instance.getLogger('http_stack');

  void onHttpDiagnostic(
    Object error,
    StackTrace stackTrace, {
    required String message,
  }) {
    httpLogger.error(message, error: error, stackTrace: stackTrace);
  }

  SoliplexHttpClient buildClient({
    String? Function()? getToken,
    TokenRefresher? tokenRefresher,
  }) =>
      createAgentHttpClient(
        innerClient: createPlatformClient(),
        observers: [inspector],
        getToken: getToken,
        tokenRefresher: tokenRefresher,
        onDiagnostic: onHttpDiagnostic,
      );

  final plainClient = buildClient();
  final refreshService = TokenRefreshService(httpClient: plainClient);

  AuthSession buildAuth() => AuthSession(refreshService: refreshService);

  final serverStorage = SecureServerStorage();
  await clearServersIfFreshInstall(serverStorage);

  final serverManager = ServerManager(
    authFactory: buildAuth,
    clientFactory: buildClient,
    storage: serverStorage,
  );
  await serverManager.restoreServers();

  final savedUrl = await DefaultBackendUrlStorage.load();
  final resolvedUrl = savedUrl ??
      platformDefaultBackendUrl(
        configUrl: defaultBackendUrl,
        isWeb: kIsWeb,
        webOrigin: kIsWeb ? Uri.base : null,
      );

  final authFlow = createAuthFlow(redirectScheme: redirectScheme);

  final runtimeManager = AgentRuntimeManager(
    platform: kIsWeb
        ? const WebPlatformConstraints()
        : const NativePlatformConstraints(),
    toolRegistryResolver: (_) async => const ToolRegistry(),
    logger: LogManager.instance.getLogger('room'),
    extensionFactory: () async => [
      ExecutionTrackerExtension(
        logger: LogManager.instance
            .getLogger('soliplex_frontend.execution_tracker'),
      ),
      ToolCallsExtension(),
      HumanApprovalExtension(),
    ],
  );

  final registry = RunRegistry();

  final inactivityLogoutFlags = LocalInactivityLogoutFlagStorage();

  final authMod = AuthAppModule(
    serverManager: serverManager,
    probeClient: plainClient,
    authFlow: authFlow,
    appName: brand.appName,
    inactivityLogoutFlags: inactivityLogoutFlags,
    callbackParams: callbackParams is! NoCallbackParams ? callbackParams : null,
    consentNotice: consentNotice,
    logo: brandLogo,
    defaultBackendUrl: resolvedUrl,
  );

  return ShellConfig.fromModules(
    appName: brand.appName,
    lightTheme: lightTheme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    initialRoute: callbackParams is! NoCallbackParams
        ? AppRoutes.authCallback
        : (serverManager.authState.value is Authenticated
            ? AppRoutes.lobby
            : AppRoutes.home),
    refreshListenable: authMod.refreshListenable,
    inactivity: InactivityConfig(
      warningDuration: inactivityWarningDuration,
      graceDuration: inactivityGraceDuration,
    ),
    modules: [
      DiagnosticsAppModule(
        appName: brand.appName,
        logo: brandLogo,
        inspector: inspector,
      ),
      authMod,
      LobbyAppModule(serverManager: serverManager, branding: brand),
      RoomAppModule(
        serverManager: serverManager,
        runtimeManager: runtimeManager,
        registry: registry,
        appName: brand.appName,
        logo: brandLogo,
        enableDocumentFilter: true,
      ),
      QuizAppModule(serverManager: serverManager),
      VersionsAppModule(
        appName: brand.appName,
        logo: brandLogo,
        serverManager: serverManager,
      ),
    ],
  );
}
