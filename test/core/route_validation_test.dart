import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/router.dart';

GoRoute _route(String path, {List<RouteBase> routes = const []}) =>
    GoRoute(path: path, builder: (_, __) => const SizedBox(), routes: routes);

void main() {
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

    test('rejects a top-level route path with no leading slash', () {
      // go_router validates this nowhere, so such a route never matches in any
      // build mode. _joinPath repairs the collected path to '/welcome', so
      // every other check here passes — a landing path validated as good that
      // lands on "Page Not Found".
      final errors = validateRoutes(
        routes: [_route('/'), _route('welcome')],
        initialRoute: '/',
      );

      expect(errors.single, contains('welcome'));
      expect(errors.single, contains('leading slash'));
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
  test('rejects a signed-out landing path no module declared public', () {
    // The guard would bounce it on arrival, so naming it as the landing path
    // is a contradiction. This holds regardless of the current auth state, so
    // it is checked on every launch — not only the signed-out ones that would
    // otherwise be the first to notice.
    final errors = validateRoutes(
      routes: [_route('/'), _route('/welcome')],
      initialRoute: '/',
      publicPaths: const {'/'},
      signedOutLandingPath: '/welcome',
    );

    expect(errors.single, contains('/welcome'));
  });

  test('rejects a signed-out landing path that names no route', () {
    // isNotEmpty alone cannot fail here: with the existence branch gone the
    // public-path branch fires instead and the assertion still passes. Name
    // the message so the test is tied to the branch it is for.
    expect(
      validateRoutes(
        routes: [_route('/')],
        initialRoute: '/',
        publicPaths: const {'/'},
        signedOutLandingPath: '/wecome',
      ).single,
      contains('does not match any defined route'),
    );
  });

  test('accepts a signed-out landing path a module declared public', () {
    expect(
      validateRoutes(
        routes: [_route('/'), _route('/welcome')],
        initialRoute: '/',
        publicPaths: const {'/', '/welcome'},
        signedOutLandingPath: '/welcome',
      ),
      isEmpty,
    );
  });

  test('rejects a landing path in a form no request can match', () {
    // A ':param' pattern is the trap: _canonicalPath normalises it on both
    // sides, so it passes an existence check, and the public-path branch then
    // tells the reader to declare it public — which the shape rule forbids.
    // Advice that cannot be followed is worse than none.
    final errors = validateRoutes(
      routes: [_route('/'), _route('/room/:id')],
      initialRoute: '/',
      publicPaths: const {'/'},
      signedOutLandingPath: '/room/:id',
    );

    expect(errors.single, contains('can never match'));
    expect(errors.single, isNot(contains('publicPaths')));
  });

  test('rejects a public path the declaring module does not register', () {
    final errors = validateModulePublicPaths([
      (
        namespace: 'welcome',
        contribution: ModuleRoutes(
          routes: [_route('/welcome')],
          publicPaths: const {'/welcom'},
        ),
      ),
    ]);

    // One message, attributed, and listing the module's own routes — where the
    // answer to a typo always is. The whole flavor's route list is not.
    expect(errors.single, contains('/welcom'));
    expect(errors.single, contains('registers /welcome'));
  });

  test('rejects a public path in a form no request can match', () {
    // '/i/:step' is the case an existence check alone misses — _canonicalPath
    // normalises both sides to ':_', so it would appear to match.
    for (final bad in ['welcome', '/welcome/', '/w?a=1', '/w#x', '/i/:step']) {
      expect(
        validateModulePublicPaths([
          (
            namespace: 'fixture',
            contribution: ModuleRoutes(
              routes: [
                _route('/welcome'),
                _route('/w'),
                _route('/i/:step'),
              ],
              publicPaths: {bad},
            ),
          ),
        ]).single,
        contains('can never match'),
        reason: bad,
      );
    }
  });

  test('names an anonymous module as one', () {
    // AppModule permits an empty namespace, so a violation can come from a
    // module with no name to print. Saying "" would read as a bug.
    final errors = validateModulePublicPaths([
      (
        namespace: '',
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

    expect(errors.single, contains('an anonymous module'));
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
