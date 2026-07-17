import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

/// Contributes one plain route per path, so a fixture config clears the
/// route guard in [ShellConfig.fromModules].
///
/// A route-less [ShellConfig] is unconstructible — [ShellConfig.fromModules]
/// throws when no module contributes routes. Fixtures exercising other axes
/// (field threading, theme guards, disposal order) use this module to
/// satisfy that invariant without dragging in feature modules.
class RouteModule extends AppModule {
  RouteModule(this.paths, {this.namespace = 'route-fixture'});

  final List<String> paths;

  @override
  final String namespace;

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          for (final path in paths)
            GoRoute(path: path, builder: (_, __) => const SizedBox()),
        ],
      );
}
