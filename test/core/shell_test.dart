import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/core/app_module.dart';
import 'package:soliplex_frontend/src/core/shell.dart';
import 'package:soliplex_frontend/src/core/shell_config.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _TestModule extends AppModule {
  _TestModule({
    this.routes = const [],
    this.overrides = const [],
    this.redirect,
    this.namespace = '',
  });

  @override
  final String namespace;
  final List<RouteBase> routes;
  final List<Override> overrides;
  final GoRouterRedirect? redirect;

  @override
  ModuleRoutes build(AppModuleContext ctx) =>
      ModuleRoutes(routes: routes, overrides: overrides, redirect: redirect);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('runSoliplexShell', () {
    test('throws ArgumentError on invalid config', () async {
      final config = await ShellConfig.fromModules(
        appName: 'Test',
        theme: ThemeData(),
        modules: [],
      );

      expect(() => runSoliplexShell(config), throwsArgumentError);
    });
  });

  group('SoliplexShell', () {
    testWidgets('overrides from multiple modules compose', (tester) async {
      final greeting = Provider<String>((_) => 'default greeting');
      final farewell = Provider<String>((_) => 'default farewell');

      final config = await ShellConfig.fromModules(
        appName: 'Test',
        theme: ThemeData(),
        initialRoute: '/check',
        modules: [
          _TestModule(
            overrides: [greeting.overrideWithValue('hello')],
          ),
          _TestModule(
            overrides: [farewell.overrideWithValue('goodbye')],
            routes: [
              GoRoute(
                path: '/check',
                builder: (_, __) => Consumer(
                  builder: (_, ref, __) => Column(
                    children: [
                      Text(ref.watch(greeting)),
                      Text(ref.watch(farewell)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(SoliplexShell(config: config));
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('goodbye'), findsOneWidget);
    });
  });

  group('redirect composition', () {
    testWidgets('first non-null redirect wins', (tester) async {
      final config = await ShellConfig.fromModules(
        appName: 'Test',
        theme: ThemeData(),
        initialRoute: '/a',
        modules: [
          _TestModule(
            redirect: (context, state) =>
                state.matchedLocation == '/a' ? '/b' : null,
          ),
          _TestModule(
            redirect: (context, state) =>
                state.matchedLocation == '/a' ? '/c' : null,
          ),
          _TestModule(
            routes: [
              GoRoute(
                path: '/a',
                builder: (_, __) => const Text('Page A'),
              ),
              GoRoute(
                path: '/b',
                builder: (_, __) => const Text('Page B'),
              ),
              GoRoute(
                path: '/c',
                builder: (_, __) => const Text('Page C'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(SoliplexShell(config: config));
      await tester.pumpAndSettle();

      expect(find.text('Page B'), findsOneWidget);
    });
  });

  group('AppModuleCoordinator', () {
    test('duplicate namespace throws StateError', () async {
      expect(
        () => ShellConfig.fromModules(
          appName: 'Test',
          theme: ThemeData(),
          modules: [
            _TestModule(namespace: 'same'),
            _TestModule(namespace: 'same'),
          ],
        ),
        throwsStateError,
      );
    });

    test('empty namespace skips uniqueness check', () async {
      // Should not throw even though both modules have empty namespace.
      await ShellConfig.fromModules(
        appName: 'Test',
        theme: ThemeData(),
        modules: [
          _TestModule(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const SizedBox()),
            ],
          ),
          _TestModule(),
        ],
      );
    });

    test('onAttach and onDispose are called', () async {
      final log = <String>[];

      final module = _LifecycleModule(log);
      final config = await ShellConfig.fromModules(
        appName: 'Test',
        theme: ThemeData(),
        modules: [module],
      );

      expect(log, ['attach']);
      config.onDispose?.call();
      await Future<void>.delayed(Duration.zero); // let async dispose flush
      expect(log, ['attach', 'dispose']);
    });
  });
}

class _LifecycleModule extends AppModule {
  _LifecycleModule(this._log);

  final List<String> _log;

  @override
  String get namespace => 'lifecycle';

  @override
  ModuleRoutes build(AppModuleContext ctx) => const ModuleRoutes();

  @override
  Future<void> onAttach(AppModuleContext ctx) async => _log.add('attach');

  @override
  Future<void> onDispose() async => _log.add('dispose');
}
