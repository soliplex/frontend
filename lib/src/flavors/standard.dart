import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client_native/soliplex_client_native.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';

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
import '../modules/room/agent_runtime_manager.dart';
import '../modules/room/room_module.dart';
import '../modules/room/run_registry.dart';
import '../modules/room/ui/markdown/markdown_theme_extension.dart';
import '../modules/tools/confirm_action_tool.dart';
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
  LogManager.instance
    ..minimumLevel = LogLevel.debug
    ..addSink(StdoutSink());
  logo ??= Image.asset(_defaultLogoAsset, width: _logoSize, height: _logoSize);
  final inspector = NetworkInspector();

  SoliplexHttpClient buildClient({
    String? Function()? getToken,
    TokenRefresher? tokenRefresher,
  }) =>
      createAgentHttpClient(
        innerClient: createPlatformClient(),
        observers: [inspector],
        getToken: getToken,
        tokenRefresher: tokenRefresher,
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

  final runtimeManager = AgentRuntimeManager(
    platform: kIsWeb
        ? const WebPlatformConstraints()
        : const NativePlatformConstraints(),
    toolRegistryResolver: (_) async => const ToolRegistry()
        .register(buildGetDeviceInfoTool())
        .register(buildConfirmActionTool())
        .register(buildGetClipboardTool()),
    logger: LogManager.instance.getLogger('room'),
    extensionFactoryBuilder: (connection) => toOwnedFactory(
      () async => MontyScriptEnvironment(
        plugins: [
          SoliplexPlugin(
            connections: {
              for (final entry in serverManager.servers.value.values)
                entry.serverId: SoliplexConnection.fromServerConnection(
                  entry.connection,
                  alias: entry.alias,
                  serverUrl: entry.serverUrl.toString(),
                ),
            },
          ),
        ],
      ),
    ),
  );

  final registry = RunRegistry();

  // Fire-and-forget startup validation: detect broken Python runtime early.
  unawaited(_probeMontyRuntime(LogManager.instance.getLogger('monty')));

  return ShellConfig(
    appName: appName,
    logo: logo,
    theme: theme ?? _defaultTheme(),
    initialRoute: callbackParams is! NoCallbackParams
        ? '/auth/callback'
        : (serverManager.authState.value is Authenticated ? '/lobby' : '/'),
    refreshListenable: authListenable,
    onDispose: () {
      authListenable.dispose();
      serverManager.dispose();
      plainClient.close();
      runtimeManager.dispose();
      registry.dispose();
    },
    modules: [
      diagnosticsModule(inspector: inspector),
      lobbyModule(serverManager: serverManager),
      roomModule(
        serverManager: serverManager,
        runtimeManager: runtimeManager,
        registry: registry,
        enableDocumentFilter: true,
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

/// Probes the Python runtime by creating a throwaway [MontyScriptEnvironment],
/// running `1 + 1`, and logging the outcome.
///
/// Failures are logged as warnings — they do not crash the app. The probe runs
/// fire-and-forget; call it with [unawaited] during startup.
Future<void> _probeMontyRuntime(Logger logger) async {
  const name = 'MontyProbe';
  final env = MontyScriptEnvironment();
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
