import 'package:flutter/foundation.dart' show kIsWeb, Listenable;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client_native/soliplex_client_native.dart';
import 'package:soliplex_logging/soliplex_logging.dart' show LoggerFactory;

import '../core/app_identity.dart';
import '../core/app_module.dart';
import '../core/inactivity/inactivity_config.dart';
import '../core/routes.dart';
import '../core/storage_migration.dart';
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
import '../modules/lobby/lobby_read_markers.dart'
    show RoomReadMarkers, ServerReadMarkers;
import '../modules/quiz/quiz_module.dart';
import '../modules/room/agent_runtime_manager.dart';
import '../modules/room/execution_tracker_extension.dart';
import '../modules/room/human_approval_extension.dart';
import '../modules/room/room_module.dart';
import '../modules/room/run_registry.dart';
import '../modules/room/tool_calls_extension.dart';
import '../modules/versions/versions_module.dart';

/// The module graph and derived boot inputs (`initialRoute`,
/// `refreshListenable`, `inactivity`) produced by [buildStandardKit],
/// plus `serverManager` — the shared-state handle custom modules build on.
typedef StandardKit = ({
  List<AppModule> modules,
  Listenable refreshListenable,
  String initialRoute,
  InactivityConfig inactivity,
  ServerManager serverManager,
});

/// Builds the standard flavor's module graph and shared state.
///
/// Owns construction order and cross-module wiring (auth, server discovery,
/// agent runtime, read markers). `standardFlavor` maps this onto a `Flavor`;
/// flavor authors can call this directly to build their own module set on
/// top of the same shared state.
Future<StandardKit> buildStandardKit({
  required AppIdentity identity,
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  Duration inactivityWarningDuration = InactivityConfig.defaultWarningDuration,
  Duration inactivityGraceDuration = InactivityConfig.defaultGraceDuration,
  bool enableDocumentFilter = true,
}) async {
  final brandLogo = BrandLogo(identity: identity);

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
  await migrateStorage();

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
    servers: serverManager.servers,
  );

  final registry = RunRegistry(servers: serverManager.servers);

  // Shared in-memory read-marker model so a room stamped read in the room
  // screen clears its lobby unread dot immediately, with no storage race.
  final roomReadMarkers = RoomReadMarkers();

  // Shared server-level read markers, watched by both modules so a server
  // marker floors every room and thread on it across both surfaces.
  final serverReadMarkers = ServerReadMarkers();

  final inactivityLogoutFlags = LocalInactivityLogoutFlagStorage();

  final authMod = AuthAppModule(
    serverManager: serverManager,
    probeClient: plainClient,
    authFlow: authFlow,
    appName: identity.appName,
    inactivityLogoutFlags: inactivityLogoutFlags,
    callbackParams: callbackParams is! NoCallbackParams ? callbackParams : null,
    consentNotice: consentNotice,
    logo: brandLogo,
    defaultBackendUrl: resolvedUrl,
  );

  final initialRoute = callbackParams is! NoCallbackParams
      ? AppRoutes.authCallback
      : (serverManager.authState.value is Authenticated
          ? AppRoutes.lobby
          : AppRoutes.home);

  return (
    modules: List<AppModule>.unmodifiable(<AppModule>[
      DiagnosticsAppModule(
        appName: identity.appName,
        logo: brandLogo,
        inspector: inspector,
      ),
      authMod,
      LobbyAppModule(
        serverManager: serverManager,
        identity: identity,
        registry: registry,
        roomReadMarkers: roomReadMarkers,
        serverReadMarkers: serverReadMarkers,
      ),
      RoomAppModule(
        serverManager: serverManager,
        runtimeManager: runtimeManager,
        registry: registry,
        roomReadMarkers: roomReadMarkers,
        serverReadMarkers: serverReadMarkers,
        appName: identity.appName,
        logo: brandLogo,
        enableDocumentFilter: enableDocumentFilter,
      ),
      QuizAppModule(serverManager: serverManager),
      VersionsAppModule(
        appName: identity.appName,
        logo: brandLogo,
        serverManager: serverManager,
      ),
    ]),
    refreshListenable: authMod.refreshListenable,
    initialRoute: initialRoute,
    inactivity: InactivityConfig(
      warningDuration: inactivityWarningDuration,
      graceDuration: inactivityGraceDuration,
    ),
    serverManager: serverManager,
  );
}
