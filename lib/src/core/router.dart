import 'package:go_router/go_router.dart';

import 'app_module.dart';
import 'shell_config.dart';

final _paramPattern = RegExp(r':[^/]+');

/// Validates route configuration and returns a list of error descriptions.
/// An empty list means the routes, [initialRoute] and [signedOutLandingPath]
/// are valid. The entries of [publicPaths] are not judged here — by this point
/// they are a merged set with no module to attribute a fault to, which is
/// [validateModulePublicPaths]' question. [publicPaths] is taken only to answer
/// whether the landing path is among them. [ShellConfig.fromModules] asks
/// both.
///
/// [initialRoute] must be a literal path (no parameterized segments).
/// [signedOutLandingPath], when given, must name a registered route that some
/// module declared public — the sign-in guard would otherwise bounce a
/// signed-out launch straight off it.
List<String> validateRoutes({
  required List<RouteBase> routes,
  required String initialRoute,
  Set<String> publicPaths = const {},
  String? signedOutLandingPath,
}) {
  if (routes.isEmpty) {
    return ['Configuration must define at least one route'];
  }

  final errors = <String>[];
  final paths = _collectPaths(routes, '', errors);

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

  if (signedOutLandingPath != null) {
    // Checked on every launch, not only the signed-out ones. Both mistakes
    // here — a typo, and forgetting to declare the route public — otherwise
    // show up as "my screen does not appear", and only to whoever happens to
    // launch without a connected server. Neither depends on the auth state,
    // so neither needs to wait for it.
    if (!_isBarePath(signedOutLandingPath)) {
      // Before the existence check, not after: _canonicalPath normalises a
      // ':param' on both sides, so a route pattern would pass that check and
      // fall through to the public-path branch, whose advice — declare it
      // public — the shape rule forbids. Advice that cannot be followed costs
      // a whole edit-and-boot cycle to discover.
      errors.add(_notBarePath('signedOutLandingPath', signedOutLandingPath));
    } else if (!paths.contains(_canonicalPath(signedOutLandingPath))) {
      errors.add(
        'signedOutLandingPath "$signedOutLandingPath" does not match any '
        'defined route. Available: ${paths.join(', ')}',
      );
    } else if (!publicPaths.contains(_canonicalPath(signedOutLandingPath))) {
      errors.add(
        'signedOutLandingPath "$signedOutLandingPath" is not declared '
        'reachable without a session, so the sign-in guard would bounce a '
        'signed-out launch straight off it. Add it to the publicPaths of the '
        'module that registers it.',
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
    final name = module.namespace.isEmpty
        ? 'an anonymous module'
        : 'module "${module.namespace}"';
    for (final path in module.contribution.publicPaths) {
      if (!_isBarePath(path)) {
        errors.add('${_notBarePath('Public path', path)} Declared by $name.');
        continue;
      }
      if (own.contains(_canonicalPath(path))) continue;
      // The module's own routes, not the whole flavor's: the answer to a typo
      // is always in this list, and every other route is noise in front of it.
      errors.add(
        'Public path "$path" is declared by $name, which registers '
        '${own.isEmpty ? 'no routes' : own.join(', ')}. A module may only '
        'declare its own routes reachable without a session.',
      );
    }
  }
  return errors;
}

/// Whether [path] has the shape a request is reported in: a leading slash, no
/// trailing slash, and no query, fragment or parameterized segment. A
/// top-level redirect reports the requested path already normalised that way.
///
/// Necessary, not sufficient — a requested path also arrives percent-encoded,
/// so a literal containing a character a request would escape passes here and
/// still matches nothing. That route is unreachable through go_router either
/// way, so the mismatch is indistinguishable from the route not working.
///
/// The ':' clause is the subtle one — [_canonicalPath] normalises a parameter
/// on both sides, so an existence check alone would accept a route pattern that
/// no concrete request ever equals.
bool _isBarePath(String path) =>
    path.startsWith('/') &&
    (path == '/' || !path.endsWith('/')) &&
    !path.contains('?') &&
    !path.contains('#') &&
    !path.contains(':');

String _notBarePath(String label, String path) =>
    '$label "$path" can never match a request. It must be a bare path: a '
    'leading slash, no trailing slash, and no query, fragment or '
    'parameterized segment.';

/// Collects every path a route tree registers, canonicalised.
///
/// Appends to [errors], when given, for a top-level route whose path omits its
/// leading slash. go_router requires one and validates it nowhere — not even
/// under an assert — so such a route never matches, in any build mode, while
/// [_joinPath] repairs the omission here and leaves the collected path looking
/// like one the router serves. An empty [parentPath] is exactly go_router's
/// notion of top level, shell routes included, since they pass the parent
/// through unchanged.
List<String> _collectPaths(
  List<RouteBase> routes,
  String parentPath, [
  List<String>? errors,
]) {
  final paths = <String>[];
  for (final route in routes) {
    if (route is GoRoute) {
      if (parentPath.isEmpty && !route.path.startsWith('/')) {
        errors?.add(
          'Route path "${route.path}" is registered at the top level and must '
          'begin with a leading slash. Only a route nested under another may '
          'be relative.',
        );
      }
      final fullPath = _joinPath(parentPath, route.path);
      paths.add(_canonicalPath(fullPath));
      paths.addAll(_collectPaths(route.routes, fullPath, errors));
    } else if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        paths.addAll(_collectPaths(branch.routes, parentPath, errors));
      }
    } else if (route is ShellRoute) {
      paths.addAll(_collectPaths(route.routes, parentPath, errors));
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
/// [ShellConfig.redirect] is the whole redirect story — every module's,
/// composed, behind the check that admits a declared public path first. A
/// route's own redirect is attached per [GoRoute] and always applies.
///
/// Routes are non-empty and consistent with `initialRoute` by construction:
/// [ShellConfig.fromModules] rejects configs that fail [validateRoutes].
GoRouter buildRouter(ShellConfig config) => GoRouter(
      initialLocation: config.initialRoute,
      routes: config.routes,
      refreshListenable: config.refreshListenable,
      redirect: config.redirect,
    );
