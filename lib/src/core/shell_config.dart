import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

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
  final ThemeData theme;
  final String initialRoute;
  final List<ModuleContribution> modules;

  ShellConfig({
    required this.appName,
    required this.theme,
    this.initialRoute = '/',
    List<ModuleContribution> modules = const [],
  }) : modules = List.unmodifiable(modules);

  List<RouteBase> get routes => modules.expand((m) => m.routes).toList();

  List<Override> get overrides => modules.expand((m) => m.overrides).toList();

  List<GoRouterRedirect> get redirects =>
      modules.map((m) => m.redirect).nonNulls.toList();

  List<String> validate() => validateRoutes(
        routes: routes,
        initialRoute: initialRoute,
      );
}
