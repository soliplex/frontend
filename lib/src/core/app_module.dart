import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

/// Routes and Riverpod overrides contributed by an [AppModule].
class ModuleRoutes {
  const ModuleRoutes({
    this.routes = const [],
    this.overrides = const [],
    this.redirect,
    this.publicPaths = const {},
  });

  final List<RouteBase> routes;
  final List<Override> overrides;
  final GoRouterRedirect? redirect;

  /// Paths this module's routes serve without a session. Each must name a
  /// route in [routes] — declaring another module's is rejected at boot, so
  /// the module making the claim is always the one that builds the screen.
  ///
  /// No global redirect runs for a path listed here; a route's own redirect
  /// still applies.
  final Set<String> publicPaths;
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
  ///
  /// [ShellConfig.fromModules] also calls it on every module when assembly
  /// aborts, which can be before this module's [build] ran — a duplicate
  /// namespace or a theme missing its extension is rejected first. Release
  /// what the constructor allocated; anything [build] creates has to tolerate
  /// being absent here.
  Future<void> onDispose() async {}
}
