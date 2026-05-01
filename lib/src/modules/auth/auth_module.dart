import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import '../../core/app_module.dart';
import '../../core/routes.dart';
import '../../core/signal_listenable.dart';
import '../../interfaces/auth_state.dart';
import 'auth_providers.dart';
import 'consent_notice.dart';
import 'platform/auth_flow.dart';
import 'platform/callback_params.dart';
import 'server_manager.dart';
import 'ui/auth_callback_screen.dart';
import 'ui/home_screen.dart';
import 'ui/server_list_screen.dart';

const _publicPaths = {
  AppRoutes.home,
  AppRoutes.servers,
  AppRoutes.authCallback,
  AppRoutes.versions,
};

class AuthAppModule extends AppModule {
  AuthAppModule({
    required ServerManager serverManager,
    required SoliplexHttpClient probeClient,
    required AuthFlow authFlow,
    required String appName,
    CallbackParams? callbackParams,
    ConsentNotice? consentNotice,
    Widget? logo,
    String? defaultBackendUrl,
  })  : _serverManager = serverManager,
        _probeClient = probeClient,
        _authFlow = authFlow,
        _appName = appName,
        _callbackParams = callbackParams,
        _consentNotice = consentNotice,
        _logo = logo,
        _defaultBackendUrl = defaultBackendUrl,
        _refreshListenable = SignalListenable(serverManager.authState);

  final ServerManager _serverManager;
  final SoliplexHttpClient _probeClient;
  final AuthFlow _authFlow;
  final String _appName;
  final CallbackParams? _callbackParams;
  final ConsentNotice? _consentNotice;
  final Widget? _logo;
  final String? _defaultBackendUrl;
  final SignalListenable _refreshListenable;

  /// The [Listenable] that notifies [GoRouter] when auth state changes.
  /// Pass this to [ShellConfig.fromModules] as [refreshListenable].
  Listenable get refreshListenable => _refreshListenable;

  @override
  String get namespace => 'auth';

  @override
  ModuleRoutes build() => ModuleRoutes(
        overrides: [
          serverManagerProvider.overrideWithValue(_serverManager),
          authFlowProvider.overrideWithValue(_authFlow),
          probeClientProvider.overrideWithValue(_probeClient),
          if (_callbackParams != null)
            callbackParamsProvider.overrideWithValue(_callbackParams),
          if (_consentNotice != null)
            consentNoticeProvider.overrideWithValue(_consentNotice),
        ],
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (_, state) {
              final autoConnectUrl = state.uri.queryParameters['url'];
              return NoTransitionPage(
                key: autoConnectUrl != null ? UniqueKey() : state.pageKey,
                child: HomeScreen(
                  serverManager: _serverManager,
                  appName: _appName,
                  logo: _logo,
                  defaultBackendUrl: _defaultBackendUrl,
                  autoConnectUrl: autoConnectUrl,
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.servers,
            pageBuilder: (_, __) => NoTransitionPage(
              child: ServerListScreen(serverManager: _serverManager),
            ),
          ),
          GoRoute(
            path: AppRoutes.authCallback,
            pageBuilder: (_, __) => NoTransitionPage(
              child: AuthCallbackScreen(serverManager: _serverManager),
            ),
          ),
        ],
        redirect: (_, state) {
          final isAuthenticated =
              _serverManager.authState.value is Authenticated;
          final isPublic = _publicPaths.contains(state.matchedLocation);
          if (!isAuthenticated && !isPublic) return AppRoutes.home;
          return null;
        },
      );

  @override
  Future<void> onDispose() async {
    _refreshListenable.dispose();
    _serverManager.dispose();
    _probeClient.close();
  }
}
