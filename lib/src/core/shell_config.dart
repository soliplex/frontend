import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import 'app_module.dart';
import 'router.dart';

class ShellConfig {
  final String appName;
  final Widget? logo;
  final ThemeData theme;
  final ThemeData? darkTheme;
  final ThemeMode themeMode;
  final String initialRoute;
  final Listenable? refreshListenable;

  /// Tears down every module's `onDispose` in reverse registration order.
  ///
  /// **Caller responsibility.** The shell widget does not invoke this —
  /// it owns neither the config nor the modules. Callers that need
  /// deterministic teardown (tests, embedded library consumers, future
  /// lifecycle-owner wrappers) must `await shellConfig.dispose?.call()`
  /// themselves. Standalone apps (`runSoliplexShell` + process exit)
  /// rely on OS reclamation.
  final Future<void> Function()? dispose;

  final List<RouteBase> _routes;
  final List<Override> _overrides;
  final List<GoRouterRedirect> _redirects;

  ShellConfig._internal({
    required this.appName,
    this.logo,
    required this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.initialRoute = '/',
    required List<RouteBase> routes,
    required List<Override> overrides,
    required List<GoRouterRedirect> redirects,
    this.refreshListenable,
    this.dispose,
  })  : _routes = routes,
        _overrides = overrides,
        _redirects = redirects;

  List<RouteBase> get routes => _routes;
  List<Override> get overrides => _overrides;
  List<GoRouterRedirect> get redirects => _redirects;

  List<String> validate() => validateRoutes(
        routes: routes,
        initialRoute: initialRoute,
      );

  /// Creates a [ShellConfig] from a list of [AppModule] instances.
  ///
  /// Calls [AppModule.build] on each module in registration order to
  /// collect routes and overrides. When the shell is disposed, calls
  /// [AppModule.onDispose] in reverse registration order.
  static Future<ShellConfig> fromModules({
    required List<AppModule> modules,
    required String appName,
    Widget? logo,
    required ThemeData theme,
    ThemeData? darkTheme,
    ThemeMode themeMode = ThemeMode.system,
    String initialRoute = '/',
    Listenable? refreshListenable,
  }) async {
    final coordinator = _AppModuleCoordinator(modules);
    return ShellConfig._internal(
      appName: appName,
      logo: logo,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      initialRoute: initialRoute,
      routes: coordinator.routes,
      overrides: coordinator.overrides,
      redirects: coordinator.redirects,
      refreshListenable: refreshListenable,
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
        throw StateError('Duplicate AppModule namespace: "${m.namespace}"');
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
}
