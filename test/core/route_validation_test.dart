import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/router.dart';

import 'route_module.dart';

GoRoute _route(String path, {List<RouteBase> routes = const []}) =>
    GoRoute(path: path, builder: (_, __) => const SizedBox(), routes: routes);

void main() {
  _buildRouterTests();
  _publicPathTests();

  group('validateRoutes', () {
    test('returns empty list for valid routes', () {
      final errors = validateRoutes(
        routes: [_route('/a'), _route('/b')],
        initialRoute: '/a',
      );

      expect(errors, isEmpty);
    });

    test('returns error for empty routes', () {
      final errors = validateRoutes(routes: [], initialRoute: '/');

      expect(errors, hasLength(1));
      expect(errors.first, contains('at least one route'));
    });

    test('detects duplicate paths', () {
      final errors = validateRoutes(
        routes: [_route('/a'), _route('/a')],
        initialRoute: '/a',
      );

      expect(errors, hasLength(1));
      expect(errors.first, contains('Duplicate'));
    });

    test('detects duplicate paths after parameterized normalization', () {
      final errors = validateRoutes(
        routes: [
          _route('/a'),
          _route('/users/:id'),
          _route('/users/:userId'),
        ],
        initialRoute: '/a',
      );

      expect(errors, contains(contains('Duplicate')));
    });

    test('detects missing initial route when routes are non-empty', () {
      final errors = validateRoutes(
        routes: [_route('/a'), _route('/b')],
        initialRoute: '/missing',
      );

      expect(errors, hasLength(1));
      expect(errors.first, contains('Initial route'));
    });

    test('returns only empty-routes error when routes are empty', () {
      final errors = validateRoutes(routes: [], initialRoute: '/missing');

      expect(errors, hasLength(1));
      expect(errors.first, contains('at least one route'));
    });

    test('validates nested routes with full absolute paths', () {
      final errors = validateRoutes(
        routes: [
          _route('/parent', routes: [_route('child')]),
        ],
        initialRoute: '/parent',
      );

      expect(errors, isEmpty);
    });

    test('detects duplicate nested paths', () {
      final errors = validateRoutes(
        routes: [
          _route('/parent', routes: [_route('child')]),
          _route('/parent/child'),
        ],
        initialRoute: '/parent',
      );

      expect(errors, hasLength(1));
      expect(errors.first, contains('Duplicate'));
    });

    test('initial route matches nested path', () {
      final errors = validateRoutes(
        routes: [
          _route('/parent', routes: [_route('child')]),
        ],
        initialRoute: '/parent/child',
      );

      expect(errors, isEmpty);
    });

    test('handles ShellRoute - passes parent path through', () {
      final errors = validateRoutes(
        routes: [
          ShellRoute(
            builder: (_, __, child) => child,
            routes: [_route('/a'), _route('/b')],
          ),
        ],
        initialRoute: '/a',
      );

      expect(errors, isEmpty);
    });

    test('handles StatefulShellRoute - iterates branches', () {
      final errors = validateRoutes(
        routes: [
          StatefulShellRoute.indexedStack(
            branches: [
              StatefulShellBranch(routes: [_route('/tab1')]),
              StatefulShellBranch(routes: [_route('/tab2')]),
            ],
            builder: (_, __, child) => child,
          ),
        ],
        initialRoute: '/tab1',
      );

      expect(errors, isEmpty);
    });

    test('detects duplicates across StatefulShellRoute branches', () {
      final errors = validateRoutes(
        routes: [
          StatefulShellRoute.indexedStack(
            branches: [
              StatefulShellBranch(routes: [_route('/tab')]),
              StatefulShellBranch(routes: [_route('/tab')]),
            ],
            builder: (_, __, child) => child,
          ),
        ],
        initialRoute: '/tab',
      );

      expect(errors, hasLength(1));
      expect(errors.first, contains('Duplicate'));
    });

    test('rejects parameterized initialRoute', () {
      final errors = validateRoutes(
        routes: [_route('/users/:id')],
        initialRoute: '/users/:id',
      );

      expect(errors, hasLength(1));
      expect(errors.first, contains('initialRoute'));
    });

    test('accumulates multiple errors in a single call', () {
      final errors = validateRoutes(
        routes: [_route('/a'), _route('/a')],
        initialRoute: '/missing',
      );

      expect(errors, hasLength(2));
      expect(errors, contains(contains('Duplicate')));
      expect(errors, contains(contains('Initial route')));
    });

    // GoRoute 17.x asserts path.isNotEmpty, so empty child paths
    // cannot be constructed. Validation of empty paths is handled
    // by GoRouter itself.

    test('trailing slash normalization', () {
      final errors = validateRoutes(
        routes: [_route('/a'), _route('/a/')],
        initialRoute: '/a',
      );

      expect(errors, hasLength(1));
      expect(errors.first, contains('Duplicate'));
    });
  });
}

void _publicPathTests() {
  test('rejects a public path that names no route', () {
    final errors = validateRoutes(
      routes: [_route('/')],
      initialRoute: '/',
      publicPaths: const {'/nope'},
    );

    expect(errors.single, contains('/nope'));
  });

  test('rejects a public path that could never match', () {
    // Each form is unmatchable against the requested path a top-level redirect
    // reports: it arrives with a leading slash, one trailing slash removed, and
    // no query or fragment. '/i/:step' is the case an existence check alone
    // misses — _canonicalPath normalises both sides to ':_'.
    for (final bad in ['welcome', '/welcome/', '/w?a=1', '/w#x', '/i/:step']) {
      expect(
        validateRoutes(
          routes: [_route('/'), _route('/i/:step')],
          initialRoute: '/',
          publicPaths: {bad},
        ),
        isNotEmpty,
        reason: bad,
      );
    }
  });

  test('accepts a public path that names a registered route', () {
    expect(
      validateRoutes(
        routes: [_route('/'), _route('/welcome')],
        initialRoute: '/',
        publicPaths: const {'/', '/welcome'},
      ),
      isEmpty,
    );
  });

  test('rejects a module declaring a path it does not register', () {
    // The route exists, so the whole-config check above passes it. What must
    // not pass is one module making a no-session claim about a screen another
    // module builds — the centralisation this design exists to remove.
    final errors = validateModulePublicPaths([
      (
        namespace: 'auth',
        contribution: ModuleRoutes(
          routes: [_route('/')],
          publicPaths: const {'/versions'},
        ),
      ),
      (
        namespace: 'versions',
        contribution: ModuleRoutes(routes: [_route('/versions')]),
      ),
    ]);

    // The path names the innocent module, so the message has to name the
    // declaring one or it sends the reader to the wrong file.
    expect(errors.single, contains('/versions'));
    expect(errors.single, contains('auth'));
  });

  test('accepts a module declaring a path it registers itself', () {
    expect(
      validateModulePublicPaths([
        (
          namespace: 'auth',
          contribution: ModuleRoutes(
            routes: [_route('/')],
            publicPaths: const {'/'},
          ),
        ),
        (
          namespace: 'versions',
          contribution: ModuleRoutes(
            routes: [_route('/versions')],
            publicPaths: const {'/versions'},
          ),
        ),
      ]),
      isEmpty,
    );
  });

  test('a module owns the paths nested under its own routes', () {
    // _collectPaths descends, so a child route is the parent module's to
    // declare — otherwise a module could not open a subtree it registered.
    expect(
      validateModulePublicPaths([
        (
          namespace: 'onboarding',
          contribution: ModuleRoutes(
            routes: [
              _route('/', routes: [_route('intro')]),
            ],
            publicPaths: const {'/intro'},
          ),
        ),
      ]),
      isEmpty,
    );
  });
}

void _buildRouterTests() {
  testWidgets('a public path bypasses global redirects', (tester) async {
    final config = ShellConfig.fromModules(
      modules: [
        RouteModule(
          const ['/', '/open', '/other', '/blocked'],
          publicPaths: const {'/open'},
        ),
        _AlwaysBlocks(),
      ],
      appName: 'Test',
      lightTheme: buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      ),
    );
    final router = buildRouter(config);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('/open');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/open');

    router.go('/other');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/blocked');
  });
}

class _AlwaysBlocks extends AppModule {
  @override
  String get namespace => 'blocks';

  @override
  ModuleRoutes build() => ModuleRoutes(redirect: (_, state) => '/blocked');
}
