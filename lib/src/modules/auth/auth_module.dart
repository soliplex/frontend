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

const _publicPaths = {
  AppRoutes.home,
  AppRoutes.authCallback,
  AppRoutes.versions,
  // A user who cannot sign in is unauthenticated by definition, and this
  // screen is where the failure is visible. Guarding it would put the
  // diagnosis out of reach of exactly the session that needs it.
  //
  // What that exposes without a session: request metadata, already redacted at
  // capture (HttpRedactor replaces the values of Authorization, cookies and
  // token-bearing query parameters), and log records, which are not redacted
  // by anything.
  // Those carry server and discovery URLs, hostnames and token expiry times —
  // deployment detail, not credentials — and the release level floor keeps
  // them to warnings and above. Nothing enforces that, so a logger that starts
  // recording a secret makes it readable here.
  AppRoutes.diagnostics,
};

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
    Set<String> extraPublicPaths = const {},
  })  : assert(
          extraPublicPaths.every(
            (p) =>
                p.startsWith('/') &&
                (p == '/' || !p.endsWith('/')) &&
                !p.contains('?') &&
                !p.contains('#'),
          ),
          'An extraPublicPaths entry can never match unless it is a bare path '
          'with a leading slash and no trailing slash, query or fragment — a '
          'top-level redirect reports the requested path already normalized '
          'that way.',
        ),
        extraPublicPaths = Set.unmodifiable(extraPublicPaths),
        _serverManager = serverManager,
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

  /// Paths a flavor declared reachable without a session. Snapshotted, so a
  /// caller that keeps the set it passed cannot retune the guard later.
  @visibleForTesting
  final Set<String> extraPublicPaths;

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
          // go_router hands a top-level redirect the whole requested path,
          // with the query and one trailing slash already off it, so matching
          // it against a literal admits '/welcome' alone: '/welcome/admin' and
          // every '/welcome/:step' instance stay guarded. The entries are not
          // normalized in turn — an entry written '/welcome/' matches nothing.
          final isPublic = _publicPaths.contains(state.matchedLocation) ||
              extraPublicPaths.contains(state.matchedLocation);
          if (isPublic) return null;

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
