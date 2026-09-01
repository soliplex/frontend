import 'package:flutter/widgets.dart' show BuildContext;
import 'package:go_router/go_router.dart';

import 'app_module.dart';
import 'shell_config.dart';

final _paramPattern = RegExp(r':[^/]+');

/// Validates route configuration and returns a list of error descriptions.
/// An empty list means the configuration is valid.
///
/// [initialRoute] must be a literal path (no parameterized segments).
List<String> validateRoutes({
  required List<RouteBase> routes,
  required String initialRoute,
  Set<String> publicPaths = const {},
}) {
  if (routes.isEmpty) {
    return ['Configuration must define at least one route'];
  }

  final errors = <String>[];
  final paths = _collectPaths(routes, '');

  // Check for duplicate paths
  final seen = <String>{};
  for (final path in paths) {
    if (!seen.add(path)) {
      errors.add('Duplicate route path: "$path"');
    }
  }

  if (_paramPattern.hasMatch(initialRoute)) {
    errors.add(
      'initialRoute "$initialRoute" contains parameterized segments — '
      'it must be a concrete path (e.g. "/users/123", not "/users/:id")',
    );
    return errors;
  }

  final normalizedInitial = _canonicalPath(initialRoute);
  if (!paths.contains(normalizedInitial)) {
    errors.add(
      'Initial route "$initialRoute" does not match any defined route. '
      'Available: ${paths.join(', ')}',
    );
  }

  for (final path in publicPaths) {
    // A top-level redirect reports the requested path with a leading slash,
    // one trailing slash removed, and no query or fragment — so any other
    // shape can never be compared against it. A ':' segment is the subtle
    // one: _canonicalPath normalises it on both sides, so an existence check
    // alone would accept a pattern that no concrete request ever equals.
    if (!path.startsWith('/') ||
        (path != '/' && path.endsWith('/')) ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains(':')) {
      errors.add(
        'Public path "$path" can never match a request. It must be a bare '
        'path: a leading slash, no trailing slash, and no query, fragment or '
        'parameterized segment.',
      );
      continue;
    }
    if (!paths.contains(_canonicalPath(path))) {
      errors.add(
        'Public path "$path" does not match any defined route. '
        'Available: ${paths.join(', ')}',
      );
    }
  }

  return errors;
}

/// Validates that each module declares only its own routes public, and returns
/// a list of error descriptions. An empty list means every declaration is the
/// declaring module's to make.
///
/// [validateRoutes] sees the flavor's routes already merged, so it can only ask
/// whether a path exists somewhere in the config. That admits a module opening
/// a screen another module builds — a security judgement about code the
/// declaring module does not own, which is the arrangement `publicPaths`
/// exists to end. This asks the narrower question its doc comment promises.
List<String> validateModulePublicPaths(
  List<({String namespace, ModuleRoutes contribution})> modules,
) {
  final errors = <String>[];
  for (final module in modules) {
    if (module.contribution.publicPaths.isEmpty) continue;
    final own = _collectPaths(module.contribution.routes, '').toSet();
    for (final path in module.contribution.publicPaths) {
      if (own.contains(_canonicalPath(path))) continue;
      final name = module.namespace.isEmpty
          ? 'an anonymous module'
          : 'module "${module.namespace}"';
      errors.add(
        'Public path "$path" is declared by $name, which does not register '
        'it. A module may only declare its own routes reachable without a '
        'session.',
      );
    }
  }
  return errors;
}

List<String> _collectPaths(List<RouteBase> routes, String parentPath) {
  final paths = <String>[];
  for (final route in routes) {
    if (route is GoRoute) {
      final fullPath = _joinPath(parentPath, route.path);
      paths.add(_canonicalPath(fullPath));
      paths.addAll(_collectPaths(route.routes, fullPath));
    } else if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        paths.addAll(_collectPaths(branch.routes, parentPath));
      }
    } else if (route is ShellRoute) {
      paths.addAll(_collectPaths(route.routes, parentPath));
    }
  }
  return paths;
}

String _joinPath(String parent, String segment) {
  if (segment.isEmpty) return parent;
  if (segment.startsWith('/')) return segment;
  if (parent.isEmpty) return '/$segment';
  final base =
      parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent;
  return '$base/$segment';
}

String _canonicalPath(String path) {
  // Strip trailing slash (except for root)
  var normalized = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  // Normalize parameterized segments: :anything -> :_
  normalized = normalized.replaceAll(_paramPattern, ':_');
  return normalized;
}

/// Creates a [GoRouter] from a [ShellConfig].
///
/// All module redirects collapse into a single GoRouter redirect slot —
/// they are evaluated in module order and the first non-null result wins.
///
/// Routes are non-empty and consistent with `initialRoute` by construction:
/// [ShellConfig.fromModules] rejects configs that fail [validateRoutes].
GoRouter buildRouter(ShellConfig config) {
  return GoRouter(
    initialLocation: config.initialRoute,
    routes: config.routes,
    refreshListenable: config.refreshListenable,
    redirect: config.redirects.isEmpty
        ? null
        : (BuildContext context, GoRouterState state) async {
            // A declared public path runs no global redirect at all; a route's
            // own redirect is attached per GoRoute and still applies.
            if (config.publicPaths.contains(state.matchedLocation)) return null;
            for (final redirect in config.redirects) {
              final result = await redirect(context, state);
              if (result != null) return result;
            }
            return null;
          },
  );
}
