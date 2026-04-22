import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

/// Routes and Riverpod overrides contributed by an [AppModule].
///
/// Replaces the deprecated [ModuleContribution].
class ModuleRoutes {
  const ModuleRoutes({
    this.routes = const [],
    this.overrides = const [],
    this.redirect,
  });

  final List<RouteBase> routes;
  final List<Override> overrides;
  final GoRouterRedirect? redirect;
}

/// Context passed to [AppModule.build] and [AppModule.onAttach].
///
/// Enables cross-module discovery without hard coupling between modules.
/// Context passed to [AppModule.build] and [AppModule.onAttach].
///
/// Enables cross-module discovery without hard coupling between modules.
abstract interface class AppModuleContext {
  T? module<T extends AppModule>();
}

/// Lifecycle unit for a feature module.
///
/// Subclass and pass instances to [ShellConfig.fromModules] instead of using
/// the deprecated [ModuleContribution] function pattern. Modules declare
/// routes and overrides via [build] and release owned resources in
/// [onDispose].
abstract class AppModule {
  String get namespace;
  int get priority => 0;

  /// Declares the routes and overrides this module contributes.
  ///
  /// Called once during [ShellConfig.fromModules] initialisation, before
  /// [onAttach]. Use [ctx] to look up sibling modules if needed.
  ModuleRoutes build(AppModuleContext ctx);

  /// Called after all modules have been built, in descending [priority] order.
  Future<void> onAttach(AppModuleContext ctx) async {}

  /// Called when the shell is disposed, in reverse registration order.
  ///
  /// Release any resources owned by this module (HTTP clients, stream
  /// subscriptions, state objects, etc.).
  Future<void> onDispose() async {}
}
