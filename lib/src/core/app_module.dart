import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

/// Routes and Riverpod overrides contributed by an [AppModule].
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

/// Lifecycle unit for a feature module.
///
/// Subclass and pass instances to [ShellConfig.fromModules]. Modules
/// declare routes and overrides via [build] and release owned resources
/// in [onDispose].
abstract class AppModule {
  /// Identifier for this module. [ShellConfig.fromModules] rejects duplicates
  /// at construction; the empty string is exempt, so anonymous modules may
  /// coexist.
  String get namespace;

  /// Declares the routes and overrides this module contributes.
  ModuleRoutes build();

  /// Releases resources this module owns. [ShellConfig.dispose] calls it in
  /// reverse registration order; the shell widget never does.
  Future<void> onDispose() async {}
}
