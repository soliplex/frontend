import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client_native/soliplex_client_native.dart';
import 'package:soliplex_logging/soliplex_logging.dart' show LoggerFactory;

import '../core/models/font_config.dart';
import '../core/models/theme_config.dart';
import '../core/routes.dart';
import '../core/shell_config.dart';
import '../design/design.dart';
import '../interfaces/auth_state.dart' show Authenticated;
import '../modules/auth/auth_module.dart';
import '../modules/auth/default_backend_url.dart';
import '../modules/auth/auth_session.dart';
import '../modules/auth/consent_notice.dart';
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

const _defaultLogoAsset = 'assets/branding/soliplex/logo_1024.png';
const _logoSize = 64.0;

/// Default font configuration.
///
/// - Inter: bundled asset (body text)
/// - Oswald: resolved via google_fonts (display text)
/// - Squada One: resolved via google_fonts (brand text)
const _defaultFontConfig = FontConfig(
  bodyFont: FontFamilies.body,
  displayFont: FontFamilies.display,
  brandFont: FontFamilies.brand,
);

Future<ShellConfig> standard({
  String appName = 'Soliplex',
  ThemeConfig? themeConfig,
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  Widget? logo,
}) async {
  logo ??= Image.asset(_defaultLogoAsset, width: _logoSize, height: _logoSize);
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
      ExecutionTrackerExtension(),
      ToolCallsExtension(),
      HumanApprovalExtension(),
    ],
  );

  final registry = RunRegistry();

  final authMod = AuthAppModule(
    serverManager: serverManager,
    probeClient: plainClient,
    authFlow: authFlow,
    appName: appName,
    callbackParams: callbackParams is! NoCallbackParams ? callbackParams : null,
    consentNotice: consentNotice,
    logo: logo,
    defaultBackendUrl: resolvedUrl,
  );

  return ShellConfig.fromModules(
    appName: appName,
    logo: logo,
    theme: soliplexLightTheme(
      colorConfig: themeConfig?.colorConfig,
      fontConfig: themeConfig?.fontConfig ?? _defaultFontConfig,
    ),
    darkTheme: soliplexDarkTheme(
      colorConfig: themeConfig?.colorConfig,
      fontConfig: themeConfig?.fontConfig ?? _defaultFontConfig,
    ),
    initialRoute: callbackParams is! NoCallbackParams
        ? AppRoutes.authCallback
        : (serverManager.authState.value is Authenticated
            ? AppRoutes.lobby
            : AppRoutes.home),
    refreshListenable: authMod.refreshListenable,
    modules: [
      DiagnosticsAppModule(inspector: inspector),
      authMod,
      LobbyAppModule(serverManager: serverManager),
      RoomAppModule(
        serverManager: serverManager,
        runtimeManager: runtimeManager,
        registry: registry,
        enableDocumentFilter: true,
      ),
      QuizAppModule(serverManager: serverManager),
      VersionsAppModule(
        appName: appName,
        serverManager: serverManager,
      ),
    ],
  );
}
