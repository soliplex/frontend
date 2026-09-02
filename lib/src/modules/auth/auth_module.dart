import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import '../../core/app_module.dart';
import '../../core/routes.dart';
import '../../core/util/signal_listenable.dart';
import '../../interfaces/auth_state.dart';
import 'auth_providers.dart';
import 'consent_notice.dart';
import 'inactivity_logout_storage.dart';
import 'platform/auth_flow.dart';
import 'platform/callback_params.dart';
import 'server_manager.dart';
import 'ui/auth_callback_screen.dart';
import 'ui/home_screen.dart';

class AuthAppModule extends AppModule {
  AuthAppModule({
    required ServerManager serverManager,
    required SoliplexHttpClient probeClient,
    required AuthFlow authFlow,
    required String appName,
    required InactivityLogoutFlagStorage inactivityLogoutFlags,
    CallbackParams? callbackParams,
    ConsentNotice? consentNotice,
    Widget? logo,
    String? defaultBackendUrl,
  })  : _serverManager = serverManager,
        _probeClient = probeClient,
        _authFlow = authFlow,
        _appName = appName,
        _inactivityLogoutFlags = inactivityLogoutFlags,
        _callbackParams = callbackParams,
        _consentNotice = consentNotice,
        _logo = logo,
        _defaultBackendUrl = defaultBackendUrl,
        _refreshListenable = SignalListenable(serverManager.connectionRevision);

  final ServerManager _serverManager;
  final SoliplexHttpClient _probeClient;
  final AuthFlow _authFlow;
  final String _appName;
  final InactivityLogoutFlagStorage _inactivityLogoutFlags;
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
        publicPaths: const {AppRoutes.home, AppRoutes.authCallback},
        overrides: [
          serverManagerProvider.overrideWithValue(_serverManager),
          authFlowProvider.overrideWithValue(_authFlow),
          probeClientProvider.overrideWithValue(_probeClient),
          inactivityLogoutFlagsProvider
              .overrideWithValue(_inactivityLogoutFlags),
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
              final returnTo = state.uri.queryParameters['returnTo'];
              return NoTransitionPage(
                key: autoConnectUrl != null ? UniqueKey() : state.pageKey,
                child: HomeScreen(
                  serverManager: _serverManager,
                  appName: _appName,
                  logo: _logo,
                  defaultBackendUrl: _defaultBackendUrl,
                  autoConnectUrl: autoConnectUrl,
                  autoConnectReturnTo: returnTo,
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.authCallback,
            pageBuilder: (_, __) => NoTransitionPage(
              child: AuthCallbackScreen(
                serverManager: _serverManager,
                appName: _appName,
                logo: _logo,
              ),
            ),
          ),
        ],
        redirect: (_, state) {
          // This guard admits no public path of its own: buildRouter returns
          // before the redirect loop for anything a module declared, so under
          // the shell one never arrives here. Handed straight to a GoRouter
          // without that step it diverts every unauthenticated request,
          // including its own /auth/callback, losing an in-flight sign-in.
          // '/?url=...' is worse for being quiet: go_router compares a redirect
          // target against the whole requested URI, query included, so
          // returning '/' is a real navigation and the new match list is parsed
          // from '/' alone — autoConnectUrl and returnTo are gone. The second
          // pass returns '/' for '/', which is discarded, so there is no loop
          // and no error, just an emptied launch. Drive a module through
          // buildRouter, not a router assembled from ModuleRoutes by hand.
          //
          // Per-server guard: if the route names a specific server and
          // that server isn't connected (signed out or expired),
          // redirect to its sign-in entry. Carry the original location
          // through so the callback can return the user back here.
          final alias = state.pathParameters['serverAlias'];
          if (alias != null) {
            final entry = _serverManager.entryByAlias(alias);
            if (entry != null && !entry.isConnected) {
              return AppRoutes.homeWithUrl(
                entry.serverUrl.toString(),
                returnTo: state.matchedLocation,
              );
            }
          }

          // Global guard: if no server is connected at all, fall back
          // to the home screen / server list.
          final isAuthenticated =
              _serverManager.authState.value is Authenticated;
          if (!isAuthenticated) return AppRoutes.home;
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
