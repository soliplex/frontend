import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'app_module.dart';
import 'inactivity/inactivity_config.dart';
import 'router.dart';
import 'status_message_config.dart';

class ShellConfig {
  final String appName;
  final ThemeData lightTheme;
  final ThemeData? darkTheme;
  final ThemeMode themeMode;
  final String initialRoute;
  final Listenable? refreshListenable;
  final InactivityConfig inactivity;
  final StatusMessageConfig statusMessage;

  /// Tears down every module's `onDispose` in reverse registration order.
  ///
  /// **Caller responsibility.** The shell widget does not invoke this —
  /// it owns neither the config nor the modules. Callers that need
  /// deterministic teardown (tests, embedded library consumers, future
  /// lifecycle-owner wrappers) must `await shellConfig.dispose()`
  /// themselves. Standalone apps (`runSoliplexShell` + process exit)
  /// rely on OS reclamation.
  final Future<void> Function() dispose;

  final List<RouteBase> _routes;
  final List<Override> _overrides;
  final List<GoRouterRedirect> _redirects;
  final Set<String> _publicPaths;

  ShellConfig._internal({
    required this.appName,
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
    required this.initialRoute,
    required List<RouteBase> routes,
    required List<Override> overrides,
    required List<GoRouterRedirect> redirects,
    required Set<String> publicPaths,
    required this.refreshListenable,
    required this.inactivity,
    required this.statusMessage,
    required this.dispose,
  })  : _routes = List.unmodifiable(routes),
        _overrides = List.unmodifiable(overrides),
        _redirects = List.unmodifiable(redirects),
        _publicPaths = Set.unmodifiable(publicPaths);

  List<RouteBase> get routes => _routes;
  List<Override> get overrides => _overrides;
  List<GoRouterRedirect> get redirects => _redirects;

  /// Paths every module declared reachable without a session, composed.
  Set<String> get publicPaths => _publicPaths;

  /// Creates a [ShellConfig] from a list of [AppModule] instances.
  ///
  /// Calls [AppModule.build] on each module in registration order to
  /// collect routes and overrides. The returned config's [dispose] runs
  /// [AppModule.onDispose] in reverse registration order; invoking it is
  /// the caller's responsibility (see [dispose]).
  ///
  /// The passed [modules] are consumed here — do not reuse the same live
  /// instances across two calls, or both configs' [dispose] will run over
  /// them.
  ///
  /// Throws [ArgumentError] when a theme lacks the [SoliplexTheme] extension,
  /// a namespace is duplicated, or the route configuration is invalid —
  /// an invalid [ShellConfig] cannot be constructed. A route-configuration
  /// throw happens after the modules are built, so it tears them down on the
  /// way out; the [modules] are spent either way.
  static ShellConfig fromModules({
    required List<AppModule> modules,
    required String appName,
    required ThemeData lightTheme,
    ThemeData? darkTheme,
    ThemeMode themeMode = ThemeMode.system,
    String initialRoute = '/',
    String? signedOutLandingPath,
    Listenable? refreshListenable,
    InactivityConfig inactivity = const InactivityConfig(),
    StatusMessageConfig statusMessage = const StatusMessageConfig(),
  }) {
    if (lightTheme.extension<SoliplexTheme>() == null) {
      throw ArgumentError(
        'The lightTheme is missing the SoliplexTheme extension. Build it with '
        'buildSoliplexThemeData(...), not a bare ThemeData(...).',
      );
    }
    if (darkTheme != null && darkTheme.extension<SoliplexTheme>() == null) {
      throw ArgumentError(
        'The darkTheme is missing the SoliplexTheme extension. Build it with '
        'buildSoliplexThemeData(...), not a bare ThemeData(...).',
      );
    }
    final coordinator = _AppModuleCoordinator(modules);
    final routes = coordinator.routes;
    final routeErrors = [
      ...validateRoutes(
        routes: routes,
        initialRoute: initialRoute,
        publicPaths: coordinator.publicPaths,
        signedOutLandingPath: signedOutLandingPath,
      ),
      ...validateModulePublicPaths(coordinator.contributions),
    ];
    if (routeErrors.isNotEmpty) {
      // The routes just rejected came from modules that are already built, so
      // they hold live resources — a ServerManager, HTTP clients, an
      // inspector. No ShellConfig is returned, so nothing else can ever reach
      // their onDispose, and Flavor refuses a second build over the same
      // instances. Teardown is fired here and not awaited, because this
      // constructor is synchronous; a failure inside it is recorded rather
      // than raised, so it cannot arrive alongside — and obscure — the
      // ArgumentError that is the actual diagnosis.
      unawaited(
        coordinator.disposeAll().catchError(
              (Object e, StackTrace s) =>
                  LogManager.instance.getLogger('shell').warning(
                        'Module teardown after an invalid route configuration failed',
                        attributes: {'failure': describeFailure(e)},
                        stackTrace: s,
                      ),
            ),
      );
      // The throw aborts boot before any screen exists, and an ArgumentError
      // carrying no `name` renders as the bare type in the uncaught-error
      // record — so the paths that name the fault would otherwise reach only
      // the platform console. Route paths are authored in code, not
      // supplied by a user or the backend, so they are safe to record.
      LogManager.instance.getLogger('shell').error(
        'Invalid route configuration',
        attributes: {'errors': routeErrors.join('; ')},
      );
      throw ArgumentError(
        'Invalid route configuration:\n${routeErrors.join('\n')}',
      );
    }
    return ShellConfig._internal(
      appName: appName,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      initialRoute: initialRoute,
      routes: routes,
      overrides: coordinator.overrides,
      redirects: coordinator.redirects,
      publicPaths: coordinator.publicPaths,
      refreshListenable: refreshListenable,
      inactivity: inactivity,
      statusMessage: statusMessage,
      dispose: coordinator.disposeAll,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal coordinator — not part of the public API.
// ---------------------------------------------------------------------------

class _AppModuleCoordinator {
  _AppModuleCoordinator(List<AppModule> modules) {
    final seen = <String>{};
    for (final m in modules) {
      if (m.namespace.isNotEmpty && !seen.add(m.namespace)) {
        throw ArgumentError('Duplicate AppModule namespace: "${m.namespace}"');
      }
    }
    _modules = List.unmodifiable(modules);
    _built = _modules.map((m) => m.build()).toList(growable: false);
  }

  late final List<AppModule> _modules;
  late final List<ModuleRoutes> _built;

  Future<void> disposeAll() async {
    for (final m in _modules.reversed) {
      await m.onDispose();
    }
  }

  List<RouteBase> get routes => _built.expand((r) => r.routes).toList();

  List<Override> get overrides => _built.expand((r) => r.overrides).toList();

  List<GoRouterRedirect> get redirects =>
      _built.map((r) => r.redirect).nonNulls.toList();

  /// Computed once: fromModules reads this twice — to validate and to store —
  /// and a getter that recomputed would make those two different sets.
  late final Set<String> publicPaths =
      _built.expand((r) => r.publicPaths).toSet();

  /// Each module's contribution paired with the namespace that made it, so a
  /// declaration can be attributed back to its author.
  List<({String namespace, ModuleRoutes contribution})> get contributions => [
        for (var i = 0; i < _modules.length; i++)
          (namespace: _modules[i].namespace, contribution: _built[i]),
      ];
}
