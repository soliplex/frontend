import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import 'app_module.dart';
import 'router.dart';

/// A static bag of routes, overrides, and an optional redirect contributed
/// by a module.
///
/// Deprecated. Implement [AppModule] and use [ShellConfig.fromModules]
/// instead. [ModuleContribution] will be removed once all consumers have
/// migrated.
@Deprecated(
  'Implement AppModule and use ShellConfig.fromModules instead. '
  'ModuleContribution will be removed once all consumers have migrated.',
)
class ModuleContribution {
  final List<RouteBase> routes;
  final List<Override> overrides;
  final GoRouterRedirect? redirect;

  ModuleContribution({
    List<RouteBase> routes = const [],
    List<Override> overrides = const [],
    this.redirect,
  })  : routes = List.unmodifiable(routes),
        overrides = List.unmodifiable(overrides);
}

class ShellConfig {
  final String appName;
  final Widget? logo;
  final ThemeData theme;
  final String initialRoute;
  final Listenable? refreshListenable;
  final VoidCallback? onDispose;

  final List<RouteBase> _routes;
  final List<Override> _overrides;
  final List<GoRouterRedirect> _redirects;

  /// Deprecated. Use [ShellConfig.fromModules] with [AppModule] classes
  /// instead. This constructor will be removed once all consumers have
  /// migrated.
  // ignore: deprecated_member_use_from_same_package
  @Deprecated(
    'Use ShellConfig.fromModules with AppModule classes instead. '
    'This constructor will be removed once all consumers have migrated.',
  )
  // ignore: deprecated_member_use_from_same_package
  ShellConfig({
    required this.appName,
    this.logo,
    required this.theme,
    this.initialRoute = '/',
    // ignore: deprecated_member_use_from_same_package
    List<ModuleContribution> modules = const [],
    this.refreshListenable,
    this.onDispose,
    // ignore: deprecated_member_use_from_same_package
  })  : _routes = modules.expand((m) => m.routes).toList(),
        // ignore: deprecated_member_use_from_same_package
        _overrides = modules.expand((m) => m.overrides).toList(),
        // ignore: deprecated_member_use_from_same_package
        _redirects = modules.map((m) => m.redirect).nonNulls.toList();

  ShellConfig._internal({
    required this.appName,
    this.logo,
    required this.theme,
    this.initialRoute = '/',
    required List<RouteBase> routes,
    required List<Override> overrides,
    required List<GoRouterRedirect> redirects,
    this.refreshListenable,
    this.onDispose,
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
  /// Calls [AppModule.build] on each module to collect routes and overrides,
  /// then calls [AppModule.onAttach] in descending [AppModule.priority] order.
  /// When the shell is disposed, calls [AppModule.onDispose] in reverse
  /// registration order.
  static Future<ShellConfig> fromModules({
    required List<AppModule> modules,
    required String appName,
    Widget? logo,
    required ThemeData theme,
    String initialRoute = '/',
    Listenable? refreshListenable,
  }) async {
    final coordinator = _AppModuleCoordinator(modules);
    await coordinator.attachAll();
    return ShellConfig._internal(
      appName: appName,
      logo: logo,
      theme: theme,
      initialRoute: initialRoute,
      routes: coordinator.routes,
      overrides: coordinator.overrides,
      redirects: coordinator.redirects,
      refreshListenable: refreshListenable,
      onDispose: () => unawaited(coordinator.disposeAll()),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal coordinator — not part of the public API.
// ---------------------------------------------------------------------------

class _AppModuleCoordinator implements AppModuleContext {
  _AppModuleCoordinator(List<AppModule> modules) {
    final seen = <String>{};
    for (final m in modules) {
      if (m.namespace.isNotEmpty && !seen.add(m.namespace)) {
        throw StateError('Duplicate AppModule namespace: "${m.namespace}"');
      }
    }
    _modules = List.unmodifiable(modules);
  }

  late final List<AppModule> _modules;
  List<ModuleRoutes>? _built;

  List<ModuleRoutes> get _builtModules =>
      _built ??= _modules.map((m) => m.build(this)).toList();

  @override
  T? module<T extends AppModule>() {
    for (final m in _modules) {
      if (m is T) return m;
    }
    return null;
  }

  Future<void> attachAll() async {
    _built = _modules.map((m) => m.build(this)).toList();
    final sorted = [..._modules]
      ..sort((a, b) => b.priority.compareTo(a.priority));
    for (final m in sorted) {
      await m.onAttach(this);
    }
  }

  Future<void> disposeAll() async {
    for (final m in _modules.reversed) {
      await m.onDispose();
    }
  }

  List<RouteBase> get routes => _builtModules.expand((r) => r.routes).toList();

  List<Override> get overrides =>
      _builtModules.expand((r) => r.overrides).toList();

  List<GoRouterRedirect> get redirects =>
      _builtModules.map((r) => r.redirect).nonNulls.toList();
}
