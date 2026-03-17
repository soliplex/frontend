import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_frontend/src/core/shell_config.dart';

void main() {
  group('ModuleContribution', () {
    test('defaults to empty routes and overrides', () {
      final module = ModuleContribution();

      expect(module.routes, isEmpty);
      expect(module.overrides, isEmpty);
      expect(module.redirect, isNull);
    });

    test('stores optional redirect', () {
      String? myRedirect(BuildContext context, GoRouterState state) => null;

      final module = ModuleContribution(redirect: myRedirect);

      expect(module.redirect, equals(myRedirect));
    });
  });

  group('ShellConfig', () {
    test('requires appName and theme', () {
      final config = ShellConfig(
        appName: 'Test',
        theme: ThemeData(),
      );

      expect(config.appName, 'Test');
      expect(config.theme, isA<ThemeData>());
      expect(config.initialRoute, '/');
      expect(config.modules, isEmpty);
    });

    test('allows custom initialRoute', () {
      final config = ShellConfig(
        appName: 'Test',
        theme: ThemeData(),
        initialRoute: '/home',
      );

      expect(config.initialRoute, '/home');
    });

    test('routes getter flattens module routes', () {
      final config = ShellConfig(
        appName: 'Test',
        theme: ThemeData(),
        modules: [
          ModuleContribution(routes: [
            GoRoute(path: '/a', builder: (_, __) => const SizedBox()),
          ]),
          ModuleContribution(routes: [
            GoRoute(path: '/b', builder: (_, __) => const SizedBox()),
            GoRoute(path: '/c', builder: (_, __) => const SizedBox()),
          ]),
        ],
      );

      expect(config.routes, hasLength(3));
    });

    test('overrides getter flattens module overrides', () {
      final p1 = Provider<int>((_) => 0);
      final p2 = Provider<String>((_) => '');

      final config = ShellConfig(
        appName: 'Test',
        theme: ThemeData(),
        modules: [
          ModuleContribution(overrides: [p1.overrideWithValue(1)]),
          ModuleContribution(overrides: [p2.overrideWithValue('hello')]),
        ],
      );

      expect(config.overrides, hasLength(2));
    });

    test('redirects getter collects non-null module redirects', () {
      String? r1(BuildContext context, GoRouterState state) => null;
      String? r2(BuildContext context, GoRouterState state) => '/login';

      final config = ShellConfig(
        appName: 'Test',
        theme: ThemeData(),
        modules: [
          ModuleContribution(redirect: r1),
          ModuleContribution(), // no redirect
          ModuleContribution(redirect: r2),
        ],
      );

      expect(config.redirects, hasLength(2));
      expect(config.redirects, containsAll([r1, r2]));
    });
  });
}
