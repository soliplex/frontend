import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import '../../core/shell_config.dart';
import '../../interfaces/auth_state.dart';
import 'auth_providers.dart';
import 'consent_notice.dart';
import 'platform/auth_flow.dart';
import 'platform/callback_params.dart';
import 'server_manager.dart';
import 'ui/auth_callback_screen.dart';
import 'ui/home_screen.dart';
import 'ui/server_list_screen.dart';

/// Public routes that don't require authentication.
const _publicPaths = {'/', '/servers', '/auth/callback'};

ModuleContribution authModule({
  required ServerManager serverManager,
  required AuthFlow authFlow,
  required SoliplexHttpClient probeClient,
  required String appName,
  CallbackParams? callbackParams,
  ConsentNotice? consentNotice,
  Widget? logo,
  String? defaultBackendUrl,
}) {
  return ModuleContribution(
    overrides: [
      serverManagerProvider.overrideWithValue(serverManager),
      authFlowProvider.overrideWithValue(authFlow),
      probeClientProvider.overrideWithValue(probeClient),
      if (callbackParams != null)
        callbackParamsProvider.overrideWithValue(callbackParams),
      if (consentNotice != null)
        consentNoticeProvider.overrideWithValue(consentNotice),
    ],
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (_, state) {
          final autoConnectUrl = state.uri.queryParameters['url'];
          return NoTransitionPage(
            key: autoConnectUrl != null ? UniqueKey() : state.pageKey,
            child: HomeScreen(
              serverManager: serverManager,
              appName: appName,
              logo: logo,
              defaultBackendUrl: defaultBackendUrl,
              autoConnectUrl: autoConnectUrl,
            ),
          );
        },
      ),
      GoRoute(
        path: '/servers',
        pageBuilder: (_, __) => NoTransitionPage(
          child: ServerListScreen(serverManager: serverManager),
        ),
      ),
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (_, __) => NoTransitionPage(
          child: AuthCallbackScreen(serverManager: serverManager),
        ),
      ),
    ],
    redirect: (_, state) {
      final isAuthenticated = serverManager.authState.value is Authenticated;
      final isPublic = _publicPaths.contains(state.matchedLocation);

      if (!isAuthenticated && !isPublic) return '/';
      return null;
    },
  );
}
