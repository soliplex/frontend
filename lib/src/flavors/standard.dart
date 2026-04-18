import 'dart:async' show StreamController, unawaited;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client_native/soliplex_client_native.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:ui_plugin/ui_plugin.dart';
import 'package:ui_renderer_soliplex/ui_renderer_soliplex.dart';

import '../design/design.dart';
import '../core/shell_config.dart';
import '../core/signal_listenable.dart';
import '../interfaces/auth_state.dart';
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
import '../modules/room/access_policy.dart';
import '../modules/room/agent_runtime_manager.dart';
import '../modules/room/policy_enforcement_middleware.dart';
import '../modules/room/room_module.dart';
import '../modules/room/run_registry.dart';
import '../modules/room/ui/markdown/markdown_theme_extension.dart';
import '../modules/tools/get_clipboard_tool.dart';
import '../modules/tools/get_device_info_tool.dart';

const _defaultLogoAsset = 'assets/branding/soliplex/logo_1024.png';
const _logoSize = 64.0;

ThemeData _defaultTheme() {
  final base = soliplexLightTheme();
  final colorScheme = base.colorScheme;
  final textTheme = base.textTheme;
  final colors = base.extension<SoliplexTheme>()!.colors;

  return base.copyWith(
    extensions: [
      ...base.extensions.values,
      MarkdownThemeExtension(
        h1: textTheme.titleLarge,
        h2: textTheme.titleMedium,
        h3: textTheme.titleSmall,
        body: textTheme.bodyMedium,
        code: textTheme.bodyMedium?.copyWith(
          backgroundColor: colorScheme.surfaceContainerHighest,
        ),
        link: TextStyle(
          color: colors.link,
          decoration: TextDecoration.underline,
          decorationColor: colors.link,
        ),
        codeBlockDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              color: colorScheme.outlineVariant,
              width: 3,
            ),
          ),
        ),
      ),
    ],
  );
}

Future<ShellConfig> standard({
  String appName = 'Soliplex',
  ThemeData? theme,
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  Widget? logo,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final uiRenderer = SoliplexUiRenderer(
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: scaffoldMessengerKey,
  );
  LogManager.instance
    ..minimumLevel = LogLevel.debug
    ..addSink(StdoutSink());
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

  final authListenable = SignalListenable(serverManager.authState);
  final authFlow = createAuthFlow(redirectScheme: redirectScheme);

  final roomEnvRegistry = RoomEnvironmentRegistry();
  final notifyController = StreamController<NotifyEvent>.broadcast();

  Future<ScriptEnvironment> buildEnv(SessionContext ctx) async {
    Map<String, SoliplexConnection> getConnections() => {
          for (final entry in serverManager.servers.value.values)
            entry.serverId: SoliplexConnection.fromServerConnection(
              entry.connection,
              alias: entry.alias,
              serverUrl: entry.serverUrl.toString(),
            ),
        };
    final roomKey = '${ctx.serverId}:${ctx.roomId}';
    final roomUiPlugin = kDebugMode
        ? UiPlugin(renderer: RoomScopedUiRenderer(uiRenderer, roomKey))
        : null;
    final env = MontyScriptEnvironment(
      tools: buildSoliplexToolset(
        ctx,
        getConnections,
        onNotify: notifyController.add,
      ),
      plugins: roomUiPlugin != null ? [roomUiPlugin] : [],
    );
    env.registerMiddleware(PolicyEnforcementMiddleware(AccessPolicy.permissive));
    return env;
  }

  Future<String> replExecutor(
    String serverId,
    String roomId,
    String code,
  ) async {
    final ctx = SessionContext(serverId: serverId, roomId: roomId);
    final env = await roomEnvRegistry.getOrCreate(ctx, buildEnv);
    return (env as MontyScriptEnvironment).executeFormatted(code);
  }

  final runtimeManager = AgentRuntimeManager(
    platform: kIsWeb
        ? const WebPlatformConstraints()
        : const NativePlatformConstraints(),
    toolRegistryResolver: (_) async => const ToolRegistry()
        .register(buildGetDeviceInfoTool())
        .register(buildGetClipboardTool()),
    logger: LogManager.instance.getLogger('room'),
    extensionFactoryBuilder: (connection) =>
        toRoomSharedFactory(roomEnvRegistry, buildEnv),
  );

  final registry = RunRegistry();

  unawaited(_probeMontyRuntime(
    LogManager.instance.getLogger('monty'),
    serverManager,
  ));

  return ShellConfig(
    appName: appName,
    logo: logo,
    theme: theme ?? _defaultTheme(),
    initialRoute: callbackParams is! NoCallbackParams
        ? '/auth/callback'
        : (serverManager.authState.value is Authenticated ? '/lobby' : '/'),
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: scaffoldMessengerKey,
    refreshListenable: authListenable,
    onDispose: () {
      authListenable.dispose();
      serverManager.dispose();
      plainClient.close();
      runtimeManager.dispose();
      registry.dispose();
      roomEnvRegistry.dispose();
      notifyController.close();
      inspector.dispose();
    },
    modules: [
      diagnosticsModule(inspector: inspector),
      lobbyModule(serverManager: serverManager),
      roomModule(
        serverManager: serverManager,
        runtimeManager: runtimeManager,
        registry: registry,
        enableDocumentFilter: true,
        injectedMessages: uiRenderer.messagesFor,
        onRoomChanged: uiRenderer.clearAllMessages,
        debugPanel: null,
        notifyStream: notifyController.stream,
        envRegistry: roomEnvRegistry,
        replExecutor: replExecutor,
      ),
      quizModule(serverManager: serverManager),
      authModule(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: plainClient,
        appName: appName,
        callbackParams: callbackParams,
        consentNotice: consentNotice,
        logo: logo,
        defaultBackendUrl: resolvedUrl,
      ),
    ],
  );
}

Future<void> _probeMontyRuntime(
  Logger logger,
  ServerManager serverManager,
) async {
  const name = 'MontyProbe';
  final ctx = const SessionContext(serverId: 'probe', roomId: 'probe');
  Map<String, SoliplexConnection> getConnections() => {
        for (final entry in serverManager.servers.value.values)
          entry.serverId: SoliplexConnection.fromServerConnection(
            entry.connection,
            alias: entry.alias,
            serverUrl: entry.serverUrl.toString(),
          ),
      };
  final env = MontyScriptEnvironment(
    tools: buildSoliplexToolset(ctx, getConnections),
  );
  try {
    await env.probe();
    logger.info('Python runtime probe passed');
    developer.log('Python runtime probe passed', name: name);
  } on Object catch (e) {
    logger.warning('Python runtime probe failed: $e');
    developer.log('Python runtime probe FAILED: $e', name: name);
  } finally {
    env.dispose();
  }
}
